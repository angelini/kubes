#lang racket

(require yaml
         "container.rkt"
         "exec.rkt"
         "utils.rkt")

(provide build-job-containers
         create-job
         create-job-dir
         job
         job-name)

(struct job (name containers))

(define (job-dir proj-dir job)
  (build-path proj-dir (job-name job)))

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

(define (create-job-dir proj-dir proj-name job)
  (define dir (build-path proj-dir (job-name job)))
  (define containers-dir (build-path dir "containers"))
  (when (directory-exists? dir)
    (error 'directory-exists "~a" dir))
  (make-directory dir)
  (make-directory containers-dir)
  (write-file dir "job.yml" (job->yaml proj-name job))
  (map (curry create-container-dir containers-dir #:with-command #f) (job-containers job)))

(define (build-job-containers proj-name proj-dir job)
  (map (lambda (cont)
         (displayln (format "> build job container: ~a > ~a" (job-name job) (container-name cont)))
         (build-container proj-name (job-dir proj-dir job) cont)
         (container-tag proj-name cont))
       (job-containers job)))

(define (create-job proj-name proj-dir job)
  (displayln (format "> start job: ~a" (job-name job)))
  (exec-streaming (job-dir proj-dir job) "kubectl" "--namespace" proj-name "create" "-f" "job.yml")
  (job-name job))
