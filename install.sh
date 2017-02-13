#!/usr/bin/env bash

set -x

if ! hash raco 2> /dev/null; then
  echo "racket / raco not installed"
  exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BIN="${DIR}/bin"

MINIKUBE_VERSION="0.16.0"
MINIKUBE_BIN="${BIN}/minikube"

KUBECTL_VERSION="1.5.2"
KUBECTL_BIN="${BIN}/kubectl"

mkdir -p "${BIN}"
mkdir -p "${DIR}/projects"

if [[ ! -f "${MINIKUBE_BIN}" ]]; then
  curl -Lo "${MINIKUBE_BIN}" "https://storage.googleapis.com/minikube/releases/v${MINIKUBE_VERSION}/minikube-darwin-amd64"
  chmod +x "${MINIKUBE_BIN}"
fi

if [[ ! -f "${KUBECTL_BIN}" ]]; then
  curl -Lo "${KUBECTL_BIN}" "https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/darwin/amd64/kubectl"
  chmod +x "${KUBECTL_BIN}"
fi

raco pkg install yaml
