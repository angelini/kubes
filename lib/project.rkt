#lang racket

(require yaml
         "cache.rkt"
         "constants.rkt"
         "container.rkt"
         "exec.rkt"
         "job.rkt"
         "service.rkt"
         "utils.rkt"
         "volume.rkt")

(provide build-project
         create-project-dirs
         deploy-project
         project
         teardown-project
         start-jobs
         stop-jobs)

(struct project (name services jobs))

(define (project-dir proj)
  (build-path root-dir "projects" (project-name proj)))

(define (project->yaml proj)
  (yaml->string
   (hash "kind" "Namespace"
         "apiVersion" "v1"
         "metadata" (hash "name" (project-name proj)))))

(define (create-project-dirs proj [overwrite #f])
  (define dir (project-dir proj))
  (when (directory-exists? dir)
    (if overwrite
        (delete-directory/files dir)
        (error 'directory-exists "~a" dir)))
  (make-directory dir)
  (write-file dir "namespace.yml" (project->yaml proj))
  (append (map (curry create-service-dir dir (project-name proj)) (project-services proj))
          (map (curry create-job-dir dir (project-name proj)) (project-jobs proj))))

(define (build-project proj)
  (append (map (curry build-service-containers (project-name proj) (project-dir proj))
               (project-services proj))
          (map (curry build-job-containers (project-name proj) (project-dir proj))
               (project-jobs proj))))

(define (stop-jobs proj)
  (exec-raise root-dir "kubectl" "--namespace" (project-name proj) "delete" "jobs" "--all"))

(define (start-jobs proj)
  (stop-jobs proj)
  (map (curry create-job (project-name proj) (project-dir proj))
       (project-jobs proj)))

(define (teardown-project proj)
  (stop-jobs proj)
  (kubectl-delete (project-name proj) (list "persistentvolumeclaims" "--all"))
  (kubectl-delete (project-name proj) (list "persistentvolumes" "--all"))
  (kubectl-delete (project-name proj) (list "deployments" "--all"))
  (kubectl-delete (project-name proj) (list "services" "--all")))

(define (deploy-project proj)
  (stop-jobs proj)
  (define proj-dir (project-dir proj))
  (define proj-name (project-name proj))
  (if (has-namespace-changed? proj-name)
    (begin (displayln (format "> create namespace: ~a" proj-name))
           (exec-streaming (project-dir proj) "kubectl" "create" "-f" "namespace.yml"))
    (displayln (format "> skip namespace: ~a" proj-name)))
  (map (lambda (serv)
         (map (lambda (vol)
                (delete-volume-claim proj-name vol)
                (delete-volume proj-name vol)
                (create-volume-and-claim proj-name (service-dir proj-dir serv) vol))
              (service-volumes serv))
         (if (has-deployment-changed? proj-name
                                      (deployment-name serv)
                                      (build-path (service-dir proj-dir serv) "containers"))
           (begin (delete-deployment proj-name serv)
                  (create-deployment proj-name proj-dir serv))
           (displayln (format "> skip deployment: ~a" (deployment-name serv))))
         (delete-service proj-name serv)
         (create-service proj-name proj-dir serv))
       (project-services proj)))
