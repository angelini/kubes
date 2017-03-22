#lang typed/racket

(provide root-dir)

(define root-dir : Path
  (let ([dir (current-directory)])
    (match-define-values (parent _ _) (split-path dir))
    (when (not (path? parent))
      (error 'cwd-error "~a" dir))
    (if (string-suffix? (path->string dir) "/lib/")
        parent
        dir)))
