#!/usr/bin/env bash

set -x

kafka/bin/kafka-topics.sh --create --zookeeper "${ZOOKEEPER_SERVICE_SERVICE_HOST}:${ZOOKEEPER_SERVICE_SERVICE_PORT}" --replication-factor 1 --partitions 1 --topic sample_topic

exec java -jar producer-assembly.jar
