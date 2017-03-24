#lang racket

(require "lib/cache.rkt"
         "lib/constants.rkt"
         "lib/container.rkt"
         "lib/exec.rkt"
         "lib/job.rkt"
         "lib/project.rkt"
         "lib/service.rkt"
         "lib/volume.rkt")

(define (render-template file-name [context #hash()])
  (foldl (lambda (ctx-cons acc)
           (string-replace acc (format "{{~a}}" (car ctx-cons)) (cdr ctx-cons)))
         (file->string (build-path root-dir "templates" file-name))
         (hash->list context)))

(define WORKING_DIR (string->path "/home/root"))

(define (jvm-dockerfile run cmd
                        #:env [env #hash()]
                        #:files [files #hash()]
                        #:include-python [py #f])
  (let* ([packages '("curl" "less" "openjdk-8-jre-headless")]
         [packages (if py
                       (append packages '("python3" "python3-pip"))
                       packages)])
    (dockerfile "ubuntu:16.10" packages WORKING_DIR
                (hash-set env "TERM" "xterm") files run cmd)))

(define ZK_PORT 2181)
(define ZK_DATA_DIR "zk_data")

(define (zk-run version)
  (let ([with-version (format "zookeeper-~a" version)])
    (list (format "mkdir -p ./~a" ZK_DATA_DIR)
          (format "curl -LO http://apache.forsale.plus/zookeeper/~a/~a.tar.gz" with-version with-version)
          (format "tar xzf ~a.tar.gz" with-version)
          (format "mv ~a zookeeper" with-version)
          (format "rm ~a.tar.gz" with-version))))

(define zk-dockerfile
  (let* ([config-path (build-path WORKING_DIR "zoo.cfg")]
         [cfg-context (hash "data_dir" (path->string (build-path WORKING_DIR ZK_DATA_DIR))
                            "client_port" (~a ZK_PORT))])
    (jvm-dockerfile (zk-run "3.4.9")
                    (list "bash" "zookeeper/bin/zkServer.sh" "start-foreground" (path->string config-path))
                    #:files (hash "zoo.cfg" (render-template "zoo.cfg" cfg-context)))))

(define zk-service (simple-service "zookeeper" "0.0.1" ZK_PORT zk-dockerfile))

(define MINIO_PORT 9000)

(define minio-dockerfile
  (jvm-dockerfile (list "mkdir storage"
                        "curl -LO https://dl.minio.io/server/minio/release/linux-amd64/minio"
                        "chmod +x minio")
                  (list "./minio" "server" "~/storage")))

(define minio-service (simple-service "minio" "0.0.1" MINIO_PORT minio-dockerfile))

(define KAFKA_PORT 9092)

(define (kafka-run kafka-version scala-version)
  (let ([with-version (format "kafka_~a-~a" scala-version kafka-version)])
    (list (format "curl -LO http://www-eu.apache.org/dist/kafka/~a/~a.tgz" kafka-version with-version)
          (format "tar xzf ~a.tgz" with-version)
          (format "mv ~a kafka" with-version)
          (format "rm ~a.tgz" with-version))))

(define kafka-dockerfile
  (let ([config-path (build-path WORKING_DIR "server.properties")])
    (jvm-dockerfile (kafka-run "0.10.1.0" "2.11")
                    (list "bash" "start_kafka.sh")
                    #:files (hash "server.properties.tmpl" (render-template "server.properties.tmpl")
                                  "start_kafka.sh" (render-template "start_kafka.sh")))))

(define kafka-service (simple-service "kafka" "0.0.1" KAFKA_PORT kafka-dockerfile))

(define SPARK_PORT 7077)
(define SPARK_WEBUI_PORT 8080)
(define SPARK_HISTORY_PORT 18080)

(define (spark-run version)
  (let ([with-version (format "spark-~a" version)])
    (list (format "curl -Lo ~a.tgz http://d3kbcqa49mib13.cloudfront.net/~a-bin-hadoop2.7.tgz"
                  with-version with-version)
          (format "tar xzf ~a.tgz" with-version)
          (format "mv ~a-bin-hadoop2.7 spark" with-version)
          (format "rm ~a.tgz" with-version))))

(define (spark-dockerfile cmd)
  (jvm-dockerfile (spark-run "2.1.0") cmd
                  #:env (hash "SPARK_HOME" (path->string (build-path WORKING_DIR "spark")))
                  #:files (hash "start_spark_master.sh" (render-template "start_spark_master.sh")
                                "start_spark_worker.sh" (render-template "start_spark_worker.sh")
                                "spark.conf" (render-template "spark.conf"))))

(define spark-master-service
  (let ([dockerfile (spark-dockerfile '("bash" "start_spark_master.sh"))])
    (simple-service "spark-master" "0.0.1" (list SPARK_PORT SPARK_WEBUI_PORT) dockerfile)))

(define spark-worker-service
  (let* ([df (spark-dockerfile '("bash" "start_spark_worker.sh"))]
         [cont (container "spark-worker" "0.0.1" '() #hash() df)])
    (service "spark-worker" 2 (list cont) '() '())))

(define ZEPPELIN_PORT 8080)

(define (zeppelin-run version)
  (let ([with-version (format "zeppelin-~a" version)])
    (list (format "curl -Lo ~a.tgz http://www-eu.apache.org/dist/zeppelin/~a/~a-bin-all.tgz"
                  with-version with-version with-version)
          (format "tar xzf ~a.tgz" with-version)
          (format "mv ~a-bin-all zeppelin" with-version)
          (format "rm ~a.tgz" with-version))))

(define zeppelin-dockerfile
  (jvm-dockerfile (append (zeppelin-run "0.7.0")
                          (spark-run "2.1.0"))
                  '("bash" "start_zeppelin.sh")
                  #:files (hash "interpreter.json.tmpl" (render-template "interpreter.json.tmpl")
                                "start_zeppelin.sh" (render-template "start_zeppelin.sh")
                                "zeppelin-site.xml.tmpl" (render-template "zeppelin-site.xml.tmpl")
                                "zeppelin-env.sh" (render-template "zeppelin-env.sh"))))

(define zeppelin-volume (volume "zeppelin-notebooks" 1 (build-path "/data/zeppelin-notebooks")))

(define zeppelin-container (container "zeppelin" "0.0.1" (list ZEPPELIN_PORT)
                                      (hash "/home/root/mount" zeppelin-volume)
                                      zeppelin-dockerfile))

(define zeppelin-service (service "zeppelin" 1
                                  (list zeppelin-container)
                                  (list ZEPPELIN_PORT)
                                  (list zeppelin-volume)))

(define JUPYTER_PORT 8888)

(define jupyter-dockerfile
  (let* ([build-string-path (lambda args (path->string (apply build-path args)))]
         [spark-dir (build-string-path WORKING_DIR "spark")]
         [paths (hash "spark_dir" spark-dir
                      "pyspark_dir" (build-string-path spark-dir "python")
                      "py4j_dir" (build-string-path spark-dir "python" "lib" "py4j-0.10.4-src.zip"))])
    (jvm-dockerfile (append '("pip3 install --upgrade pip"
                              "pip3 install jupyter")
                            (spark-run "2.1.0"))
                    (list "bash" "start_jupyter.sh")
                    #:files (hash "start_jupyter.sh" (render-template "start_jupyter.sh" paths))
                    #:include-python #t)))

(define jupyter-volume (volume "jupyter-notebooks" 1 (build-path "/data/jupyter-notebooks")))

(define jupyter-container (container "jupyter" "0.0.1" (list JUPYTER_PORT)
                                     (hash "/home/root/mount" jupyter-volume)
                                     jupyter-dockerfile))

(define jupyter-service (service "jupyter" 1
                                 (list jupyter-container)
                                 (list JUPYTER_PORT)
                                 (list jupyter-volume)))

(define (producer-files)
  (define scala-dir (build-path root-dir "scala/producer"))
  (hash "server.properties.tmpl" (render-template "server.properties.tmpl")
        "start_producer.sh" (render-template "start_producer.sh")
        "producer-assembly.jar"
        (lambda (dir)
          (displayln (format "> sbt compile: ~a" dir))
          (if (has-directory-changed? (build-path scala-dir "src") scala-dir)
              (exec-streaming scala-dir "sbt" "compile" "assembly")
              (displayln (format "> skip compile: ~a" dir)))
          (copy-file (build-path scala-dir "target/scala-2.12/producer-assembly-0.0.1.jar")
                     (build-path dir "producer-assembly.jar"))
          (write-dir-hash (build-path scala-dir "src") scala-dir))
        "data"
        (lambda (dir)
          (define data-dir (build-path root-dir "data"))
          (when (empty? data-dir)
            (error 'missing-data-files "~a" data-dir))
          (copy-directory/files data-dir
                                (build-path dir "data")))))

(define producer-dockerfile
  (jvm-dockerfile (kafka-run "0.10.1.0" "2.11")
                  '("bash" "start_producer.sh")
                  #:files (producer-files)))

(define producer-container (container "producer" "0.0.1" '() #hash() producer-dockerfile))

(define producer-job (job "producer" (list producer-container)))

(define dev-dockerfile
  (jvm-dockerfile (append (kafka-run "0.10.1.0" "2.11") (spark-run "2.1.0"))
                  '("sleep" "infinity")))

(define dev-service
  (simple-service "dev" "0.0.1" '() dev-dockerfile))

(define sample-project (project "sample"
                                (list zk-service minio-service kafka-service
                                      spark-master-service spark-worker-service
                                      ;; zeppelin-service
                                      jupyter-service
                                      dev-service)
                                (list producer-job)))

(define (run-all)
  (create-project-dirs sample-project #t)
  (build-project sample-project)
  (deploy-project sample-project))
