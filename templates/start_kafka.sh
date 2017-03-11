#!/usr/bin/env bash

set -x

cat ./server.properties.tmpl |
  sed -e "s/{{ZK_HOST}}/${ZOOKEEPER_SERVICE_HOST}/g" \
      -e "s/{{ZK_PORT}}/${ZOOKEEPER_SERVICE_PORT}/g" \
      -e "s/{{KAFKA_HOST}}/${KAFKA_SERVICE_HOST}/g" \
      -e "s/{{KAFKA_PORT}}/${KAFKA_SERVICE_PORT}/g" \
      > server.properties

exec kafka/bin/kafka-server-start.sh server.properties
