#lang racket

(require "constants.rkt"
         "exec.rkt")

(provide kubectl-create
         kubectl-delete
         kubectl-get
         write-file)

(define (write-file dir name contents)
  (call-with-output-file (build-path dir name)
    (lambda (out)
      (display contents out))))

(define (output-mode->command mode)
  (case mode
    ['#:stdout exec-stdout]
    ['#:streaming exec-streaming]
    ['#:raise exec-raise]))

(define (kubectl-get namespace args [output-mode '#:stdout])
  (apply (output-mode->command output-mode)
         root-dir
         "kubectl" "get" "--namespace" namespace args))

(define (kubectl-create namespace file-name [output-mode '#:stdout])
  ((output-mode->command output-mode)
   root-dir
   "kubectl" "create" "--namespace" namespace "-f" (path->string file-name)))

(define (kubectl-delete namespace args [output-mode '#:stdout])
  (apply (output-mode->command output-mode)
         root-dir
         "kubectl" "delete" "--namespace" namespace args))
