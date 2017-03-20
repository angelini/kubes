#lang typed/racket

(require/typed yaml
  [yaml->string (-> Any String)])
(require "cache.rkt"
         "constants.rkt"
         "container.rkt"
         "exec.rkt"
         "utils.rkt"
         "volume.rkt")

(provide build-service-containers
         create-deployment
         create-service
         create-service-dir
         delete-deployment
         delete-service
         deployment-name
         service
         service-dir
         service-name
         service-volumes
         simple-service)

(struct service ([name : String] [replicas : Integer] [containers : (Listof container)]
                 [ports : (Listof Integer)] [volumes : (Listof volume)]))

(: deployment-name (-> service String))
(define (deployment-name serv)
  (format "~a-deployment" (service-name serv)))

(: service-dir (-> Path service Path))
(define (service-dir proj-dir serv)
  (build-path proj-dir (service-name serv)))

(: service->deployment-yaml (-> String service String String))
(define (service->deployment-yaml proj-name serv shasum)
  (define pod-tmpl (hash "metadata" (hash "labels" (hash "app" (service-name serv)
                                                         "namespace" proj-name))
                         "spec" (hash "containers" (map (lambda (c)
                                                          (container->hash proj-name c
                                                                           #:with-ports #t))
                                                        (service-containers serv))
                                      "volumes" (map (lambda (v)
                                                       (volume->hash v))
                                                     (service-volumes serv)))))
  (define spec (hash "replicas" (service-replicas serv)
                     "template" pod-tmpl))
  (yaml->string
   (hash "kind" "Deployment"
         "apiVersion" "extensions/v1beta1"
         "metadata" (hash "name" (deployment-name serv)
                          "annotations" (hash "shasum" shasum))
         "spec" spec)))

(: service->yaml (-> String service String))
(define (service->yaml proj-name serv)
  (define spec (hash "ports" (map (lambda (p) (hash "name" (format "~a-~a" (service-name serv) p)
                                                    "port" p))
                                  (service-ports serv))
                     "selector" (hash "app" (service-name serv)
                                      "namespace" proj-name)
                     "type" "NodePort"))
  (yaml->string
   (hash "kind" "Service"
         "apiVersion" "v1"
         "metadata" (hash "name" (~a (service-name serv)))
         "spec" spec)))

(: create-service-dir (-> String Path service Path))
(define (create-service-dir proj-name proj-dir serv)
  (define dir (service-dir proj-dir serv))
  (define containers-dir (build-path dir "containers"))
  (define volumes-dir (build-path dir "volumes"))
  (when (directory-exists? dir)
    (error 'directory-exists "~a" dir))
  (make-directory dir)
  (make-directory containers-dir)
  (make-directory volumes-dir)
  (map (lambda ([c : container]) (create-container-dir containers-dir c #:with-command #t))
       (service-containers serv))
  (map (curry create-volume-files volumes-dir) (service-volumes serv))
  (define shasum (shasum-dir containers-dir))
  (write-file dir "deployment.yml" (service->deployment-yaml proj-name serv shasum))
  (when (not (empty? (service-ports serv)))
    (write-file dir "service.yml" (service->yaml proj-name serv)))
  dir)

(: build-service-containers (-> String Path service String))
(define (build-service-containers proj-name proj-dir serv)
  (map (lambda ([cont : container])
         (displayln (format "> build service container: ~a > ~a" (service-name serv) (container-name cont)))
         (build-container proj-name (service-dir proj-dir serv) cont)
         (container-tag proj-name cont))
       (service-containers serv))
  (service-name serv))

(: create-deployment (-> String Path service String))
(define (create-deployment proj-name proj-dir serv)
  (define deployment-file (build-path (service-dir proj-dir serv) "deployment.yml"))
  (displayln (format "> create deployment: ~a" (service-name serv)))
  (kubectl-create proj-name deployment-file '#:streaming)
  (service-name serv))

(: create-service (-> String Path service String))
(define (create-service proj-name proj-dir serv)
  (when (not (empty? (service-ports serv)))
    (define service-file (build-path (service-dir proj-dir serv) "service.yml"))
    (displayln (format "> create service: ~a" (service-name serv)))
    (kubectl-create proj-name service-file '#:streaming))
  (service-name serv))

(: delete-deployment (-> String service (U String Boolean)))
(define (delete-deployment proj-name serv)
  (define args (list "deployment" (deployment-name serv)))
  (if (kubectl-get proj-name args)
    (begin (displayln (format "> delete deployment: ~a" (deployment-name serv)))
           (kubectl-delete proj-name args '#:raise))
    #f))

(: delete-service (-> String service (U String Boolean)))
(define (delete-service proj-name serv)
  (define args (list "service" (service-name serv)))
  (if (kubectl-get proj-name args)
      (begin (displayln (format "> delete service: ~a" (deployment-name serv)))
             (kubectl-delete proj-name args '#:raise))
      #f))

(: simple-service (-> String String (U (Listof Integer) Integer) dockerfile service))
(define (simple-service name image-version ports dockerfile)
  (define ports-list (or (if (integer? ports) (list ports) ports) '()))
  (define cont (container name image-version ports-list #hash() dockerfile))
  (service name 1 (list cont) ports-list '()))
