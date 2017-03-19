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

### Kubes CLI

```
$ kubes -h
bin/kubes allows you to interact with a runnings kubes project

Usage:
  kubes [command] [namespace] [arg ...]

Available Commands:
  connect    Connect to a bash shell on a random running pod
  dash       Open the dashboard at the correct namespace
  logs       Follow logs from a random pod within the specified app
```
