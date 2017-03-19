#lang typed/racket

(provide container-working-dir
         root-dir)

(define container-working-dir : Path
  (string->path "/home/root"))

(define root-dir : Path
  (let ([dir (current-directory)])
    (match-define-values (parent _ _) (split-path dir))
    (when (not (path? parent))
      (error 'cwd-error "~a" dir))
    (if (string-suffix? (path->string dir) "/lib/")
        parent
        dir)))
