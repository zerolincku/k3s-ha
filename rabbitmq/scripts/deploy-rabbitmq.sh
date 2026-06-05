#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
用法:
  deploy-rabbitmq.sh <config.env>

示例:
  bash rabbitmq/scripts/deploy-rabbitmq.sh rabbitmq/prod.env

说明:
  部署 RabbitMQ Cluster Operator 和 3 节点 RabbitMQ 集群。
  如果是完全离线环境，请先执行 upload-rabbitmq-images.sh，并设置 RABBITMQ_OPERATOR_MANIFEST 为本地文件。
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

CONFIG=$1
if [[ ! -f "$CONFIG" ]]; then
  echo "配置文件不存在: $CONFIG" >&2
  exit 1
fi

ENV_KUBECONFIG=${KUBECONFIG:-}
ENV_RABBITMQ_NAMESPACE=${RABBITMQ_NAMESPACE:-}
ENV_RABBITMQ_CLUSTER_NAME=${RABBITMQ_CLUSTER_NAME:-}
ENV_RABBITMQ_REPLICAS=${RABBITMQ_REPLICAS:-}
ENV_RABBITMQ_IMAGE=${RABBITMQ_IMAGE:-}
ENV_RABBITMQ_OPERATOR_MANIFEST=${RABBITMQ_OPERATOR_MANIFEST:-}
ENV_RABBITMQ_OPERATOR_MANIFEST_URL=${RABBITMQ_OPERATOR_MANIFEST_URL:-}
ENV_RABBITMQ_INSTALL_OPERATOR=${RABBITMQ_INSTALL_OPERATOR:-}
ENV_RABBITMQ_WAIT_TIMEOUT=${RABBITMQ_WAIT_TIMEOUT:-}
ENV_RABBITMQ_STORAGE_CLASS=${RABBITMQ_STORAGE_CLASS:-}
ENV_RABBITMQ_STORAGE=${RABBITMQ_STORAGE:-}
ENV_RABBITMQ_CPU_REQUEST=${RABBITMQ_CPU_REQUEST:-}
ENV_RABBITMQ_CPU_LIMIT=${RABBITMQ_CPU_LIMIT:-}
ENV_RABBITMQ_MEMORY_REQUEST=${RABBITMQ_MEMORY_REQUEST:-}
ENV_RABBITMQ_MEMORY_LIMIT=${RABBITMQ_MEMORY_LIMIT:-}
ENV_RABBITMQ_DEFAULT_QUEUE_TYPE=${RABBITMQ_DEFAULT_QUEUE_TYPE:-}
ENV_RABBITMQ_VM_MEMORY_HIGH_WATERMARK=${RABBITMQ_VM_MEMORY_HIGH_WATERMARK:-}
ENV_RABBITMQ_DISK_FREE_LIMIT=${RABBITMQ_DISK_FREE_LIMIT:-}

# shellcheck disable=SC1090
source "$CONFIG"

