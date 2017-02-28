#!/usr/bin/env bash

set -x

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPARK_DIR="${DIR}/spark"

"${SPARK_DIR}"/sbin/start-master.sh

find "${SPARK_DIR}/logs" -name "*$(hostname)*.out" | xargs tail --pid "$(find /tmp -name '*.pid' | xargs cat)" -f