DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PATH="${DIR}/bin:${PATH}"
unset HADOOP_CONF_DIR

if [[ "$(minikube status)" != *"Running"* ]]; then
  minikube start --vm-driver=xhyve
fi

eval $(minikube docker-env)
