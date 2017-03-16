#lang racket

(require "lib/constants.rkt"
         "lib/container.rkt"
         "lib/exec.rkt"
         "lib/job.rkt"
         "lib/project.rkt"
         "lib/service.rkt")

(define (render-template file-name [context #hash()])
  (foldl (lambda (ctx-cons acc)
           (string-replace acc (format "{{~a}}" (car ctx-cons)) (cdr ctx-cons)))
         (file->string (build-path root-dir "templates" file-name))
         (hash->list context)))

(define (jvm-dockerfile env files run cmd)
  (dockerfile "ubuntu:16.10"
              '("curl" "less" "openjdk-8-jre-headless")
              container-working-dir (hash-set env "TERM" "xterm") files run cmd))

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
  (let* ([config-path (build-path container-working-dir "zoo.cfg")]
         [cfg-context (hash "data_dir" (path->string (build-path container-working-dir ZK_DATA_DIR))
                            "client_port" (~a ZK_PORT))])
    (jvm-dockerfile #hash()
                    (hash "zoo.cfg" (render-template "zoo.cfg" cfg-context))
                    (zk-run "3.4.9")
                    (list "bash" "zookeeper/bin/zkServer.sh" "start-foreground" (path->string config-path)))))

(define zk-service (simple-service "zookeeper" "0.0.1" ZK_PORT zk-dockerfile))

(define MINIO_PORT 9000)

(define minio-dockerfile
  (jvm-dockerfile #hash()
                  #hash()
                  (list "mkdir storage"
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
  (let ([config-path (build-path container-working-dir "server.properties")])
    (jvm-dockerfile #hash()
                    (hash "server.properties.tmpl" (render-template "server.properties.tmpl")
                          "start_kafka.sh" (render-template "start_kafka.sh"))
                    (kafka-run "0.10.1.0" "2.11")
                    (list "bash" "start_kafka.sh"))))

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
  (jvm-dockerfile (hash "SPARK_HOME" (path->string (build-path container-working-dir "spark")))
                  (hash "start_spark_master.sh" (render-template "start_spark_master.sh")
                        "start_spark_worker.sh" (render-template "start_spark_worker.sh"))
                  (spark-run "2.1.0")
                  cmd))

(define spark-master-service
  (let ([dockerfile (spark-dockerfile '("bash" "start_spark_master.sh"))])
    (simple-service "spark-master" "0.0.1" (list SPARK_PORT SPARK_WEBUI_PORT) dockerfile)))

(define spark-worker-service
  (let* ([df (spark-dockerfile '("bash" "start_spark_worker.sh"))]
         [cont (container "spark-worker" "0.0.1" '() df)])
    (service "spark-worker" 2 (list cont) '())))

(define ZEPPELIN_PORT 8080)

(define (zeppelin-run version)
  (let ([with-version (format "zeppelin-~a" version)])
    (list (format "curl -Lo ~a.tgz http://www-eu.apache.org/dist/zeppelin/~a/~a-bin-all.tgz"
                  with-version with-version with-version)
          (format "tar xzf ~a.tgz" with-version)
          (format "mv ~a-bin-all zeppelin" with-version)
          (format "rm ~a.tgz" with-version))))

(define zeppelin-dockerfile
  (jvm-dockerfile #hash()
                  (hash "interpreter.json.tmpl" (render-template "interpreter.json.tmpl")
                        "start_zeppelin.sh" (render-template "start_zeppelin.sh")
                        "zeppelin-site.xml.tmpl" (render-template "zeppelin-site.xml.tmpl")
                        "zeppelin-env.sh" (render-template "zeppelin-env.sh"))
                  (append (zeppelin-run "0.7.0")
                          (spark-run "2.1.0"))
                  '("bash" "start_zeppelin.sh")))

(define zeppelin-service (simple-service "zeppelin" "0.0.1" ZEPPELIN_PORT zeppelin-dockerfile))

(define (producer-files)
  (define scala-dir (build-path root-dir "scala/producer"))
  (hash "server.properties.tmpl" (render-template "server.properties.tmpl")
        "start_producer.sh" (render-template "start_producer.sh")
        "producer-assembly.jar"
        (lambda (dir)
          (displayln (format "> sbt compile: ~a" dir))
          (exec-streaming scala-dir "sbt" "compile" "assembly")
          (copy-file (build-path scala-dir "target/scala-2.12/producer-assembly-0.0.1.jar")
                     (build-path dir "producer-assembly.jar")))
        "data"
        (lambda (dir)
          (define data-dir (build-path root-dir "data"))
          (when (empty? data-dir)
            (error 'missing-data-files "~a" data-dir))
          (copy-directory/files data-dir
                                (build-path dir "data")))))

(define producer-dockerfile
  (jvm-dockerfile #hash()
                  (producer-files)
                  (kafka-run "0.10.1.0" "2.11")
                  '("bash" "start_producer.sh")))

(define producer-container (container "producer" "0.0.1" #f producer-dockerfile))

(define producer-job (job "producer" (list producer-container)))

(define dev-dockerfile
  (jvm-dockerfile #hash()
                  #hash()
                  (append (kafka-run "0.10.1.0" "2.11") (spark-run "2.1.0"))
                  '("sleep" "infinity")))

(define dev-service
  (simple-service "dev" "0.0.1" #f dev-dockerfile))

(define sample-project (project "sample"
                                (list zk-service minio-service kafka-service
                                      spark-master-service spark-worker-service
                                      zeppelin-service
                                      dev-service)
                                (list producer-job)))

(define (run-all)
  (create-project-dirs sample-project #t)
  (build-project sample-project)
  (deploy-project sample-project))
