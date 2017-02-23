#!/usr/bin/env bash

set -x

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="$(${DIR}/spark/sbin/start-master.sh --host ${SPARK_MASTER_SERVICE_SERVICE_HOST} --port ${SPARK_MASTER_SERVICE_SERVICE_PORT})"

tail -f "$(echo "${OUTPUT}" | awk 'END{print $NF}')"
