#!/usr/bin/env bash

set -x

export SPARK_HOME="{{spark_dir}}"
export PATH="{{pyspark_dir}}:{{py4j_dir}}:${PATH}"
export PYTHONPATH="{{pyspark_dir}}:{{py4j_dir}}:${PYTHONPATH}"

jupyter notebook \
        --port "${JUPYTER_SERVICE_PORT}" \
        --ip "*" \
        --NotebookApp.allow_origin="*"
        --no-browser \
        --debug
