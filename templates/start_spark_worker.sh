#!/usr/bin/env bash

set -x

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPARK_DIR="${DIR}/spark"

"${SPARK_DIR}"/sbin/start-slave.sh "${SPARK_MASTER_SERVICE_SERVICE_HOST}:${SPARK_MASTER_SERVICE_SERVICE_PORT}"

find "${SPARK_DIR}/logs" -name "*$(hostname)*.out" | xargs tail --pid "$(find /tmp -name '*.pid' | xargs cat)" -f
