DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="${DIR}/bin:${PATH}"

if [[ "$(minikube status)" != *"Running"* ]]; then
  minikube start --vm-driver=xhyve
fi

eval $(minikube docker-env)