KUBECONFIG=${ENV_KUBECONFIG:-${KUBECONFIG:-}}
RABBITMQ_NAMESPACE=${ENV_RABBITMQ_NAMESPACE:-${RABBITMQ_NAMESPACE:-rabbitmq}}
RABBITMQ_CLUSTER_NAME=${ENV_RABBITMQ_CLUSTER_NAME:-${RABBITMQ_CLUSTER_NAME:-rabbitmq}}
RABBITMQ_REPLICAS=${ENV_RABBITMQ_REPLICAS:-${RABBITMQ_REPLICAS:-3}}
RABBITMQ_IMAGE=${ENV_RABBITMQ_IMAGE:-${RABBITMQ_IMAGE:-rabbitmq:4.3.1-management}}
RABBITMQ_OPERATOR_MANIFEST=${ENV_RABBITMQ_OPERATOR_MANIFEST:-${RABBITMQ_OPERATOR_MANIFEST:-}}
RABBITMQ_OPERATOR_MANIFEST_URL=${ENV_RABBITMQ_OPERATOR_MANIFEST_URL:-${RABBITMQ_OPERATOR_MANIFEST_URL:-https://github.com/rabbitmq/cluster-operator/releases/download/v2.21.0/cluster-operator.yml}}
RABBITMQ_INSTALL_OPERATOR=${ENV_RABBITMQ_INSTALL_OPERATOR:-${RABBITMQ_INSTALL_OPERATOR:-true}}
RABBITMQ_WAIT_TIMEOUT=${ENV_RABBITMQ_WAIT_TIMEOUT:-${RABBITMQ_WAIT_TIMEOUT:-600s}}
RABBITMQ_STORAGE_CLASS=${ENV_RABBITMQ_STORAGE_CLASS:-${RABBITMQ_STORAGE_CLASS:-local-path}}
RABBITMQ_STORAGE=${ENV_RABBITMQ_STORAGE:-${RABBITMQ_STORAGE:-20Gi}}
RABBITMQ_CPU_REQUEST=${ENV_RABBITMQ_CPU_REQUEST:-${RABBITMQ_CPU_REQUEST:-500m}}
RABBITMQ_CPU_LIMIT=${ENV_RABBITMQ_CPU_LIMIT:-${RABBITMQ_CPU_LIMIT:-1000m}}
RABBITMQ_MEMORY_REQUEST=${ENV_RABBITMQ_MEMORY_REQUEST:-${RABBITMQ_MEMORY_REQUEST:-1Gi}}
RABBITMQ_MEMORY_LIMIT=${ENV_RABBITMQ_MEMORY_LIMIT:-${RABBITMQ_MEMORY_LIMIT:-1Gi}}
RABBITMQ_DEFAULT_QUEUE_TYPE=${ENV_RABBITMQ_DEFAULT_QUEUE_TYPE:-${RABBITMQ_DEFAULT_QUEUE_TYPE:-quorum}}
RABBITMQ_VM_MEMORY_HIGH_WATERMARK=${ENV_RABBITMQ_VM_MEMORY_HIGH_WATERMARK:-${RABBITMQ_VM_MEMORY_HIGH_WATERMARK:-0.60}}
RABBITMQ_DISK_FREE_LIMIT=${ENV_RABBITMQ_DISK_FREE_LIMIT:-${RABBITMQ_DISK_FREE_LIMIT:-1GB}}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少本地命令: $1" >&2
    exit 1
  }
}

