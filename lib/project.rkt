#lang racket

(require "constants.rkt"
         "container.rkt"
         "exec.rkt"
         "service.rkt")

(provide build-project
         create-project-dirs
         deploy-project
         project)

(struct project (name services))

(define (project-dir proj)
  (build-path root-dir "projects" (project-name proj)))

(define (create-project-dirs proj [overwrite #f])
  (define dir (project-dir proj))
  (when (directory-exists? dir)
    (if overwrite
        (delete-directory/files dir)
        (error 'directory-exists "~a" dir)))
  (make-directory dir)
  (map (curry create-service-dir dir (project-name proj)) (project-services proj)))

(define (build-project proj)
  (map (curry build-service-containers (project-name proj) (project-dir proj))
       (project-services proj)))

(define (deploy-project proj)
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
