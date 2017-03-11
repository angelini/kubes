#!/usr/bin/env bash

set -x

cat ./s3.properties.tmpl |
  sed -e "s/{{MINIO_HOST}}/${MINIO_SERVICE_HOST}/g" \
      -e "s/{{MINIO_PORT}}/${MINIO_SERVICE_PORT}/g" \
      > s3.properties

exec kafka/bin/connect-standalone.sh s3.properties
