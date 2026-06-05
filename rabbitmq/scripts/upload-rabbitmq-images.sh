#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
用法:
  upload-rabbitmq-images.sh <config.env>

说明:
  将 RabbitMQ 和 RabbitMQ Cluster Operator 镜像归档上传到每台 K3s 节点的
  /var/lib/rancher/k3s/agent/images/。

  K3s 已经运行时，上传后需要重启对应节点的 k3s 服务才会立即导入。
  如需脚本逐台滚动重启，设置 RABBITMQ_RESTART_K3S_AFTER_IMAGE_UPLOAD=true。
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
ENV_RABBITMQ_IMAGE=${RABBITMQ_IMAGE:-}
ENV_RABBITMQ_OPERATOR_IMAGE=${RABBITMQ_OPERATOR_IMAGE:-}
ENV_RABBITMQ_IMAGE_TAR=${RABBITMQ_IMAGE_TAR:-}
ENV_RABBITMQ_OPERATOR_IMAGE_TAR=${RABBITMQ_OPERATOR_IMAGE_TAR:-}
ENV_RABBITMQ_NODE_SSH_HOSTS=${RABBITMQ_NODE_SSH_HOSTS:-}
ENV_RABBITMQ_NODE_NAMES=${RABBITMQ_NODE_NAMES:-}
ENV_SSH_USER=${SSH_USER:-}
ENV_SSH_PORT=${SSH_PORT:-}
ENV_SSH_OPTS=${SSH_OPTS:-}
ENV_RABBITMQ_K3S_IMAGES_DIR=${RABBITMQ_K3S_IMAGES_DIR:-}
ENV_RABBITMQ_RESTART_K3S_AFTER_IMAGE_UPLOAD=${RABBITMQ_RESTART_K3S_AFTER_IMAGE_UPLOAD:-}
ENV_RABBITMQ_RESET_K3S_IMAGE_CACHE=${RABBITMQ_RESET_K3S_IMAGE_CACHE:-}

# shellcheck disable=SC1090
source "$CONFIG"

KUBECONFIG=${ENV_KUBECONFIG:-${KUBECONFIG:-}}
RABBITMQ_IMAGE=${ENV_RABBITMQ_IMAGE:-${RABBITMQ_IMAGE:-rabbitmq:4.3.1-management}}
RABBITMQ_OPERATOR_IMAGE=${ENV_RABBITMQ_OPERATOR_IMAGE:-${RABBITMQ_OPERATOR_IMAGE:-ghcr.io/rabbitmq/cluster-operator:2.21.0}}
RABBITMQ_IMAGE_TAR=${ENV_RABBITMQ_IMAGE_TAR:-${RABBITMQ_IMAGE_TAR:-}}
RABBITMQ_OPERATOR_IMAGE_TAR=${ENV_RABBITMQ_OPERATOR_IMAGE_TAR:-${RABBITMQ_OPERATOR_IMAGE_TAR:-}}
RABBITMQ_NODE_SSH_HOSTS=${ENV_RABBITMQ_NODE_SSH_HOSTS:-${RABBITMQ_NODE_SSH_HOSTS:-}}
RABBITMQ_NODE_NAMES=${ENV_RABBITMQ_NODE_NAMES:-${RABBITMQ_NODE_NAMES:-}}
SSH_USER=${ENV_SSH_USER:-${SSH_USER:-root}}
SSH_PORT=${ENV_SSH_PORT:-${SSH_PORT:-22}}
SSH_OPTS=${ENV_SSH_OPTS:-${SSH_OPTS:-"-o StrictHostKeyChecking=accept-new"}}
RABBITMQ_K3S_IMAGES_DIR=${ENV_RABBITMQ_K3S_IMAGES_DIR:-${RABBITMQ_K3S_IMAGES_DIR:-/var/lib/rancher/k3s/agent/images}}
RABBITMQ_RESTART_K3S_AFTER_IMAGE_UPLOAD=${ENV_RABBITMQ_RESTART_K3S_AFTER_IMAGE_UPLOAD:-${RABBITMQ_RESTART_K3S_AFTER_IMAGE_UPLOAD:-false}}
RABBITMQ_RESET_K3S_IMAGE_CACHE=${ENV_RABBITMQ_RESET_K3S_IMAGE_CACHE:-${RABBITMQ_RESET_K3S_IMAGE_CACHE:-false}}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少本地命令: $1" >&2
    exit 1
  }
}

ssh_target() {
  local host=$1
  printf '%s@%s' "$SSH_USER" "$host"
}

run_ssh() {
  local host=$1
  shift
  ssh -p "$SSH_PORT" $SSH_OPTS "$(ssh_target "$host")" "$@"
}

