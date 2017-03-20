#lang typed/racket

(require/typed yaml
  [yaml->string (-> Any String)])
(require "cache.rkt"
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

(struct project ([name : String] [services : (Listof service)] [jobs : (Listof job)]))

(: project-dir (-> project Path))
(define (project-dir proj)
  (build-path root-dir "projects" (project-name proj)))

(: project->yaml (-> project String))
(define (project->yaml proj)
  (yaml->string
   (hash "kind" "Namespace"
         "apiVersion" "v1"
         "metadata" (hash "name" (project-name proj)))))

(: create-project-dirs (->* (project) (Boolean) (Listof Path)))
(define (create-project-dirs proj [overwrite #f])
  (define dir (project-dir proj))
  (when (directory-exists? dir)
    (if overwrite
        (delete-directory/files dir)
        (error 'directory-exists "~a" dir)))
  (make-directory dir)
  (write-file dir "namespace.yml" (project->yaml proj))
  (append (map (lambda ([s : service])
                 (create-service-dir (project-name proj) dir s))
               (project-services proj))
          (map (lambda ([j : job])
                 (create-job-dir (project-name proj) dir j))
               (project-jobs proj))))

(: build-project (-> project (Listof String)))
(define (build-project proj)
  (append (map (lambda ([s : service])
                 (build-service-containers (project-name proj) (project-dir proj) s))
               (project-services proj))
          (map (lambda ([j : job])
                 (build-job-containers (project-name proj) (project-dir proj) j))
               (project-jobs proj))))

(: stop-jobs (-> project String))
(define (stop-jobs proj)
  (exec-raise root-dir "kubectl" "--namespace" (project-name proj) "delete" "jobs" "--all"))

(: start-jobs (-> project (Listof String)))
(define (start-jobs proj)
  (stop-jobs proj)
  (map (lambda ([j : job]) (create-job (project-name proj) (project-dir proj) j))
       (project-jobs proj)))

(: teardown-project (->* (project) (Boolean) Void))
(define (teardown-project proj [delete-volumes #f])
  (stop-jobs proj)
  (when delete-volumes
    (kubectl-delete (project-name proj) (list "persistentvolumeclaims" "--all"))
    (kubectl-delete (project-name proj) (list "persistentvolumes" "--all")))
  (kubectl-delete (project-name proj) (list "deployments" "--all"))
  (kubectl-delete (project-name proj) (list "services" "--all"))
  (void))

(: deploy-project (-> project Void))
(define (deploy-project proj)
  (stop-jobs proj)
  (define proj-dir (project-dir proj))
  (define proj-name (project-name proj))
  (if (has-namespace-changed? proj-name)
    (begin (displayln (format "> create namespace: ~a" proj-name))
           (exec-streaming (project-dir proj) "kubectl" "create" "-f" "namespace.yml"))
    (displayln (format "> skip namespace: ~a" proj-name)))
  (map (lambda ([serv : service])
         (map (lambda ([vol : volume])
                (when (not (volume-exists? proj-name vol))
                  (create-volume-and-claim proj-name (service-dir proj-dir serv) vol)))
              (service-volumes serv))
         (if (has-deployment-changed? proj-name
                                      (deployment-name serv)
                                      (build-path (service-dir proj-dir serv) "containers"))
           (begin (delete-deployment proj-name serv)
                  (create-deployment proj-name proj-dir serv))
           (displayln (format "> skip deployment: ~a" (deployment-name serv))))
         (delete-service proj-name serv)
         (create-service proj-name proj-dir serv))
       (project-services proj))
  (void))
