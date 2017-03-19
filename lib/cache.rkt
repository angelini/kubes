#lang racket

(require "constants.rkt"
         "exec.rkt"
         "utils.rkt")

(provide shasum-dir
         has-deployment-changed?
         has-directory-changed?
         has-namespace-changed?
         write-dir-hash)

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

(define (dir-hash-name src-dir)
  (define-values (_ src-filename __) (split-path src-dir))
  (format "~a.hash" src-filename))

(define (has-directory-changed? src-dir output-dir)
  (define dir-hash-path (build-path output-dir (dir-hash-name src-dir)))
  (if (file-exists? dir-hash-path)
      (not (equal? (shasum-dir src-dir)
                   (file->string dir-hash-path)))
      #t))

(define (write-dir-hash src-dir output-dir)
  (define dir-hash-path (build-path output-dir (dir-hash-name src-dir)))
  (when (file-exists? dir-hash-path)
    (delete-file dir-hash-path))
  (write-file output-dir (dir-hash-name src-dir) (shasum-dir src-dir)))
