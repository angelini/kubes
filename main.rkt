#lang racket

(require yaml)

(define (set-var vars key val)
  (environment-variables-set! vars (string->bytes/utf-8 key) (string->bytes/utf-8 val)))

(define env-vars
  (let ([vars (environment-variables-copy (current-environment-variables))]
        [bin-dir (build-path (current-directory) "bin")])
    (set-var vars "PATH" (path->string bin-dir))
    (set-var vars "DOCKER_TLS_VERIFY" "1")
    (set-var vars "DOCKER_HOST" "tcp://192.168.99.100:2376")
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

(struct container (name image-version port dockerfile))

(define (container->hash proj-name cont)
  (hash "name" (container-name cont)
        "image" (format "~a/~a:~a" proj-name (container-name cont) (container-image-version cont))
        "ports" (list (hash "containerPort" (container-port cont)))))

(define (create-container-dir depl-dir cont)
  (define dir (build-path depl-dir (container-name cont)))
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

(define (build-container proj-name depl-path cont)
  (define image-tag (format "~a/~a:~a" proj-name (container-name cont) (container-image-version cont)))
  (define docker-path (find-executable-path "docker"))
  (exec (build-path depl-path (container-name cont)) docker-path "build" "-t" image-tag "."))

(struct deployment (name replicas containers))

(define (deployment->string proj-name depl)
  (define pod-tmpl (hash "metadata" (hash "labels" (hash "app" (deployment-name depl)))
                         "spec" (hash "containers" (map (curry container->hash proj-name)
                                                        (deployment-containers depl)))))
  (define spec (hash "replicas" (deployment-replicas depl)
                     "template" pod-tmpl))
  (define full-spec (hash "apiVersion" "extensions/v1beta1"
                          "kind" "Deployment"
                          "metadata" (hash "name" (format "~a-deployment" (deployment-name depl)))
                          "spec" spec))
  (yaml->string full-spec))

(define (create-deployment-dir proj-dir proj-name depl)
  (define dir (build-path proj-dir (deployment-name depl)))
  (when (directory-exists? dir)
    (error 'directory-exists "~a" dir))
  (make-directory dir)
  (call-with-output-file (build-path dir "deployment.yml")
    (lambda (out)
      (display (deployment->string proj-name depl) out)))
  (map (curry create-container-dir dir) (deployment-containers depl)))

(define (create-deployment depl-dir depl)
  (define kubectl-path (build-path (current-directory) "bin" "kubectl"))
  (exec depl-dir kubectl-path "create" "-f" "deployment.yml"))

(struct project (name deployments))

(define (project-path proj)
  (build-path (current-directory) "projects" (project-name proj)))

(define (deployment-path proj depl)
  (build-path (project-path proj) (deployment-name depl)))

(define (container-path proj depl cont)
  (build-path (deployment-path project depl) (container-name cont)))

(define (create-project-dirs proj [overwrite #f])
  (define dir (project-path proj))
  (when (directory-exists? dir)
    (if overwrite
        (delete-directory/files dir)
        (error 'directory-exists "~a" dir)))
  (make-directory dir)
  (map (curry create-deployment-dir dir (project-name proj)) (project-deployments proj)))

(define (build-project proj)
  (map (lambda (depl)
         (map (lambda (cont)
                (let ([eo (build-container (project-name proj) (deployment-path proj depl) cont)])
                  (if (= 0 (exec-output-code eo))
                      (display (format "BUILD SUCCESS (~a > ~a):\n~a\n"
                                       (deployment-name depl)
                                       (container-name cont)
                                       (exec-output-stdout eo)))
                      (display (format "BUILD ERROR (~a > ~a):\n~a\n"
                                       (deployment-name depl)
                                       (container-name cont)
                                       (exec-output-stderr eo))))))
              (deployment-containers depl)))
       (project-deployments proj)))

(define (deploy-project proj)
    (map (lambda (depl)
           (let ([eo (create-deployment (deployment-path proj depl) depl)])
             (if (= 0 (exec-output-code eo))
                 (display (format "DEPLOY SUCCESS (~a):\n~a\n"
                                  (deployment-name depl)
                                  (exec-output-stdout eo)))
                 (display (format "DEPLOY ERROR (~a):\n~a\n"
                                  (deployment-name depl)
                                  (exec-output-stderr eo))))))
         (project-deployments proj)))

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
         [config-path (build-path working-dir "zoo.cfg")])
    (dockerfile "alpine:3.5"
                '("bash" "curl" "openjdk8-jre-base")
                working-dir
                (hash "zoo.cfg" (zk-conf working-dir))
                (zk-run "3.4.9")
                (list "bash" "zookeeper/bin/zkServer.sh" "start-foreground" (path->string config-path)))))

(define zk-container (container "zookeeper"
                                "0.0.1"
                                ZK_PORT
                                zk-dockerfile))

(define zk-deployment (deployment "zookeeper" 1 (list zk-container)))

(define sample-project (project "sample" (list zk-deployment)))

(create-project-dirs sample-project #t)
; (build-project sample-project)
; (deploy-project sample-project)
