#lang racket

(require yaml)

(define (set-var vars key val)
  (environment-variables-set! vars (string->bytes/utf-8 key) (string->bytes/utf-8 val)))

(define env-vars
  (let ([vars (environment-variables-copy (current-environment-variables))]
        [bin-dir (build-path (current-directory) "bin")])
    (set-var vars "PATH" (format "~a:~a" (path->string bin-dir) (getenv "PATH")))
    (set-var vars "DOCKER_TLS_VERIFY" "1")
    (set-var vars "DOCKER_HOST" "tcp://192.168.64.3:2376")
    (set-var vars "DOCKER_CERT_PATH" "/Users/alexangelini/.minikube/certs")
    (set-var vars "DOCKER_API_VERSION" "1.23")
    vars))

(struct exec-output (code stdout stderr))

(define (exec dir command . args)
  (parameterize ([current-environment-variables env-vars]
                 [current-directory dir])
    (define-values (sp stdout stdin stderr) (apply subprocess #f #f #f command args))
    (subprocess-wait sp)
    (define output (exec-output (subprocess-status sp) (read-all stdout) (read-all stderr)))
    (close-output-port stdin)
    (close-input-port stdout)
    (close-input-port stderr)
    output))

(define (read-all port [buffer ""])
  (define s (read-string 1024 port))
  (if (equal? s eof) buffer (read-all port (string-append buffer s))))

(define (render-template file-name context)
  (foldl (lambda (ctx-cons acc)
           (string-replace acc (format "{{~a}}" (car ctx-cons)) (cdr ctx-cons)))
         (file->string (build-path (current-directory) "templates" file-name))
         (hash->list context)))

; Dockerfile
; ---------------------

(struct dockerfile (base-image packages working-dir files run cmd))

(define (dockerfile->string dfile)
  (string-join (list (format "FROM ~a" (dockerfile-base-image dfile))
                     (format "RUN apk add --no-cache \\\n    ~a"
                             (string-join (dockerfile-packages dfile) " \\\n    "))
                     (format "RUN mkdir -p ~a" (dockerfile-working-dir dfile))
                     (format "WORKDIR ~a" (dockerfile-working-dir dfile))
                     (string-join (map (lambda (f) (format "COPY ~a ." f))
                                       (hash-keys (dockerfile-files dfile)))
                                  "\n")
                     (format "RUN ~a"
                             (string-join (dockerfile-run dfile) " \\\n && "))
                     (format "CMD [\"~a\"]"
                             (string-join (dockerfile-cmd dfile) "\", \"")))
               "\n\n"))

; Container
; ---------------------

(struct container (name image-version port dockerfile))

(define (container->hash proj-name cont)
  (hash "name" (container-name cont)
        "image" (format "~a/~a:~a" proj-name (container-name cont) (container-image-version cont))
        "ports" (list (hash "containerPort" (container-port cont)))))

(define (create-container-dir serv-dir cont)
  (define dir (build-path serv-dir (container-name cont)))
  (when (directory-exists? dir)
    (error 'directory-exists "~a" dir))
  (make-directory dir)
  (call-with-output-file (build-path dir "Dockerfile")
    (lambda (out)
      (display (dockerfile->string (container-dockerfile cont)) out)))
  (map (lambda (f) (call-with-output-file (build-path dir (car f))
                     (lambda (out)
                       (display (cdr f) out))))
       (hash->list (dockerfile-files (container-dockerfile cont)))))

(define (build-container proj-name serv-dir cont)
  (define image-tag (format "~a/~a:~a" proj-name (container-name cont) (container-image-version cont)))
  (define docker-path (find-executable-path "docker"))
  (exec (build-path serv-dir (container-name cont)) docker-path "build" "-t" image-tag "."))

; Service
; ---------------------

(struct service (name replicas containers ports))

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

(define (create-deployment serv-dir)
  (define kubectl-path (build-path (current-directory) "bin" "kubectl"))
  (exec serv-dir kubectl-path "create" "-f" "deployment.yml"))

(define (create-service serv-dir)
  (define kubectl-path (build-path (current-directory) "bin" "kubectl"))
  (exec serv-dir kubectl-path "create" "-f" "service.yml"))

; Project
; ---------------------

(struct project (name services))

(define (project-path proj)
  (build-path (current-directory) "projects" (project-name proj)))

(define (service-path proj serv)
  (build-path (project-path proj) (service-name serv)))

(define (container-path proj serv cont)
  (build-path (service-path project serv) (container-name cont)))

(define (create-project-dirs proj [overwrite #f])
  (define dir (project-path proj))
  (when (directory-exists? dir)
    (if overwrite
        (delete-directory/files dir)
        (error 'directory-exists "~a" dir)))
  (make-directory dir)
  (map (curry create-service-dir dir (project-name proj)) (project-services proj)))

(define (build-project proj)
  (map (lambda (serv)
         (map (lambda (cont)
                (let ([eo (build-container (project-name proj) (service-path proj serv) cont)])
                  (if (= 0 (exec-output-code eo))
                      (display (format "BUILD SUCCESS (~a > ~a):\n~a\n"
                                       (service-name serv)
                                       (container-name cont)
                                       (exec-output-stdout eo)))
                      (display (format "BUILD ERROR (~a > ~a):\n~a\n"
                                       (service-name serv)
                                       (container-name cont)
                                       (exec-output-stderr eo))))))
              (service-containers serv)))
       (project-services proj)))

(define (deploy-project proj)
    (map (lambda (serv)
           (let ([eo (create-deployment (service-path proj serv))])
             (if (= 0 (exec-output-code eo))
                 (display (format "DEPLOYMENT SUCCESS (~a):\n~a\n"
                                  (service-name serv)
                                  (exec-output-stdout eo)))
                 (display (format "DEPLOYMENT ERROR (~a):\n~a\n"
                                  (service-name serv)
                                  (exec-output-stderr eo)))))
           (let ([eo (create-service (service-path proj serv))])
             (if (= 0 (exec-output-code eo))
                 (display (format "SERVICE SUCCESS (~a):\n~a\n"
                                  (service-name serv)
                                  (exec-output-stdout eo)))
                 (display (format "SERVICE ERROR (~a):\n~a\n"
                                  (service-name serv)
                                  (exec-output-stderr eo))))))
         (project-services proj)))

; Sample Project
; ---------------------

(define ZK_PORT 2181)
(define ZK_DATA_DIR "zk_data")
(define ZK_CONF_TMPL
  "tickTime=2000
dataDir=~a/~a
clientPort=~a")

(define (zk-conf working-dir) (format ZK_CONF_TMPL working-dir ZK_DATA_DIR ZK_PORT))

(define (zk-run version)
  (let ([with-version (format "zookeeper-~a" version)])
    (list (format "mkdir -p ./~a" ZK_DATA_DIR)
          (format "curl -LO http://apache.forsale.plus/zookeeper/~a/~a.tar.gz" with-version with-version)
          (format "tar xzf ~a.tar.gz" with-version)
          (format "mv ~a zookeeper" with-version)
          (format "rm ~a.tar.gz" with-version))))

(define zk-dockerfile
  (let* ([working-dir (string->path "/home/root")]
         [config-path (build-path working-dir "zoo.cfg")]
         [cfg-context (hash "data_dir" (path->string (build-path working-dir ZK_DATA_DIR))
                            "client_port" (~a ZK_PORT))])
    (dockerfile "alpine:3.5"
                '("bash" "curl" "openjdk8-jre-base")
                working-dir
                (hash "zoo.cfg" (render-template "zoo.cfg" cfg-context))
                (zk-run "3.4.9")
                (list "bash" "zookeeper/bin/zkServer.sh" "start-foreground" (path->string config-path)))))

(define zk-container (container "zookeeper"
                                "0.0.1"
                                ZK_PORT
                                zk-dockerfile))

(define zk-service (service "zookeeper" 1 (list zk-container) (list (cons ZK_PORT ZK_PORT))))

(define sample-project (project "sample" (list zk-service)))

(create-project-dirs sample-project #t)
; (build-project sample-project)
; (deploy-project sample-project)
