#!/usr/bin/env bash

PLATFORM="$(uname | awk '{print tolower($0)}')"

case "${PLATFORM}" in
  "linux")
    COMMAND="sha256sum"
    ARGS=""
    ;;
  "darwin")
    COMMAND="shasum"
    ARGS="-a1"
    ;;
esac

find "${1:-.}" -type f -print0 |
  xargs -0 "${COMMAND}" | "${COMMAND}" |
  awk '{print($1)}' | tr -d '\n'
