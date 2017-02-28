#lang racket

(require "constants.rkt")

(provide exec
         exec-raise
         exec-streaming
         log-output)

(define (close-ports stdout stdin stderr)
  (close-output-port stdin)
  (close-input-port stdout)
  (close-input-port stderr))

(define (read-all port [buffer ""])
  (define s (read-string 1024 port))
  (if (equal? s eof) buffer (read-all port (string-append buffer s))))

(define (parse-docker-env stdout)
  (map (lambda (s)
         (apply cons (rest (regexp-match #rx"export (.*)=\"(.*)\"" s))))
       (filter (lambda (s) (string-prefix? s "export "))
               (string-split stdout "\n"))))

(define (minikube-docker-env bin-dir)
  (define-values (sp stdout stdin stderr) (subprocess #f #f #f (build-path bin-dir "minikube") "docker-env"))
  (subprocess-wait sp)
  (define env-list (if (= 0 (subprocess-status sp))
                       (parse-docker-env (read-all stdout))
                       (error 'cannot-load-docker-env "~a" (read-all stderr))))
  (close-ports stdout stdin stderr)
  env-list)

(define (set-var vars key val)
  (environment-variables-set! vars (string->bytes/utf-8 key) (string->bytes/utf-8 val)))

(define env-vars
  (let ([vars (environment-variables-copy (current-environment-variables))]
        [bin-dir (build-path root-dir "bin")])
    (set-var vars "PATH" (format "~a:~a" (path->string bin-dir) (getenv "PATH")))
    (map (lambda (pair)
           (set-var vars (car pair) (cdr pair)))
         (minikube-docker-env bin-dir))
    vars))

(struct exec-output (code stdout stderr))

(define (exec dir command . args)
  (parameterize ([current-environment-variables env-vars]
                 [current-directory dir])
    (define-values (sp stdout stdin stderr) (apply subprocess #f #f #f (find-executable-path command) args))
    (subprocess-wait sp)
    (define output (exec-output (subprocess-status sp) (read-all stdout) (read-all stderr)))
    (close-ports stdout stdin stderr)
    output))

(define (stream-print port)
  (let loop ([s (read-string 1 port)])
    (if (eof-object? s)
        (displayln "")
        (begin (display s)
               (loop (read-string 1 port))))))

(define (exec-streaming dir command . args)
  (parameterize ([current-environment-variables env-vars]
                 [current-directory dir])
    (define-values (sp stdout stdin stderr) (apply subprocess #f #f #f (find-executable-path command) args))
    (stream-print stdout)
    (subprocess-wait sp)
    (when (not (= 0 (subprocess-status sp)))
      (displayln (read-all stderr))
      (error 'exec-error "$ ~a ~a ~a" dir command args))
    (close-ports stdout stdin stderr)
    (void)))

(define (exec-raise dir command . args)
    (parameterize ([current-environment-variables env-vars]
                 [current-directory dir])
    (define-values (sp stdout stdin stderr) (apply subprocess #f #f #f (find-executable-path command) args))
    (subprocess-wait sp)
    (define output (if (= 0 (subprocess-status sp))
                       (read-all stdout)
                       (error 'exec-error "~a ~a" command (read-all stderr))))
    (close-ports stdout stdin stderr)
    output))

(define (log-output output ok-prefix err-prefix)
  (if (= 0 (exec-output-code output))
      (display (format "~a\n~a\n" ok-prefix (exec-output-stdout output)))
      (display (format "~a\n~a\n" err-prefix (exec-output-stderr output)))))
