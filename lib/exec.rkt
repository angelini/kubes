#lang typed/racket

(require/typed racket/base
               [environment-variables-copy (-> Environment-Variables Environment-Variables)])
(require "constants.rkt")

(provide exec
         exec-raise
         exec-stdout
         exec-streaming
         log-output)

(define-type String-EOF (U String EOF))

(: subprocess-final-status (-> Subprocess Integer))
(define (subprocess-final-status sp)
  (define status (subprocess-status sp))
  (if (integer? status)
      status
      (error 'subprocess-still-running)))

(: find-exec-path (-> String Path))
(define (find-exec-path s)
  (define exec-path (find-executable-path s))
  (if (path? exec-path)
      exec-path
      (error 'cannot-find-exec-path s)))

(: close-ports (-> Input-Port Output-Port Input-Port Void))
(define (close-ports stdout stdin stderr)
  (close-output-port stdin)
  (close-input-port stdout)
  (close-input-port stderr))

(: read-all (->* (Input-Port) (String) String))
(define (read-all port [buffer ""])
  (define s (read-string 1024 port))
  (if (equal? s eof) buffer (read-all port (string-append buffer s))))

(: parse-docker-env (-> String (Listof (Pairof String String))))
(define (parse-docker-env stdout)
  (map (lambda ([s : String])
         (define match (regexp-match #rx"export (.*)=\"(.*)\"" s))
         (if (pair? match)
             (apply cons (cast (cdr match) (List String String)))
             (error 'parse-error "~a" s)))
       (filter (lambda ([s : String]) (string-prefix? s "export "))
               (string-split stdout "\n"))))

(: minikube-docker-env (-> Path (Listof (Pairof String String))))
(define (minikube-docker-env bin-dir)
  (define-values (sp stdout stdin stderr) (subprocess #f #f #f (build-path bin-dir "minikube") "docker-env"))
  (subprocess-wait sp)
  (define env-list (if (= 0 (subprocess-final-status sp))
                       (parse-docker-env (read-all stdout))
                       (error 'cannot-load-docker-env "~a" (read-all stderr))))
  (close-ports stdout stdin stderr)
  env-list)

(: set-var (-> Environment-Variables String String String))
(define (set-var vars key val)
  (environment-variables-set! vars (string->bytes/utf-8 key) (string->bytes/utf-8 val))
  val)

(define env-vars : Environment-Variables
  (let ([vars (environment-variables-copy (current-environment-variables))]
        [bin-dir (build-path root-dir "bin")])
    (set-var vars "PATH" (format "~a:~a" (path->string bin-dir) (getenv "PATH")))
    (map (lambda ([pair : (Pairof String String)])
           (set-var vars (car pair) (cdr pair)))
         (minikube-docker-env bin-dir))
    vars))

(struct exec-output ([code : Integer] [stdout : String] [stderr : String]))

(: exec (-> Path String String * exec-output))
(define (exec dir command . args)
  (parameterize ([current-environment-variables env-vars]
                 [current-directory dir])
    (define-values (sp stdout stdin stderr) (apply subprocess #f #f #f (find-exec-path command) args))
    (subprocess-wait sp)
    (define output (exec-output (subprocess-final-status sp) (read-all stdout) (read-all stderr)))
    (close-ports stdout stdin stderr)
    output))

(: stream-print (-> Input-Port Void))
(define (stream-print port)
  (let loop ([s : String-EOF (read-string 1 port)])
    (when (not (eof-object? s))
      (display s)
      (loop (read-string 1 port)))))

(: exec-streaming (-> Path String String * Void))
(define (exec-streaming dir command . args)
  (parameterize ([current-environment-variables env-vars]
                 [current-directory dir])
    (define-values (sp stdout stdin stderr) (apply subprocess #f #f #f (find-exec-path command) args))
    (stream-print stdout)
    (subprocess-wait sp)
    (when (not (= 0 (subprocess-final-status sp)))
      (displayln (read-all stderr))
      (error 'exec-error "$ ~a ~a ~a" dir command args))
    (close-ports stdout stdin stderr)
    (void)))

(: exec-stdout (-> Path String String * (U String False)))
(define (exec-stdout dir command . args)
  (define output (apply exec dir command args))
  (if (= 0 (exec-output-code output))
      (exec-output-stdout output)
      #f))

(: exec-raise (-> Path String String * String))
(define (exec-raise dir command . args)
    (parameterize ([current-environment-variables env-vars]
                   [current-directory dir])
    (define-values (sp stdout stdin stderr) (apply subprocess #f #f #f (find-exec-path command) args))
    (subprocess-wait sp)
    (define output (if (= 0 (subprocess-final-status sp))
                       (read-all stdout)
                       (error 'exec-error "~a ~a" command (read-all stderr))))
    (close-ports stdout stdin stderr)
    output))

(: log-output (-> exec-output String String Void))
(define (log-output output ok-prefix err-prefix)
  (if (= 0 (exec-output-code output))
      (display (format "~a\n~a\n" ok-prefix (exec-output-stdout output)))
      (display (format "~a\n~a\n" err-prefix (exec-output-stderr output)))))
