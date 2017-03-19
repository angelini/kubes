#lang typed/racket

(require/typed yaml
  [yaml->string (-> Any String)])
(require "constants.rkt"
         "exec.rkt"
         "utils.rkt")

(provide create-volume-and-claim
         create-volume-files
         delete-volume
         delete-volume-claim
         volume
         volume->hash
         volume-exists?
         volume-name)

(struct volume ([name : String] [size : Integer] [path : Path]))

(: volume-claim-name (-> volume String))
(define (volume-claim-name vol)
  (format "~a-claim" (volume-name vol)))

(: volume-file (-> volume String))
(define (volume-file vol)
  (format "~a-volume.yml" (volume-name vol)))

(: volume-claim-file (-> volume String))
(define (volume-claim-file vol)
  (format "~a-claim.yml" (volume-name vol)))

(: volume-dir (-> Path volume Path))
(define (volume-dir serv-dir vol)
  (build-path serv-dir "volumes"))

(: volume->hash (-> volume (HashTable String Any)))
(define (volume->hash vol)
  (hash "name" (volume-name vol)
        "persistentVolumeClaim" (hash "claimName" (volume-claim-name vol))))

(: volume->yaml (-> volume String))
(define (volume->yaml vol)
  (define spec (hash "capacity" (hash "storage" (format "~aGi" (volume-size vol)))
                     "accessModes" (list "ReadWriteOnce")
                     "persistentVolumeReclaimPolicy" "Retain"
                     "hostPath" (hash "path" (path->string (volume-path vol)))))
  (yaml->string
   (hash "kind" "PersistentVolume"
         "apiVersion" "v1"
         "metadata" (hash "name" (format "~a-volume" (volume-name vol))
                          "labels" (hash "volume-name" (volume-name vol)))
         "spec" spec)))

(: volume->claim-yaml (-> volume String))
(define (volume->claim-yaml vol)
  (define spec (hash "resources" (hash "requests" (hash "storage"
                                                        (format "~aGi" (volume-size vol))))
                     "accessModes" (list "ReadWriteOnce")
                     "selector" (hash "matchLabels" (hash "volume-name"
                                                          (volume-name vol)))))
  (yaml->string
   (hash "kind" "PersistentVolumeClaim"
         "apiVersion" "v1"
         "metadata" (hash "name" (volume-claim-name vol))
         "spec" spec)))

(: create-volume-files (-> Path volume Void))
(define (create-volume-files vol-dir vol)
  (write-file vol-dir (volume-file vol) (volume->yaml vol))
  (write-file vol-dir (volume-claim-file vol) (volume->claim-yaml vol)))

(: create-volume-and-claim (-> String Path volume String))
(define (create-volume-and-claim proj-name serv-dir vol)
  (displayln (format "> create volume: ~a" (volume-name vol)))
  (kubectl-create proj-name (build-path (volume-dir serv-dir vol) (volume-file vol)) '#:streaming)
  (kubectl-create proj-name (build-path (volume-dir serv-dir vol) (volume-claim-file vol)) '#:streaming)
  (volume-name vol))

(: delete-volume (-> String volume Boolean))
(define (delete-volume proj-name vol)
  (define args (list "persistentvolume" (format "~a-volume" (volume-name vol))))
  (not (void? (when (kubectl-get proj-name args)
                (displayln (format "> delete volume: ~a" (volume-name vol)))
                (kubectl-delete proj-name args '#:raise)))))

(: delete-volume-claim (-> String volume Boolean))
(define (delete-volume-claim proj-name vol)
  (define args (list "persistentvolumeclaim" (volume-claim-name vol)))
  (not (void? (when (kubectl-get proj-name args)
                (displayln (format "> delete claim: ~a" (volume-name vol)))
                (kubectl-delete proj-name args '#:raise)))))

(: volume-exists? (-> String volume Boolean))
(define (volume-exists? proj-name vol)
  (define args (list "persistentvolume" (format "~a-volume" (volume-name vol))))
  (not (boolean? (kubectl-get proj-name args))))
