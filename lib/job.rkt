#lang racket

(require yaml
         "container.rkt"
         "exec.rkt")

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
   (hash "apiVersion" "batch/v1"
         "kind" "Job"
         "metadata" (hash "name" (format "~a-job" (job-name job)))
         "spec" (hash "template" tmpl))))

(define (create-job-dir proj-dir proj-name job)
  (define dir (build-path proj-dir (job-name job)))
  (when (directory-exists? dir)
    (error 'directory-exists "~a" dir))
  (make-directory dir)
  (call-with-output-file (build-path dir "job.yml")
    (lambda (out)
      (display (job->yaml proj-name job) out)))
  (map (curry create-container-dir dir) (job-containers job)))

(define (build-job-containers proj-name proj-dir job)
  (map (lambda (cont)
         (log-output (build-container proj-name (job-dir proj-dir job) cont)
                     (format "BUILD SUCCESS (~a > ~a):" (job-name job) (container-name cont))
                     (format "BUILD ERROR (~a > ~a):" (job-name job) (container-name cont)))
         (container-tag proj-name cont))
       (job-containers job)))

(define (create-job project-dir job)
  (exec (job-dir project-dir job) "kubectl" "create" "-f" "job.yml"))
