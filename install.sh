#!/usr/bin/env bash

set -x

if ! hash raco 2> /dev/null; then
  echo "racket / raco not installed"
  exit 1
fi

if ! hash sbt 2> /dev/null; then
  echo "sbt not installed"
  exit
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${DIR}/bin"

PLATFORM="$(uname | awk '{print tolower($0)}')"

MINIKUBE_VERSION="0.16.0"
MINIKUBE_BIN="${BIN}/minikube"

KUBECTL_VERSION="1.5.3"
KUBECTL_BIN="${BIN}/kubectl"

DOCKER_KVM_VERSION="0.7.0"
DOCKER_KVM_BIN="${BIN}/docker-machine-driver-kvm"

mkdir -p "${BIN}"
mkdir -p "${DIR}/data"
mkdir -p "${DIR}/projects"
mkdir -p "${DIR}/templates"

if [[ ! -f "${MINIKUBE_BIN}" ]]; then
  # download from HEAD
  curl -Lo "${MINIKUBE_BIN}" "https://storage.googleapis.com/minikube-builds/1050/minikube-linux-amd64"
  # curl -Lo "${MINIKUBE_BIN}" "https://storage.googleapis.com/minikube/releases/v${MINIKUBE_VERSION}/minikube-${PLATFORM}-amd64"
  chmod +x "${MINIKUBE_BIN}"
fi

if [[ ! -f "${KUBECTL_BIN}" ]]; then
  curl -Lo "${KUBECTL_BIN}" "https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/${PLATFORM}/amd64/kubectl"
  chmod +x "${KUBECTL_BIN}"
fi

if [[ "${PLATFORM}" -eq "linux" && ! -f "${DOCKER_KVM_BIN}" ]]; then
  curl -Lo "${DOCKER_KVM_BIN}" "https://github.com/dhiltgen/docker-machine-kvm/releases/download/v${DOCKER_KVM_VERSION}/docker-machine-driver-kvm"
  chmod +x "${DOCKER_KVM_BIN}"
fi

if [[ ! "$(raco pkg show yaml)" =~ "Checksum" ]]; then
  raco pkg install yaml
fi
