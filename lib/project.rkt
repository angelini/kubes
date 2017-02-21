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
         teardown-projects
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

(define (stop-jobs)
  (exec-raise root-dir "kubectl" "delete" "jobs" "--all"))

(define (start-jobs proj)
  (stop-jobs)
  (map (curry create-job (project-dir proj))
       (project-jobs proj)))

(define (teardown-projects)
  (stop-jobs)
  (exec-raise root-dir "kubectl" "delete" "deployments" "--all")
  (exec-raise root-dir "kubectl" "delete" "services" "--all"))

(define (deploy-project proj)
  (teardown-projects)
  (map (curry create-deployment-and-service (project-dir proj))
       (project-services proj)))
