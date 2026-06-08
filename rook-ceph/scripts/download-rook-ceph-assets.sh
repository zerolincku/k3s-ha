#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
用法:
  download-rook-ceph-assets.sh <config.env>

示例:
  ROOK_CEPH_IMAGE_PLATFORM=linux/arm64 \
  bash rook-ceph/scripts/download-rook-ceph-assets.sh rook-ceph/prod.env

说明:
  在有网络的机器上下载 Rook Ceph 离线资源：
  1. Rook 官方 manifest
  2. Rook Operator、CSI sidecar、Ceph 镜像归档
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

ENV_ROOK_CEPH_ARTIFACT_DIR=${ROOK_CEPH_ARTIFACT_DIR:-}
ENV_ROOK_CEPH_CRDS_MANIFEST=${ROOK_CEPH_CRDS_MANIFEST:-}
ENV_ROOK_CEPH_COMMON_MANIFEST=${ROOK_CEPH_COMMON_MANIFEST:-}
ENV_ROOK_CEPH_CSI_OPERATOR_MANIFEST=${ROOK_CEPH_CSI_OPERATOR_MANIFEST:-}
ENV_ROOK_CEPH_OPERATOR_MANIFEST=${ROOK_CEPH_OPERATOR_MANIFEST:-}
ENV_ROOK_CEPH_CRDS_URL=${ROOK_CEPH_CRDS_URL:-}
ENV_ROOK_CEPH_COMMON_URL=${ROOK_CEPH_COMMON_URL:-}
ENV_ROOK_CEPH_CSI_OPERATOR_URL=${ROOK_CEPH_CSI_OPERATOR_URL:-}
ENV_ROOK_CEPH_OPERATOR_URL=${ROOK_CEPH_OPERATOR_URL:-}
ENV_ROOK_CEPH_IMAGE=${ROOK_CEPH_IMAGE:-}
ENV_ROOK_CEPH_CEPH_IMAGE=${ROOK_CEPH_CEPH_IMAGE:-}
ENV_ROOK_CEPH_IMAGE_PLATFORM=${ROOK_CEPH_IMAGE_PLATFORM:-}
ENV_ROOK_CEPH_EXTRA_IMAGES=${ROOK_CEPH_EXTRA_IMAGES:-}
ENV_ROOK_CEPH_IMAGE_DOWNLOAD_TOOL=${ROOK_CEPH_IMAGE_DOWNLOAD_TOOL:-}
ENV_CRANE_BIN=${CRANE_BIN:-}
ENV_ROOK_CEPH_DOCKER_PULL_RETRIES=${ROOK_CEPH_DOCKER_PULL_RETRIES:-}
ENV_ROOK_CEPH_DOCKER_PULL_RETRY_DELAY=${ROOK_CEPH_DOCKER_PULL_RETRY_DELAY:-}
ENV_ROOK_CEPH_CURL_INSECURE=${ROOK_CEPH_CURL_INSECURE:-}

# shellcheck disable=SC1090
source "$CONFIG"

