#lang racket

(require yaml
         "container.rkt"
         "exec.rkt")

(provide build-service-containers
         create-deployment
         create-service
         create-service-dir
         service
         service-name)

(struct service (name replicas containers ports))

(define (service-dir proj-dir serv)
  (build-path proj-dir (service-name serv)))

(define (service->deployment-yaml proj-name serv)
  (define pod-tmpl (hash "metadata" (hash "labels" (hash "app" (service-name serv)
                                                         "project" proj-name))
                         "spec" (hash "containers" (map (lambda (c)
                                                          (container->hash proj-name c
                                                                           #:with-ports #t))
                                                        (service-containers serv)))))
  (define spec (hash "replicas" (service-replicas serv)
                     "template" pod-tmpl))
  (yaml->string
   (hash "apiVersion" "extensions/v1beta1"
         "kind" "Deployment"
         "metadata" (hash "name" (format "~a-deployment" (service-name serv)))
         "spec" spec)))

(define (service->yaml proj-name serv)
  (define spec (hash "ports" (map (lambda (p) (hash "port" (car p) "targetPort" (cdr p)))
                                  (service-ports serv))
                     "selector" (hash "app" (service-name serv)
                                      "project" proj-name)
                     "type" "NodePort"))
  (yaml->string
   (hash "apiVersion" "v1"
         "kind" "Service"
         "metadata" (hash "name" (format "~a-service" (service-name serv)))
         "spec" spec)))

(define (create-service-dir proj-dir proj-name serv)
  (define dir (build-path proj-dir (service-name serv)))
  (when (directory-exists? dir)
    (error 'directory-exists "~a" dir))
  (make-directory dir)
  (call-with-output-file (build-path dir "deployment.yml")
    (lambda (out)
      (display (service->deployment-yaml proj-name serv) out)))
  (call-with-output-file (build-path dir "service.yml")
    (lambda (out)
      (display (service->yaml proj-name serv) out)))
  (map (curry create-container-dir dir  #:with-command #t) (service-containers serv)))

(define (build-service-containers proj-name proj-dir serv)
  (map (lambda (cont)
         (log-output (build-container proj-name (service-dir proj-dir serv) cont)
                     (format "> build success (~a > ~a)" (service-name serv) (container-name cont))
                     (format "> build error (~a > ~a)" (service-name serv) (container-name cont)))
         (container-tag proj-name cont))
       (service-containers serv)))

(define (create-deployment project-dir serv)
  (exec (service-dir project-dir serv) "kubectl" "create" "-f" "deployment.yml"))

(define (create-service project-dir serv)
  (exec (service-dir project-dir serv) "kubectl" "create" "-f" "service.yml"))
