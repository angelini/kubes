# Kubes

### Install

```
$ ./install.sh
$ source init.sh
```

### Download Data Files

In the `download.rkt` module, run

```racket
(download-all 2015 2017)
```

### Set Up the Cluster

In the `main.rkt` module, run

```racket
(create-project-dirs sample-project #t)
(build-project sample-project)
(deploy-project sample-project)
```

### Start the Kafka Producer

In the `main.rkt` module, run

```racket
(start-jobs sample-project)
```
