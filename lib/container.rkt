#lang racket

(require "exec.rkt")

(provide build-container
         container
         container-name
         container-tag
         container->hash
         create-container-dir
         dockerfile)

(struct dockerfile (base-image packages working-dir files run cmd))

(define (dockerfile->string dfile)
  (string-join (list (format "FROM ~a" (dockerfile-base-image dfile))
                     (format "RUN apk add --no-cache \\\n    ~a"
                             (string-join (dockerfile-packages dfile) " \\\n    "))
                     (format "RUN mkdir -p ~a" (dockerfile-working-dir dfile))
                     (format "WORKDIR ~a" (dockerfile-working-dir dfile))
                     (string-join (map (lambda (f) (format "COPY ~a ." f))
                                       (hash-keys (dockerfile-files dfile)))
                                  "\n")
                     (format "RUN ~a"
                             (string-join (dockerfile-run dfile) " \\\n && "))
                     (format "CMD [\"~a\"]"
                             (string-join (dockerfile-cmd dfile) "\", \"")))
               "\n\n"))

(struct container (name image-version port dockerfile))

(define (container-tag proj-name cont)
  (format "~a/~a:~a" proj-name (container-name cont) (container-image-version cont)))

(define (container-dir serv-dir cont)
  (build-path serv-dir (container-name cont)))

(define (container->hash proj-name cont)
  (hash "name" (container-name cont)
        "image" (format "~a/~a:~a" proj-name (container-name cont) (container-image-version cont))
        "ports" (list (hash "containerPort" (container-port cont)))))

(define (create-container-dir serv-dir cont)
  (define dir (build-path serv-dir (container-name cont)))
  (when (directory-exists? dir)
    (error 'directory-exists "~a" dir))
  (make-directory dir)
  (call-with-output-file (build-path dir "Dockerfile")
    (lambda (out)
      (display (dockerfile->string (container-dockerfile cont)) out)))
  (map (lambda (f) (call-with-output-file (build-path dir (car f))
                     (lambda (out)
                       (display (cdr f) out))))
       (hash->list (dockerfile-files (container-dockerfile cont))))
  dir)

(define (build-container proj-name serv-dir cont)
  (exec (container-dir serv-dir cont) "docker" "build" "-t" (container-tag proj-name cont) "."))
