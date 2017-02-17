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
  (define pod-tmpl (hash "metadata" (hash "labels" (hash "app" (service-name serv)))
                         "spec" (hash "containers" (map (curry container->hash proj-name)
                                                        (service-containers serv)))))
  (define spec (hash "replicas" (service-replicas serv)
                     "template" pod-tmpl))
  (yaml->string
   (hash "apiVersion" "extensions/v1beta1"
         "kind" "Deployment"
         "metadata" (hash "name" (format "~a-deployment" (service-name serv)))
         "spec" spec)))

(define (service->yaml serv)
  (define spec (hash "ports" (map (lambda (p) (hash "port" (car p) "targetPort" (cdr p)))
                                  (service-ports serv))
                     "selector" (hash "app" (service-name serv))
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
      (display (service->yaml serv) out)))
  (map (curry create-container-dir dir) (service-containers serv)))

(define (build-service-containers proj-name proj-dir serv)
  (map (lambda (cont)
         (log-output (build-container proj-name (service-dir proj-dir serv) cont)
                     (format "BUILD SUCCESS (~a > ~a):" (service-name serv) (container-name cont))
                     (format "BUILD ERROR (~a > ~a):" (service-name serv) (container-name cont))))
       (service-containers serv)))

(define (create-deployment project-dir serv)
  (exec (service-dir project-dir serv) "kubectl" "create" "-f" "deployment.yml"))

(define (create-service project-dir serv)
  (exec (service-dir project-dir serv) "kubectl" "create" "-f" "service.yml"))