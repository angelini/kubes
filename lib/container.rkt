#lang typed/racket

(require "exec.rkt"
         "utils.rkt"
         "volume.rkt")

(provide build-container
         container
         container-name
         container-tag
         container->hash
         create-container-dir
         dockerfile)

(define-type FileOrGenerator (U String (-> Path Void)))

(struct dockerfile ([base-image : String] [packages : (Listof String)] [working-dir : Path]
                    [env : (HashTable String String)] [files : (HashTable String FileOrGenerator)]
                    [run : (Listof String)] [cmd : (Listof String)]))

(: dockerfile->string (->* (dockerfile) (#:with-command Boolean) String))
(define (dockerfile->string dfile #:with-command [with-command #f])
  (define lines (list (format "FROM ~a" (dockerfile-base-image dfile))
                      (string-join (list "RUN apt-get update \\"
                                         (format " && apt-get install -y ~a \\"
                                                 (string-join (dockerfile-packages dfile) " "))
                                         " && rm -rf /var/lib/apt/lists/*")
                                   "\n")
                     (format "RUN mkdir -p ~a" (dockerfile-working-dir dfile))
                     (format "WORKDIR ~a" (dockerfile-working-dir dfile))
                     (string-join (map (lambda ([t : (Pairof String String)])
                                         (format "ENV ~a ~a" (car t) (cdr t)))
                                       (hash->list (dockerfile-env dfile)))
                                  "\n")
                     (when (not (empty? (dockerfile-run dfile)))
                       (format "RUN ~a"
                               (string-join (dockerfile-run dfile) " \\\n && ")))
                     (string-join (map (lambda (f) (format "COPY ~a ./~a" f f))
                                       (hash-keys (dockerfile-files dfile)))
                                  "\n")
                     (when with-command
                       (format "CMD [\"~a\"]"
                             (string-join (dockerfile-cmd dfile) "\", \"")))))
  (string-join (cast (filter (compose not void?) lines) (Listof String)) "\n\n"))

(struct container ([name : String] [image-version : String] [ports : (Listof Integer)]
                   [volumes : (HashTable String volume)] [dockerfile : dockerfile]))

(: create-dockerfile-files (-> Path container Void))
(define (create-dockerfile-files cont-dir cont)
  (map (lambda ([f : (Pairof String FileOrGenerator)])
         (match-let ([(cons name gen-or-contents) f])
           (if (procedure? gen-or-contents)
               (gen-or-contents cont-dir)
               (write-file cont-dir name gen-or-contents))))
       (hash->list (dockerfile-files (container-dockerfile cont))))
  (void))

(: container-tag (-> String container String))
(define (container-tag proj-name cont)
  (format "~a/~a:~a" proj-name (container-name cont) (container-image-version cont)))

(: container-dir (-> Path container Path))
(define (container-dir serv-dir cont)
  (build-path serv-dir "containers" (container-name cont)))

(: container->hash (->* (String container)
                        (#:with-ports Boolean #:with-command Boolean)
                        (HashTable String Any)))
(define (container->hash proj-name cont #:with-ports [with-ports #f] #:with-command [with-command #f])
  (define assocs : (Listof (U Void (Pairof String Any)))
    (list (cons "name" (container-name cont))
          (cons "image" (format "~a/~a:~a"
                                proj-name
                                (container-name cont) (container-image-version cont)))
          (when (not (empty? (container-volumes cont)))
            (cons "volumeMounts" (map (lambda ([v : (Pairof String volume)])
                                        (hash "mountPath" (car v)
                                              "name" (volume-name (cdr v))))
                                      (hash->list (container-volumes cont)))))
          (when with-ports
            (cons "ports" (map (lambda ([p : Integer]) (hash "containerPort" p))
                               (container-ports cont))))
          (when with-command
            (cons "command" (dockerfile-cmd (container-dockerfile cont))))))
  (make-immutable-hash (filter
                        (lambda ([p : (U Void (Pairof String Any))]) (pair? p))
                        assocs)))

(: create-container-dir (->* (Path container) (#:with-command Boolean) Path))
(define (create-container-dir serv-dir cont #:with-command [with-command #f])
  (define dir (build-path serv-dir (container-name cont)))
  (when (directory-exists? dir)
    (error 'directory-exists "~a" dir))
  (make-directory dir)
  (write-file dir "Dockerfile"
              (dockerfile->string (container-dockerfile cont) #:with-command with-command))
  (create-dockerfile-files dir cont)
  dir)

(: build-container (-> String Path container True))
(define (build-container proj-name serv-dir cont)
  (exec-streaming (container-dir serv-dir cont) "docker" "build" "-t" (container-tag proj-name cont) "."))
