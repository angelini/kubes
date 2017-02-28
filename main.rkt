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
              '("curl" "openjdk-8-jre-headless")
              container-working-dir env files run cmd))

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

(define KAFKA_PORT 9092)

(define (kafka-run version)
  (let ([with-version (format "kafka_2.11-~a" version)])
    (list (format "curl -LO http://www-eu.apache.org/dist/kafka/~a/~a.tgz" version with-version)
          (format "tar xzf ~a.tgz" with-version)
          (format "mv ~a kafka" with-version)
          (format "rm ~a.tgz" with-version))))

(define kafka-dockerfile
  (let ([config-path (build-path container-working-dir "server.properties")])
    (jvm-dockerfile #hash()
                    (hash "server.properties.tmpl" (render-template "server.properties.tmpl")
                          "start_kafka.sh" (render-template "start_kafka.sh"))
                    (kafka-run "0.10.1.0")
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
    (service "spark-worker" 3 (list cont) '())))

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
                  (kafka-run "0.10.1.0")
                  (list "bash" "start_producer.sh")))

(define producer-container (container "producer" "0.0.1" #f producer-dockerfile))

(define producer-job (job "producer" (list producer-container)))

(define max-volume-per-day-dockerfile
  (jvm-dockerfile #hash()
                  #hash()
                  '()
                  (list "bash")))

(define max-volume-per-day-service
  (simple-service "max-volume-per-day" "0.0.1" #f max-volume-per-day-dockerfile))

(define sample-project (project "sample"
                                (list zk-service kafka-service
                                      spark-master-service spark-worker-service
                                      ; max-vol-per-day-service
                                      )
                                (list producer-job)))

(define (run-all)
  (create-project-dirs sample-project #t)
  (build-project sample-project)
  (deploy-project sample-project))
