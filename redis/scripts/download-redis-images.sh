#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
用法:
  download-redis-images.sh <config.env>

示例:
  REDIS_IMAGE=redis:7.2.4 \
  REDIS_IMAGE_PLATFORM=linux/arm64 \
  bash redis/scripts/download-redis-images.sh redis/prod.env
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

ENV_REDIS_IMAGE=${REDIS_IMAGE:-}
ENV_REDIS_IMAGE_PLATFORM=${REDIS_IMAGE_PLATFORM:-}
ENV_REDIS_ARTIFACT_DIR=${REDIS_ARTIFACT_DIR:-}
ENV_REDIS_IMAGE_TAR=${REDIS_IMAGE_TAR:-}

# shellcheck disable=SC1090
source "$CONFIG"

REDIS_IMAGE=${ENV_REDIS_IMAGE:-${REDIS_IMAGE:-redis:7.2.4}}
REDIS_IMAGE_PLATFORM=${ENV_REDIS_IMAGE_PLATFORM:-${REDIS_IMAGE_PLATFORM:-linux/arm64}}
REDIS_ARTIFACT_DIR=${ENV_REDIS_ARTIFACT_DIR:-${REDIS_ARTIFACT_DIR:-./redis/artifacts}}
REDIS_IMAGE_TAR=${ENV_REDIS_IMAGE_TAR:-${REDIS_IMAGE_TAR:-}}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少本地命令: $1" >&2
    exit 1
  }
}

safe_name() {
  printf '%s' "$1" | sed -e 's#[/:@]#-#g'
}

require_cmd docker
require_cmd mkdir
require_cmd sed

if [[ -z "$REDIS_IMAGE_TAR" ]]; then
  REDIS_IMAGE_TAR="$REDIS_ARTIFACT_DIR/images/$(safe_name "$REDIS_IMAGE").tar"
fi

mkdir -p "$(dirname "$REDIS_IMAGE_TAR")"

echo "拉取 Redis 镜像: ${REDIS_IMAGE}，平台: $REDIS_IMAGE_PLATFORM"
docker pull --platform "$REDIS_IMAGE_PLATFORM" "$REDIS_IMAGE"

echo "导出 Redis 镜像归档: $REDIS_IMAGE_TAR"
docker save "$REDIS_IMAGE" -o "$REDIS_IMAGE_TAR"

echo "镜像归档大小:"
ls -lh "$REDIS_IMAGE_TAR"

cat <<EOF

部署配置示例:
  REDIS_IMAGE=$REDIS_IMAGE
  REDIS_IMAGE_TAR=$REDIS_IMAGE_TAR
EOF
