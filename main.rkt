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

(define (jvm-dockerfile working-dir files run cmd)
  (dockerfile "alpine:3.5"
              '("bash" "curl" "openjdk8-jre-base")
              working-dir files run cmd))

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
  (let* ([working-dir (string->path "/home/root")]
         [config-path (build-path working-dir "zoo.cfg")]
         [cfg-context (hash "data_dir" (path->string (build-path working-dir ZK_DATA_DIR))
                            "client_port" (~a ZK_PORT))])
    (jvm-dockerfile working-dir
                    (hash "zoo.cfg" (render-template "zoo.cfg" cfg-context))
                    (zk-run "3.4.9")
                    (list "bash" "zookeeper/bin/zkServer.sh" "start-foreground" (path->string config-path)))))

(define zk-container (container "zookeeper" "0.0.1" ZK_PORT zk-dockerfile))

(define zk-service (service "zookeeper" 1 (list zk-container) (list (cons ZK_PORT ZK_PORT))))

(define KAFKA_PORT 9092)

(define (kafka-run version)
  (let ([with-version (format "kafka_2.11-~a" version)])
    (list (format "curl -LO http://www-eu.apache.org/dist/kafka/~a/~a.tgz" version with-version)
          (format "tar xzf ~a.tgz" with-version)
          (format "mv ~a kafka" with-version)
          (format "rm ~a.tgz" with-version))))

(define kafka-dockerfile
  (let* ([working-dir (string->path "/home/root")]
         [config-path (build-path working-dir "server.properties")])
    (jvm-dockerfile working-dir
                    (hash "server.properties.tmpl" (render-template "server.properties.tmpl")
                          "start_kafka.sh" (render-template "start_kafka.sh" #hash()))
                    (kafka-run "0.10.1.0")
                    (list "bash" "start_kafka.sh"))))

(define kafka-container (container "kafka" "0.0.1" KAFKA_PORT kafka-dockerfile))

(define kafka-service (service "kafka" 1 (list kafka-container) (list (cons KAFKA_PORT KAFKA_PORT))))

(define (producer-files)
  (define scala-dir (build-path root-dir "scala/producer"))
  (hash "producer-assembly.jar"
        (lambda (dir)
          (exec-raise scala-dir "sbt" "compile" "assembly")
          (copy-file (build-path scala-dir "target/scala-2.12/producer-assembly-0.0.1.jar")
                     (build-path dir "producer-assembly.jar")))
        "data"
        (lambda (dir)
          (copy-directory/files (build-path root-dir "data")
                                (build-path dir "data")))))

(define producer-dockerfile
  (let ([working-dir (string->path "/home/root")])
    (jvm-dockerfile working-dir
                    (producer-files)
                    '()
                    (list "java" "-jar" "producer-assembly.jar"))))

(define producer-container (container "producer" "0.0.1" #f producer-dockerfile))

(define producer-job (job "producer" (list producer-container)))

(define sample-project (project "sample"
                                (list zk-service kafka-service)
                                (list producer-job)))

; (create-project-dirs sample-project #t)
; (build-project sample-project)
; (deploy-project sample-project)
