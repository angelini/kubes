#lang racket

(require "constants.rkt"
         "exec.rkt")

(provide shasum-dir
         has-deployment-changed?
         has-namespace-changed?)

(define (kubectl-get . args)
  (apply exec-stdout root-dir "kubectl" "get" args))

(define (shasum-dir dir)
  (exec-raise root-dir "bash" "scripts/hash_dir.sh" (path->string dir)))

(define (has-deployment-changed? proj-name depl-name dir)
  (not (equal? (shasum-dir dir)
               (kubectl-get "deployment" depl-name
                            "--namespace" proj-name
                            "--template" "{{.metadata.annotations.shasum}}"))))

(define (has-namespace-changed? proj-name)
  (not (equal? proj-name
               (kubectl-get "namespace" proj-name
                            "--template" "{{.metadata.name}}"))))