copy_to() {
  local src=$1
  local host=$2
  local dest=$3
  scp -P "$SSH_PORT" $SSH_OPTS "$src" "$(ssh_target "$host"):$dest"
}

wait_node_ready() {
  local node=$1
  if [[ -z "$KUBECONFIG" ]]; then
    return
  fi

  export KUBECONFIG
  echo "等待节点 Ready: $node"
  kubectl wait --for=condition=Ready "node/$node" --timeout=180s
}

require_cmd ssh
require_cmd scp

if [[ -n "$KUBECONFIG" ]]; then
  require_cmd kubectl
fi

if [[ -z "$RABBITMQ_IMAGE_TAR" || ! -f "$RABBITMQ_IMAGE_TAR" ]]; then
  echo "找不到 RABBITMQ_IMAGE_TAR: $RABBITMQ_IMAGE_TAR" >&2
  exit 1
fi

if [[ -z "$RABBITMQ_OPERATOR_IMAGE_TAR" || ! -f "$RABBITMQ_OPERATOR_IMAGE_TAR" ]]; then
  echo "找不到 RABBITMQ_OPERATOR_IMAGE_TAR: $RABBITMQ_OPERATOR_IMAGE_TAR" >&2
  exit 1
fi

if [[ -z "$RABBITMQ_NODE_SSH_HOSTS" ]]; then
  echo "缺少 RABBITMQ_NODE_SSH_HOSTS，多个节点用英文逗号分隔。" >&2
  exit 1
fi

IFS=',' read -r -a node_hosts <<<"$RABBITMQ_NODE_SSH_HOSTS"
IFS=',' read -r -a node_names <<<"$RABBITMQ_NODE_NAMES"

if [[ -n "$RABBITMQ_NODE_NAMES" && "${#node_names[@]}" -ne "${#node_hosts[@]}" ]]; then
  echo "RABBITMQ_NODE_NAMES 数量必须与 RABBITMQ_NODE_SSH_HOSTS 一致。" >&2
  exit 1
fi

remote_rabbitmq_tar="$RABBITMQ_K3S_IMAGES_DIR/$(basename "$RABBITMQ_IMAGE_TAR")"
remote_operator_tar="$RABBITMQ_K3S_IMAGES_DIR/$(basename "$RABBITMQ_OPERATOR_IMAGE_TAR")"
remote_rabbitmq_tmp="$RABBITMQ_K3S_IMAGES_DIR/.uploading-$(basename "$RABBITMQ_IMAGE_TAR").tmp"
remote_operator_tmp="$RABBITMQ_K3S_IMAGES_DIR/.uploading-$(basename "$RABBITMQ_OPERATOR_IMAGE_TAR").tmp"

for i in "${!node_hosts[@]}"; do
  host=${node_hosts[$i]}
  node_name=${node_names[$i]:-}
  echo "上传 RabbitMQ 离线镜像到节点: $host"
  run_ssh "$host" "mkdir -p '$RABBITMQ_K3S_IMAGES_DIR'"
  copy_to "$RABBITMQ_IMAGE_TAR" "$host" "$remote_rabbitmq_tmp"
  copy_to "$RABBITMQ_OPERATOR_IMAGE_TAR" "$host" "$remote_operator_tmp"
  run_ssh "$host" "chmod 0600 '$remote_rabbitmq_tmp' '$remote_operator_tmp' && mv -f '$remote_rabbitmq_tmp' '$remote_rabbitmq_tar' && mv -f '$remote_operator_tmp' '$remote_operator_tar'"

  if [[ "$RABBITMQ_RESET_K3S_IMAGE_CACHE" == "true" ]]; then
    echo "重置 K3s 镜像导入缓存: $host"
    run_ssh "$host" "rm -f '$RABBITMQ_K3S_IMAGES_DIR/.cache.json'"
  fi

  if [[ "$RABBITMQ_RESTART_K3S_AFTER_IMAGE_UPLOAD" == "true" ]]; then
    echo "重启 K3s 触发镜像自动导入: $host"
    run_ssh "$host" "systemctl restart k3s"
    if [[ -n "$node_name" ]]; then
      wait_node_ready "$node_name"
    fi
  else
    echo "已上传。K3s 已运行时不会立即导入；下次 k3s 服务启动会从 images 目录自动导入。若需立即导入，请设置 RABBITMQ_RESTART_K3S_AFTER_IMAGE_UPLOAD=true。"
  fi

  echo "检查节点镜像: $host"
  run_ssh "$host" "k3s ctr images ls | grep -F '$RABBITMQ_IMAGE' || true"
  run_ssh "$host" "k3s ctr images ls | grep -F '$RABBITMQ_OPERATOR_IMAGE' || true"
done

echo "完成"
