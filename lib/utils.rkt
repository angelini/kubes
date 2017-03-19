#lang typed/racket

(require "constants.rkt"
         "exec.rkt")

(provide kubectl-create
         kubectl-delete
         kubectl-get
         write-file)

(: write-file (-> Path String String Void))
(define (write-file dir name contents)
  (call-with-output-file (build-path dir name)
    (lambda ([out : Output-Port])
      (display contents out))))

(define-type OutputMode (U '#:stdout '#:streaming '#:raise))

(: output-mode->command (-> OutputMode (-> Path String String * (U String Boolean))))
(define (output-mode->command mode)
  (case mode
    ['#:stdout exec-stdout]
    ['#:streaming exec-streaming]
    ['#:raise exec-raise]))

(: kubectl-get (->* (String (Listof String)) (OutputMode) (U String Boolean)))
(define (kubectl-get namespace args [output-mode '#:stdout])
  (apply (output-mode->command output-mode)
         root-dir
         "kubectl" "get" "--namespace" namespace args))

(: kubectl-create (->* (String Path) (OutputMode) (U String Boolean)))
(define (kubectl-create namespace file-path [output-mode '#:stdout])
  ((output-mode->command output-mode)
   root-dir
   "kubectl" "create" "--namespace" namespace "-f" (path->string file-path)))

(: kubectl-delete (->* (String (Listof String)) (OutputMode) (U String Boolean)))
(define (kubectl-delete namespace args [output-mode '#:stdout])
  (apply (output-mode->command output-mode)
         root-dir
         "kubectl" "delete" "--namespace" namespace args))
