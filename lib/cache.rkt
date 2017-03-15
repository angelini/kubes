#lang racket

(require "constants.rkt"
         "exec.rkt"
         "utils.rkt")

(provide shasum-dir
         has-deployment-changed?
         has-namespace-changed?)

(define (shasum-dir dir)
  (exec-raise root-dir "bash" "scripts/hash_dir.sh" (path->string dir)))

(define (has-deployment-changed? proj-name depl-name dir)
  (not (equal? (shasum-dir dir)
               (kubectl-get proj-name
                            (list "deployment" depl-name
                                  "--template" "{{.metadata.annotations.shasum}}")))))

(define (has-namespace-changed? proj-name)
  (not (equal? proj-name
               (exec-stdout root-dir "kubectl" "get"
                            "namespace" proj-name
                            "--template" "{{.metadata.name}}"))))
