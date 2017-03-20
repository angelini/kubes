#lang typed/racket

(require/typed yaml
  [yaml->string (-> Any String)])
(require "container.rkt"
         "exec.rkt"
         "utils.rkt")

(provide build-job-containers
         create-job
         create-job-dir
         job
         job-name)

(struct job ([name : String] [containers : (Listof container)]))

(: job-dir (-> Path job Path))
(define (job-dir proj-dir job)
  (build-path proj-dir (job-name job)))

(: job->yaml (-> String job String))
(define (job->yaml proj-name job)
  (define tmpl (hash "metadata" (hash)
                     "spec" (hash "containers" (map (lambda (c)
                                                      (container->hash proj-name c
                                                                       #:with-command #t))
                                                    (job-containers job))
                                  "restartPolicy" "Never")))
  (yaml->string
   (hash "kind" "Job"
         "apiVersion" "batch/v1"
         "metadata" (hash "name" (format "~a-job" (job-name job)))
         "spec" (hash "template" tmpl))))

(: create-job-dir (-> String Path job Path))
(define (create-job-dir proj-name proj-dir job)
  (define dir (build-path proj-dir (job-name job)))
  (define containers-dir (build-path dir "containers"))
  (when (directory-exists? dir)
    (error 'directory-exists "~a" dir))
  (make-directory dir)
  (make-directory containers-dir)
  (write-file dir "job.yml" (job->yaml proj-name job))
  (map (lambda ([j : container])
         (create-container-dir containers-dir j #:with-command #f))
       (job-containers job))
  dir)

(: build-job-containers (-> String Path job String))
(define (build-job-containers proj-name proj-dir job)
  (map (lambda ([cont : container])
         (displayln (format "> build job container: ~a > ~a" (job-name job) (container-name cont)))
         (build-container proj-name (job-dir proj-dir job) cont)
         (container-tag proj-name cont))
       (job-containers job))
  (job-name job))

(: create-job (-> String Path job String))
(define (create-job proj-name proj-dir job)
  (displayln (format "> start job: ~a" (job-name job)))
  (exec-streaming (job-dir proj-dir job) "kubectl" "--namespace" proj-name "create" "-f" "job.yml")
  (job-name job))
