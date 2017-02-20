#lang racket

(require "constants.rkt"
         "container.rkt"
         "exec.rkt"
         "job.rkt"
         "service.rkt")

(provide build-project
         create-project-dirs
         deploy-project
         project
         start-jobs
         stop-jobs)

(struct project (name services jobs))

(define (project-dir proj)
  (build-path root-dir "projects" (project-name proj)))

(define (create-project-dirs proj [overwrite #f])
  (define dir (project-dir proj))
  (when (directory-exists? dir)
    (if overwrite
        (delete-directory/files dir)
        (error 'directory-exists "~a" dir)))
  (make-directory dir)
  (append (map (curry create-service-dir dir (project-name proj)) (project-services proj))
          (map (curry create-job-dir dir (project-name proj)) (project-jobs proj))))

(define (build-project proj)
  (append (map (curry build-service-containers (project-name proj) (project-dir proj))
               (project-services proj))
          (map (curry build-job-containers (project-name proj) (project-dir proj))
               (project-jobs proj))))

(define (deploy-project proj)
  (exec-raise root-dir "kubectl" "delete" "jobs" "--all")
  (exec-raise root-dir "kubectl" "delete" "deployments" "--all")
  (exec-raise root-dir "kubectl" "delete" "services" "--all")
  (map (lambda (serv)
                 (log-output (create-deployment (project-dir proj) serv)
                             (format "> deployed ~a" (service-name serv))
                             (format "> deployment error ~a" (service-name serv)))
                 (log-output (create-service (project-dir proj) serv)
                             (format "> service created ~a" (service-name serv))
                             (format "> service error ~a" (service-name serv)))
                 (service-name serv))
               (project-services proj)))

(define (stop-jobs)
  (exec-raise root-dir "kubectl" "delete" "jobs" "--all"))

(define (start-jobs proj)
  (stop-jobs)
  (map (lambda (job)
                 (log-output (create-job (project-dir proj) job)
                             (format "> started job ~a" (job-name job))
                             (format "> job start error ~a" (job-name job)))
                 (job-name job))
       (project-jobs proj)))
