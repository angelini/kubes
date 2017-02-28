#!/usr/bin/env bash

set -x

spark/sbin/start-slave.sh "${SPARK_MASTER_SERVICE_HOST}:${SPARK_MASTER_SERVICE_PORT}"

find spark/logs -name "*$(hostname)*.out" |
  xargs tail --pid "$(find /tmp -name '*.pid' | xargs cat)" -f