escape_sed() {
  printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

wait_statefulset_created() {
  local namespace=$1
  local statefulset=$2

  echo "等待 StatefulSet 创建: ${namespace}/${statefulset}"
  for _ in {1..60}; do
    if kubectl -n "$namespace" get statefulset "$statefulset" >/dev/null 2>&1; then
      return
    fi
    sleep 5
  done

  echo "等待 StatefulSet 创建超时: ${namespace}/${statefulset}" >&2
  kubectl -n "$namespace" get events --sort-by=.lastTimestamp | tail -30 || true
  exit 1
}

require_cmd kubectl
require_cmd sed
require_cmd mktemp
require_cmd tail

if [[ -n "$KUBECONFIG" ]]; then
  export KUBECONFIG
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RESOURCE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$RESOURCE_DIR/manifests/rabbitmq-cluster.yaml.tpl"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "找不到 manifest 模板: $TEMPLATE" >&2
  exit 1
fi

rendered=$(mktemp "${TMPDIR:-/tmp}/rabbitmq-cluster.XXXXXX.yaml")
trap 'rm -f "$rendered"' EXIT

echo "检查 Kubernetes 连接"
kubectl version --client >/dev/null
kubectl cluster-info >/dev/null

if [[ "$RABBITMQ_INSTALL_OPERATOR" == "true" ]]; then
  if [[ -n "$RABBITMQ_OPERATOR_MANIFEST" ]]; then
    if [[ ! -f "$RABBITMQ_OPERATOR_MANIFEST" ]]; then
      echo "找不到 RABBITMQ_OPERATOR_MANIFEST: $RABBITMQ_OPERATOR_MANIFEST" >&2
      exit 1
    fi
    echo "应用 RabbitMQ Cluster Operator 本地 manifest: $RABBITMQ_OPERATOR_MANIFEST"
    kubectl apply -f "$RABBITMQ_OPERATOR_MANIFEST"
  else
    echo "应用 RabbitMQ Cluster Operator 在线 manifest: $RABBITMQ_OPERATOR_MANIFEST_URL"
    kubectl apply -f "$RABBITMQ_OPERATOR_MANIFEST_URL"
  fi

  echo "等待 RabbitMQ Cluster Operator 就绪"
  kubectl -n rabbitmq-system rollout status deployment/rabbitmq-cluster-operator --timeout="$RABBITMQ_WAIT_TIMEOUT"
else
  echo "跳过 RabbitMQ Cluster Operator 安装，确认集群中已经存在 CRD 和 Operator。"
fi

sed \
  -e "s|__RABBITMQ_NAMESPACE__|$(escape_sed "$RABBITMQ_NAMESPACE")|g" \
  -e "s|__RABBITMQ_CLUSTER_NAME__|$(escape_sed "$RABBITMQ_CLUSTER_NAME")|g" \
  -e "s|__RABBITMQ_REPLICAS__|$(escape_sed "$RABBITMQ_REPLICAS")|g" \
  -e "s|__RABBITMQ_IMAGE__|$(escape_sed "$RABBITMQ_IMAGE")|g" \
  -e "s|__RABBITMQ_STORAGE_CLASS__|$(escape_sed "$RABBITMQ_STORAGE_CLASS")|g" \
  -e "s|__RABBITMQ_STORAGE__|$(escape_sed "$RABBITMQ_STORAGE")|g" \
  -e "s|__RABBITMQ_CPU_REQUEST__|$(escape_sed "$RABBITMQ_CPU_REQUEST")|g" \
  -e "s|__RABBITMQ_CPU_LIMIT__|$(escape_sed "$RABBITMQ_CPU_LIMIT")|g" \
  -e "s|__RABBITMQ_MEMORY_REQUEST__|$(escape_sed "$RABBITMQ_MEMORY_REQUEST")|g" \
  -e "s|__RABBITMQ_MEMORY_LIMIT__|$(escape_sed "$RABBITMQ_MEMORY_LIMIT")|g" \
  -e "s|__RABBITMQ_DEFAULT_QUEUE_TYPE__|$(escape_sed "$RABBITMQ_DEFAULT_QUEUE_TYPE")|g" \
  -e "s|__RABBITMQ_VM_MEMORY_HIGH_WATERMARK__|$(escape_sed "$RABBITMQ_VM_MEMORY_HIGH_WATERMARK")|g" \
  -e "s|__RABBITMQ_DISK_FREE_LIMIT__|$(escape_sed "$RABBITMQ_DISK_FREE_LIMIT")|g" \
  "$TEMPLATE" >"$rendered"

echo "应用 RabbitMQ 集群资源: ${RABBITMQ_NAMESPACE}/${RABBITMQ_CLUSTER_NAME}"
kubectl apply -f "$rendered"

statefulset="${RABBITMQ_CLUSTER_NAME}-server"
wait_statefulset_created "$RABBITMQ_NAMESPACE" "$statefulset"

echo "等待 RabbitMQ StatefulSet 就绪"
kubectl -n "$RABBITMQ_NAMESPACE" rollout status "statefulset/$statefulset" --timeout="$RABBITMQ_WAIT_TIMEOUT"

echo "当前 Pod 状态"
kubectl -n "$RABBITMQ_NAMESPACE" get pods -o wide

echo "当前 PVC 状态"
kubectl -n "$RABBITMQ_NAMESPACE" get pvc -o wide

echo "当前 Service 状态"
kubectl -n "$RABBITMQ_NAMESPACE" get svc

echo "RabbitMQ 集群状态"
kubectl -n "$RABBITMQ_NAMESPACE" exec "${statefulset}-0" -- rabbitmq-diagnostics cluster_status || true

echo "完成"
