#lang racket

(require "container.rkt"
         "exec.rkt"
         "service.rkt")

(provide build-project
         create-project-dirs
         deploy-project
         project)

(struct project (name services))

(define (project-dir proj)
  (build-path (current-directory) "projects" (project-name proj)))

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
  (map (lambda (serv)
         (log-output (create-deployment (project-dir proj) serv)
                     (format "DEPLOYMENT SUCCESS (~a):" (service-name serv))
                     (format "DEPLOYMENT ERROR (~a):" (service-name serv)))
         (log-output (create-service (project-dir proj) serv)
                     (format "SERVICE SUCCESS (~a):" (service-name serv))
                     (format "SERVICE ERROR (~a):" (service-name serv))))
       (project-services proj)))
