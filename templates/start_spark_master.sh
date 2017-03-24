#!/usr/bin/env bash

set -x

unset SPARK_MASTER_PORT
spark/sbin/start-master.sh -h 0.0.0.0 --properties-file spark.conf

find spark/logs -name "*$(hostname)*.out" |
  xargs tail --pid "$(find /tmp -name '*.pid' | xargs cat)" -f
