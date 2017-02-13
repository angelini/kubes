DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export PATH="${DIR}/bin:${PATH}"

eval $(minikube docker-env)