ROOK_CEPH_ARTIFACT_DIR=${ENV_ROOK_CEPH_ARTIFACT_DIR:-${ROOK_CEPH_ARTIFACT_DIR:-./rook-ceph/artifacts}}
ROOK_CEPH_CRDS_MANIFEST=${ENV_ROOK_CEPH_CRDS_MANIFEST:-${ROOK_CEPH_CRDS_MANIFEST:-}}
ROOK_CEPH_COMMON_MANIFEST=${ENV_ROOK_CEPH_COMMON_MANIFEST:-${ROOK_CEPH_COMMON_MANIFEST:-}}
ROOK_CEPH_CSI_OPERATOR_MANIFEST=${ENV_ROOK_CEPH_CSI_OPERATOR_MANIFEST:-${ROOK_CEPH_CSI_OPERATOR_MANIFEST:-}}
ROOK_CEPH_OPERATOR_MANIFEST=${ENV_ROOK_CEPH_OPERATOR_MANIFEST:-${ROOK_CEPH_OPERATOR_MANIFEST:-}}
ROOK_CEPH_CRDS_URL=${ENV_ROOK_CEPH_CRDS_URL:-${ROOK_CEPH_CRDS_URL:-https://raw.githubusercontent.com/rook/rook/v1.19.6/deploy/examples/crds.yaml}}
ROOK_CEPH_COMMON_URL=${ENV_ROOK_CEPH_COMMON_URL:-${ROOK_CEPH_COMMON_URL:-https://raw.githubusercontent.com/rook/rook/v1.19.6/deploy/examples/common.yaml}}
ROOK_CEPH_CSI_OPERATOR_URL=${ENV_ROOK_CEPH_CSI_OPERATOR_URL:-${ROOK_CEPH_CSI_OPERATOR_URL:-https://raw.githubusercontent.com/rook/rook/v1.19.6/deploy/examples/csi-operator.yaml}}
ROOK_CEPH_OPERATOR_URL=${ENV_ROOK_CEPH_OPERATOR_URL:-${ROOK_CEPH_OPERATOR_URL:-https://raw.githubusercontent.com/rook/rook/v1.19.6/deploy/examples/operator.yaml}}
ROOK_CEPH_IMAGE=${ENV_ROOK_CEPH_IMAGE:-${ROOK_CEPH_IMAGE:-quay.io/rook/ceph:v1.19.6}}
ROOK_CEPH_CEPH_IMAGE=${ENV_ROOK_CEPH_CEPH_IMAGE:-${ROOK_CEPH_CEPH_IMAGE:-quay.io/ceph/ceph:v19.2.3}}
ROOK_CEPH_IMAGE_PLATFORM=${ENV_ROOK_CEPH_IMAGE_PLATFORM:-${ROOK_CEPH_IMAGE_PLATFORM:-linux/arm64}}
ROOK_CEPH_EXTRA_IMAGES=${ENV_ROOK_CEPH_EXTRA_IMAGES:-${ROOK_CEPH_EXTRA_IMAGES:-}}
ROOK_CEPH_IMAGE_DOWNLOAD_TOOL=${ENV_ROOK_CEPH_IMAGE_DOWNLOAD_TOOL:-${ROOK_CEPH_IMAGE_DOWNLOAD_TOOL:-docker}}
CRANE_BIN=${ENV_CRANE_BIN:-${CRANE_BIN:-crane}}
ROOK_CEPH_DOCKER_PULL_RETRIES=${ENV_ROOK_CEPH_DOCKER_PULL_RETRIES:-${ROOK_CEPH_DOCKER_PULL_RETRIES:-5}}
ROOK_CEPH_DOCKER_PULL_RETRY_DELAY=${ENV_ROOK_CEPH_DOCKER_PULL_RETRY_DELAY:-${ROOK_CEPH_DOCKER_PULL_RETRY_DELAY:-10}}
ROOK_CEPH_CURL_INSECURE=${ENV_ROOK_CEPH_CURL_INSECURE:-${ROOK_CEPH_CURL_INSECURE:-false}}

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
  local curl_args=(--http1.1 -fL --retry 5 --retry-delay 3 --retry-all-errors -o "$output" "$url")

  if [[ "$ROOK_CEPH_CURL_INSECURE" == "true" ]]; then
    curl_args=(-k "${curl_args[@]}")
    echo "下载文件时跳过 TLS 证书校验，仅建议在受信代理环境临时使用。"
  fi

  echo "下载文件: $url"
  curl "${curl_args[@]}"
}

pull_image() {
  local image=$1
  local platform=$2
  local attempts=$ROOK_CEPH_DOCKER_PULL_RETRIES
  local delay=$ROOK_CEPH_DOCKER_PULL_RETRY_DELAY

  for ((i = 1; i <= attempts; i++)); do
    echo "拉取镜像，第 ${i}/${attempts} 次: ${image}，平台: $platform"
    if docker pull --platform "$platform" "$image"; then
      return
    fi

    if ((i < attempts)); then
      echo "镜像拉取失败，${delay} 秒后重试: $image" >&2
      sleep "$delay"
    fi
  done

  echo "镜像拉取失败，已达到最大重试次数: $image" >&2
  exit 1
}

save_image_archive() {
  local image=$1
  local platform=$2
  local output=$3

  case "$ROOK_CEPH_IMAGE_DOWNLOAD_TOOL" in
    docker)
      require_cmd docker
      pull_image "$image" "$platform"
      echo "导出镜像归档: $output"
      docker save "$image" -o "$output"
      ;;
    crane)
      require_cmd "$CRANE_BIN"
      echo "使用 crane 下载并导出镜像归档: ${image}，平台: $platform"
      "$CRANE_BIN" pull --platform="$platform" --format=legacy "$image" "$output"
      ;;
    *)
      echo "不支持的 ROOK_CEPH_IMAGE_DOWNLOAD_TOOL: $ROOK_CEPH_IMAGE_DOWNLOAD_TOOL，仅支持 docker 或 crane。" >&2
      exit 1
      ;;
  esac
}

extract_manifest_images() {
  grep -hE 'image:|value:|IMAGE:' "$@" \
    | sed -nE 's/.*[" ](([A-Za-z0-9.-]+(:[0-9]+)?\/)?[A-Za-z0-9._-]+(\/[A-Za-z0-9._-]+)+(:[^" ]+|@sha256:[a-f0-9]+)).*/\1/p' \
    | grep -E '/|:' \
    | grep -v '^http' \
    | sort -u
}

require_cmd curl
require_cmd mkdir
require_cmd sed
require_cmd grep
require_cmd sort

manifest_dir="$ROOK_CEPH_ARTIFACT_DIR/manifests"
image_dir="$ROOK_CEPH_ARTIFACT_DIR/images"
mkdir -p "$manifest_dir" "$image_dir"

ROOK_CEPH_CRDS_MANIFEST=${ROOK_CEPH_CRDS_MANIFEST:-$manifest_dir/crds.yaml}
ROOK_CEPH_COMMON_MANIFEST=${ROOK_CEPH_COMMON_MANIFEST:-$manifest_dir/common.yaml}
ROOK_CEPH_CSI_OPERATOR_MANIFEST=${ROOK_CEPH_CSI_OPERATOR_MANIFEST:-$manifest_dir/csi-operator.yaml}
ROOK_CEPH_OPERATOR_MANIFEST=${ROOK_CEPH_OPERATOR_MANIFEST:-$manifest_dir/operator.yaml}

download_file "$ROOK_CEPH_CRDS_URL" "$ROOK_CEPH_CRDS_MANIFEST"
download_file "$ROOK_CEPH_COMMON_URL" "$ROOK_CEPH_COMMON_MANIFEST"
download_file "$ROOK_CEPH_CSI_OPERATOR_URL" "$ROOK_CEPH_CSI_OPERATOR_MANIFEST"
download_file "$ROOK_CEPH_OPERATOR_URL" "$ROOK_CEPH_OPERATOR_MANIFEST"

images_tmp=$(mktemp "${TMPDIR:-/tmp}/rook-ceph-images.XXXXXX")
trap 'rm -f "$images_tmp"' EXIT

{
  printf '%s\n' "$ROOK_CEPH_IMAGE"
  printf '%s\n' "$ROOK_CEPH_CEPH_IMAGE"
  extract_manifest_images "$ROOK_CEPH_CSI_OPERATOR_MANIFEST" "$ROOK_CEPH_OPERATOR_MANIFEST" || true
  if [[ -n "$ROOK_CEPH_EXTRA_IMAGES" ]]; then
    IFS=',' read -r -a extra_images <<<"$ROOK_CEPH_EXTRA_IMAGES"
    for image in "${extra_images[@]}"; do
      [[ -n "$image" ]] && printf '%s\n' "$image"
    done
  fi
} | grep -vE '(^|/)rook/ceph:' | sort -u >"$images_tmp.without-rook"

{
  printf '%s\n' "$ROOK_CEPH_IMAGE"
  cat "$images_tmp.without-rook"
} | sort -u >"$images_tmp"
rm -f "$images_tmp.without-rook"

echo "需要下载的镜像:"
sed 's/^/  /' "$images_tmp"

while IFS= read -r image; do
  [[ -z "$image" ]] && continue
  save_image_archive "$image" "$ROOK_CEPH_IMAGE_PLATFORM" "$image_dir/$(safe_name "$image").tar"
done <"$images_tmp"

echo "离线资源大小:"
ls -lh "$manifest_dir"/*.yaml "$image_dir"/*.tar

cat <<EOF

部署配置示例:
  ROOK_CEPH_CRDS_MANIFEST=$ROOK_CEPH_CRDS_MANIFEST
  ROOK_CEPH_COMMON_MANIFEST=$ROOK_CEPH_COMMON_MANIFEST
  ROOK_CEPH_CSI_OPERATOR_MANIFEST=$ROOK_CEPH_CSI_OPERATOR_MANIFEST
  ROOK_CEPH_OPERATOR_MANIFEST=$ROOK_CEPH_OPERATOR_MANIFEST
  ROOK_CEPH_EXTRA_IMAGE_TARS=$(find "$image_dir" -maxdepth 1 -type f -name '*.tar' | sort | paste -sd, -)
EOF
