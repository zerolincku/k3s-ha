#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
用法:
  deploy-redis-sentinel.sh <config.env>

示例:
  bash redis/scripts/deploy-redis-sentinel.sh redis/prod.env
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
ENV_REDIS_NAMESPACE=${REDIS_NAMESPACE:-}
ENV_REDIS_IMAGE=${REDIS_IMAGE:-}
ENV_REDIS_PASSWORD=${REDIS_PASSWORD:-}

# shellcheck disable=SC1090
source "$CONFIG"

KUBECONFIG=${ENV_KUBECONFIG:-${KUBECONFIG:-}}
REDIS_NAMESPACE=${ENV_REDIS_NAMESPACE:-${REDIS_NAMESPACE:-redis}}
REDIS_IMAGE=${ENV_REDIS_IMAGE:-${REDIS_IMAGE:-redis:7.2.4}}
REDIS_PASSWORD=${ENV_REDIS_PASSWORD:-${REDIS_PASSWORD:-}}
REDIS_MASTER_NAME=${REDIS_MASTER_NAME:-mymaster}
REDIS_MAXMEMORY=${REDIS_MAXMEMORY:-256mb}
REDIS_MAXMEMORY_POLICY=${REDIS_MAXMEMORY_POLICY:-allkeys-lru}
REDIS_SENTINEL_QUORUM=${REDIS_SENTINEL_QUORUM:-2}
REDIS_SENTINEL_DOWN_AFTER_MS=${REDIS_SENTINEL_DOWN_AFTER_MS:-10000}
REDIS_SENTINEL_FAILOVER_TIMEOUT_MS=${REDIS_SENTINEL_FAILOVER_TIMEOUT_MS:-60000}
REDIS_SENTINEL_PARALLEL_SYNCS=${REDIS_SENTINEL_PARALLEL_SYNCS:-1}
REDIS_WAIT_TIMEOUT=${REDIS_WAIT_TIMEOUT:-300s}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少本地命令: $1" >&2
    exit 1
  }
}

escape_sed() {
  printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

require_cmd kubectl
require_cmd sed
require_cmd mktemp

if [[ -n "$KUBECONFIG" ]]; then
  export KUBECONFIG
fi

if [[ -z "$REDIS_PASSWORD" || "$REDIS_PASSWORD" == "change-me-use-openssl-rand-base64-24" ]]; then
  echo "部署前必须修改 REDIS_PASSWORD。" >&2
  echo "示例: openssl rand -base64 24" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RESOURCE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$RESOURCE_DIR/manifests/redis-sentinel.yaml.tpl"

if [[ ! -f "$TEMPLATE" ]]; then
  echo "找不到 manifest 模板: $TEMPLATE" >&2
  exit 1
fi

rendered=$(mktemp "${TMPDIR:-/tmp}/redis-sentinel.XXXXXX.yaml")
trap 'rm -f "$rendered"' EXIT

echo "检查 Kubernetes 连接"
kubectl version --client >/dev/null
kubectl cluster-info >/dev/null

echo "创建命名空间: $REDIS_NAMESPACE"
kubectl create namespace "$REDIS_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "创建 Redis 密码 Secret: redis-auth"
kubectl -n "$REDIS_NAMESPACE" create secret generic redis-auth \
  --from-literal=password="$REDIS_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

sed \
  -e "s|__REDIS_NAMESPACE__|$(escape_sed "$REDIS_NAMESPACE")|g" \
  -e "s|__REDIS_IMAGE__|$(escape_sed "$REDIS_IMAGE")|g" \
  -e "s|__REDIS_MASTER_NAME__|$(escape_sed "$REDIS_MASTER_NAME")|g" \
  -e "s|__REDIS_MAXMEMORY__|$(escape_sed "$REDIS_MAXMEMORY")|g" \
  -e "s|__REDIS_MAXMEMORY_POLICY__|$(escape_sed "$REDIS_MAXMEMORY_POLICY")|g" \
  -e "s|__REDIS_SENTINEL_QUORUM__|$(escape_sed "$REDIS_SENTINEL_QUORUM")|g" \
  -e "s|__REDIS_SENTINEL_DOWN_AFTER_MS__|$(escape_sed "$REDIS_SENTINEL_DOWN_AFTER_MS")|g" \
  -e "s|__REDIS_SENTINEL_FAILOVER_TIMEOUT_MS__|$(escape_sed "$REDIS_SENTINEL_FAILOVER_TIMEOUT_MS")|g" \
  -e "s|__REDIS_SENTINEL_PARALLEL_SYNCS__|$(escape_sed "$REDIS_SENTINEL_PARALLEL_SYNCS")|g" \
  "$TEMPLATE" >"$rendered"

echo "应用 Redis Sentinel 资源"
kubectl apply -f "$rendered"

echo "等待 Redis StatefulSet 就绪"
kubectl -n "$REDIS_NAMESPACE" rollout status statefulset/redis --timeout="$REDIS_WAIT_TIMEOUT"

echo "等待 Sentinel StatefulSet 就绪"
kubectl -n "$REDIS_NAMESPACE" rollout status statefulset/sentinel --timeout="$REDIS_WAIT_TIMEOUT"

echo "当前 Pod 状态"
kubectl -n "$REDIS_NAMESPACE" get pods -o wide

echo "Sentinel 当前 master"
kubectl -n "$REDIS_NAMESPACE" exec sentinel-0 -- \
  redis-cli -p 26379 sentinel get-master-addr-by-name "$REDIS_MASTER_NAME" || true

echo "完成"
