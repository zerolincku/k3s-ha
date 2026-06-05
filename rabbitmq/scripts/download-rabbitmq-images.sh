#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
用法:
  download-rabbitmq-images.sh <config.env>

示例:
  RABBITMQ_IMAGE_PLATFORM=linux/arm64 \
  bash rabbitmq/scripts/download-rabbitmq-images.sh rabbitmq/prod.env

说明:
  在有网络的机器上下载 RabbitMQ 离线资源：
  1. RabbitMQ Cluster Operator manifest
  2. RabbitMQ Cluster Operator 镜像归档
  3. RabbitMQ server 镜像归档
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

ENV_RABBITMQ_IMAGE=${RABBITMQ_IMAGE:-}
ENV_RABBITMQ_OPERATOR_VERSION=${RABBITMQ_OPERATOR_VERSION:-}
ENV_RABBITMQ_OPERATOR_IMAGE=${RABBITMQ_OPERATOR_IMAGE:-}
ENV_RABBITMQ_IMAGE_PLATFORM=${RABBITMQ_IMAGE_PLATFORM:-}
ENV_RABBITMQ_ARTIFACT_DIR=${RABBITMQ_ARTIFACT_DIR:-}
ENV_RABBITMQ_IMAGE_TAR=${RABBITMQ_IMAGE_TAR:-}
ENV_RABBITMQ_OPERATOR_IMAGE_TAR=${RABBITMQ_OPERATOR_IMAGE_TAR:-}
ENV_RABBITMQ_OPERATOR_MANIFEST=${RABBITMQ_OPERATOR_MANIFEST:-}
ENV_RABBITMQ_OPERATOR_MANIFEST_URL=${RABBITMQ_OPERATOR_MANIFEST_URL:-}

# shellcheck disable=SC1090
source "$CONFIG"

RABBITMQ_IMAGE=${ENV_RABBITMQ_IMAGE:-${RABBITMQ_IMAGE:-rabbitmq:4.3.1-management}}
RABBITMQ_OPERATOR_VERSION=${ENV_RABBITMQ_OPERATOR_VERSION:-${RABBITMQ_OPERATOR_VERSION:-v2.21.0}}
RABBITMQ_OPERATOR_IMAGE=${ENV_RABBITMQ_OPERATOR_IMAGE:-${RABBITMQ_OPERATOR_IMAGE:-rabbitmqoperator/cluster-operator:2.21.0}}
RABBITMQ_IMAGE_PLATFORM=${ENV_RABBITMQ_IMAGE_PLATFORM:-${RABBITMQ_IMAGE_PLATFORM:-linux/arm64}}
RABBITMQ_ARTIFACT_DIR=${ENV_RABBITMQ_ARTIFACT_DIR:-${RABBITMQ_ARTIFACT_DIR:-./rabbitmq/artifacts}}
RABBITMQ_IMAGE_TAR=${ENV_RABBITMQ_IMAGE_TAR:-${RABBITMQ_IMAGE_TAR:-}}
RABBITMQ_OPERATOR_IMAGE_TAR=${ENV_RABBITMQ_OPERATOR_IMAGE_TAR:-${RABBITMQ_OPERATOR_IMAGE_TAR:-}}
RABBITMQ_OPERATOR_MANIFEST=${ENV_RABBITMQ_OPERATOR_MANIFEST:-${RABBITMQ_OPERATOR_MANIFEST:-}}
RABBITMQ_OPERATOR_MANIFEST_URL=${ENV_RABBITMQ_OPERATOR_MANIFEST_URL:-${RABBITMQ_OPERATOR_MANIFEST_URL:-https://github.com/rabbitmq/cluster-operator/releases/download/${RABBITMQ_OPERATOR_VERSION}/cluster-operator.yml}}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少本地命令: $1" >&2
    exit 1
  }
}

safe_name() {
  printf '%s' "$1" | sed -e 's#[/:@]#-#g'
}

download_file() {
  local url=$1
  local output=$2
  echo "下载文件: $url"
  curl --http1.1 -fL --retry 5 --retry-delay 3 --retry-all-errors -o "$output" "$url"
}

require_cmd curl
require_cmd docker
require_cmd mkdir
require_cmd sed

if [[ -z "$RABBITMQ_IMAGE_TAR" ]]; then
  RABBITMQ_IMAGE_TAR="$RABBITMQ_ARTIFACT_DIR/images/$(safe_name "$RABBITMQ_IMAGE").tar"
fi

if [[ -z "$RABBITMQ_OPERATOR_IMAGE_TAR" ]]; then
  RABBITMQ_OPERATOR_IMAGE_TAR="$RABBITMQ_ARTIFACT_DIR/images/$(safe_name "$RABBITMQ_OPERATOR_IMAGE").tar"
fi

if [[ -z "$RABBITMQ_OPERATOR_MANIFEST" ]]; then
  RABBITMQ_OPERATOR_MANIFEST="$RABBITMQ_ARTIFACT_DIR/operator/cluster-operator-${RABBITMQ_OPERATOR_VERSION}.yml"
fi

mkdir -p "$(dirname "$RABBITMQ_IMAGE_TAR")"
mkdir -p "$(dirname "$RABBITMQ_OPERATOR_IMAGE_TAR")"
mkdir -p "$(dirname "$RABBITMQ_OPERATOR_MANIFEST")"

download_file "$RABBITMQ_OPERATOR_MANIFEST_URL" "$RABBITMQ_OPERATOR_MANIFEST"

echo "拉取 RabbitMQ server 镜像: ${RABBITMQ_IMAGE}，平台: $RABBITMQ_IMAGE_PLATFORM"
docker pull --platform "$RABBITMQ_IMAGE_PLATFORM" "$RABBITMQ_IMAGE"

echo "导出 RabbitMQ server 镜像归档: $RABBITMQ_IMAGE_TAR"
docker save "$RABBITMQ_IMAGE" -o "$RABBITMQ_IMAGE_TAR"

echo "拉取 RabbitMQ Cluster Operator 镜像: ${RABBITMQ_OPERATOR_IMAGE}，平台: $RABBITMQ_IMAGE_PLATFORM"
docker pull --platform "$RABBITMQ_IMAGE_PLATFORM" "$RABBITMQ_OPERATOR_IMAGE"

echo "导出 RabbitMQ Cluster Operator 镜像归档: $RABBITMQ_OPERATOR_IMAGE_TAR"
docker save "$RABBITMQ_OPERATOR_IMAGE" -o "$RABBITMQ_OPERATOR_IMAGE_TAR"

echo "离线资源大小:"
ls -lh "$RABBITMQ_OPERATOR_MANIFEST" "$RABBITMQ_IMAGE_TAR" "$RABBITMQ_OPERATOR_IMAGE_TAR"

cat <<EOF

部署配置示例:
  RABBITMQ_IMAGE=$RABBITMQ_IMAGE
  RABBITMQ_OPERATOR_IMAGE=$RABBITMQ_OPERATOR_IMAGE
  RABBITMQ_OPERATOR_MANIFEST=$RABBITMQ_OPERATOR_MANIFEST
  RABBITMQ_IMAGE_TAR=$RABBITMQ_IMAGE_TAR
  RABBITMQ_OPERATOR_IMAGE_TAR=$RABBITMQ_OPERATOR_IMAGE_TAR
EOF
