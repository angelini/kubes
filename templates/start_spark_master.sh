#!/usr/bin/env bash

set -x

spark/sbin/start-master.sh

find spark/logs -name "*$(hostname)*.out" |
  xargs tail --pid "$(find /tmp -name '*.pid' | xargs cat)" -f
