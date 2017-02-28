#lang racket

(provide write-file)

(define (write-file dir name contents)
  (call-with-output-file (build-path dir name)
    (lambda (out)
      (display contents out))))
