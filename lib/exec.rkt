#lang racket

(provide exec
         log-output)

(define (read-all port [buffer ""])
  (define s (read-string 1024 port))
  (if (equal? s eof) buffer (read-all port (string-append buffer s))))

(define (set-var vars key val)
  (environment-variables-set! vars (string->bytes/utf-8 key) (string->bytes/utf-8 val)))

(define env-vars
  (let ([vars (environment-variables-copy (current-environment-variables))]
        [bin-dir (build-path (current-directory) "bin")])
    (set-var vars "PATH" (format "~a:~a" (path->string bin-dir) (getenv "PATH")))
    (set-var vars "DOCKER_TLS_VERIFY" "1")
    (set-var vars "DOCKER_HOST" "tcp://192.168.64.4:2376")
    (set-var vars "DOCKER_CERT_PATH" "/Users/alexangelini/.minikube/certs")
    (set-var vars "DOCKER_API_VERSION" "1.23")
    vars))

(struct exec-output (code stdout stderr))

(define (exec dir command . args)
  (parameterize ([current-environment-variables env-vars]
                 [current-directory dir])
    (define-values (sp stdout stdin stderr) (apply subprocess #f #f #f (find-executable-path command) args))
    (subprocess-wait sp)
    (define output (exec-output (subprocess-status sp) (read-all stdout) (read-all stderr)))
    (close-output-port stdin)
    (close-input-port stdout)
    (close-input-port stderr)
    output))

(define (log-output output ok-prefix err-prefix)
  (if (= 0 (exec-output-code output))
      (display (format "~a\n~a\n" ok-prefix (exec-output-stdout output)))
      (display (format "~a\n~a\n" err-prefix (exec-output-stderr output)))))
