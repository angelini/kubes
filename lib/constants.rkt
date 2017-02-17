#lang racket

(provide root-dir)

(define root-dir
  (let ([dir (current-directory)])
    (match-define-values (parent _ _) (split-path dir))
    (if (string-suffix? (path->string dir) "/lib/")
        parent
        dir)))
