#!/usr/bin/env bash

set -x

cat ./zeppelin-site.xml.tmpl |
  sed -e "s/{{ZEPPELIN_HOST}}/${ZEPPELIN_SERVICE_HOST}/g" \
      -e "s/{{ZEPPELIN_PORT}}/${ZEPPELIN_SERVICE_PORT}/g" \
      > zeppelin/conf/zeppelin-site.xml

cat ./interpreter.json.tmpl |
  sed -e "s/{{SPARK_MASTER_HOST}}/${SPARK_MASTER_SERVICE_HOST}/g" \
      -e "s/{{SPARK_MASTER_PORT}}/${SPARK_MASTER_SERVICE_PORT}/g" \
      > zeppelin/conf/interpreter.json

cp zeppelin-env.sh zeppelin/conf/zeppelin-env.sh

export ZEPPELIN_PORT="${ZEPPELIN_SERVICE_PORT}"

exec zeppelin/bin/zeppelin.sh
