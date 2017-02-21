#lang racket

(require "exec.rkt")

(provide build-container
         container
         container-name
         container-tag
         container->hash
         create-container-dir
         dockerfile)

(struct dockerfile (base-image packages working-dir env files run cmd))

(define (dockerfile->string dfile #:with-command [with-command #f])
  (define lines (list (format "FROM ~a" (dockerfile-base-image dfile))
                     (format "RUN apk add --no-cache \\\n    ~a"
                             (string-join (dockerfile-packages dfile) " \\\n    "))
                     (format "RUN mkdir -p ~a" (dockerfile-working-dir dfile))
                     (format "WORKDIR ~a" (dockerfile-working-dir dfile))
                     (string-join (map (lambda (t) (format "ENV ~a ~a" (car t) (cdr t)))
                                       (hash->list (dockerfile-env dfile)))
                                  "\n")
                     (string-join (map (lambda (f) (format "COPY ~a ./~a" f f))
                                       (hash-keys (dockerfile-files dfile)))
                                  "\n")
                     (when (not (empty? (dockerfile-run dfile)))
                       (format "RUN ~a"
                               (string-join (dockerfile-run dfile) " \\\n && ")))
                     (when with-command
                       (format "CMD [\"~a\"]"
                             (string-join (dockerfile-cmd dfile) "\", \"")))))
  (string-join (filter (compose not void?) lines) "\n\n"))

(define (create-dockerfile-files cont-dir cont)
  (map (lambda (f)
         (match-let ([(cons name gen-or-contents) f])
           (if (procedure? gen-or-contents)
               (gen-or-contents cont-dir)
               (call-with-output-file (build-path cont-dir name)
                 (lambda (out)
                   (display gen-or-contents out))))))
       (hash->list (dockerfile-files (container-dockerfile cont)))))


(struct container (name image-version port dockerfile))

(define (container-tag proj-name cont)
  (format "~a/~a:~a" proj-name (container-name cont) (container-image-version cont)))

(define (container-dir serv-dir cont)
  (build-path serv-dir (container-name cont)))

(define (container->hash proj-name cont #:with-ports [with-ports #f] #:with-command [with-command #f])
  (define assocs (list (cons "name" (container-name cont))
                       (cons "image" (format "~a/~a:~a"
                                             proj-name
                                             (container-name cont) (container-image-version cont)))
                       (when with-ports
                         (cons "ports" (list (hash "containerPort" (container-port cont)))))
                       (when with-command
                         (cons "command" (dockerfile-cmd (container-dockerfile cont))))))
  (make-immutable-hash (filter (compose not void?) assocs)))

(define (create-container-dir serv-dir cont #:with-command [with-command #f])
  (define dir (build-path serv-dir (container-name cont)))
  (when (directory-exists? dir)
    (error 'directory-exists "~a" dir))
  (make-directory dir)
  (call-with-output-file (build-path dir "Dockerfile")
    (lambda (out)
      (display (dockerfile->string (container-dockerfile cont) #:with-command with-command) out)))
  (create-dockerfile-files dir cont)
  dir)

(define (build-container proj-name serv-dir cont)
  (exec (container-dir serv-dir cont) "docker" "build" "-t" (container-tag proj-name cont) "."))
