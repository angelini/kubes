#!/usr/bin/env racket

#lang racket

(require "../lib/constants.rkt"
         "../lib/exec.rkt")

(define (pods-list namespace [app #f])
  (define pod-filter (if app (format "app=~a" app) ""))
  (string-split
   (exec-stdout root-dir
                "kubectl" "get" "pods"
                "--namespace" namespace
                "-l" pod-filter
                "-o" "jsonpath"
                "--template" "{.items[*].metadata.name}")))

(define (connect-to-pod namespace [app #f])
  (define pod (car (pods-list namespace app)))
  (format "kubectl --namespace=~a exec -it ~a env TERM=xterm -- bash" namespace pod))

(define (open-dashboard namespace)
  (string-append
   (case (system-type 'os)
     ['macosx "open "]
     ['unix "xdg-open "])
   (string-trim (exec-stdout root-dir "minikube" "dashboard" "--url"))
   (format "/#/workload?namespace=~a" namespace)))

(define (open-service project service)
  (format "minikube --namespace ~a service ~a" project service))

(define (follow-logs-from-pod namespace app)
  (define pod (car (pods-list namespace app)))
  (format "kubectl --namespace=~a logs -f ~a" namespace pod))

(define (print-usage)
  (display "bin/kubes allows you to interact with a runnings kubes project

Usage:
  kubes [command] [namespace] [arg ...]

Available Commands:
  connect    Connect to a bash shell on a random running pod
  dash       Open the dashboard in the default browser
  logs       Follow logs from a random pod within the specified app
  open       Open all ports for a service in the default browser
"))

(define (run)
  (define cli-args (vector->list (current-command-line-arguments)))
  (define-values (command args) (if (empty? cli-args)
                                    (values "" '())
                                    (values (car cli-args)
                                            (cdr cli-args))))
  (case command
    [("connect") (apply connect-to-pod args)]
    [("dash") (apply open-dashboard args)]
    [("logs") (apply follow-logs-from-pod args)]
    [("open") (apply open-service args)]
    [else (begin (print-usage)
                 (exit 1))]))

(run)
