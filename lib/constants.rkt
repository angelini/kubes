#lang racket

(provide container-working-dir
         root-dir)

(define container-working-dir
  (string->path "/home/root"))

(define root-dir
  (let ([dir (current-directory)])
    (match-define-values (parent _ _) (split-path dir))
    (if (string-suffix? (path->string dir) "/lib/")
        parent
        dir)))
