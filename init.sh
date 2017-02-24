DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM="$(uname | awk '{print tolower($0)}')"

case "${PLATFORM}" in
  "linux") DRIVER="kvm" ;;
  "darwin") DRIVER="xhyve" ;;
esac

export PATH="${DIR}/bin:${PATH}"
unset HADOOP_CONF_DIR

if [[ ! "$(minikube status)" =~ "Running" ]]; then
  minikube start --vm-driver="${DRIVER}" --cpus 6 --memory 6144
fi

eval $(minikube docker-env)
