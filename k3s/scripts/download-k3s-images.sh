#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  download-k3s-images.sh <config.env>

可选环境变量:
  K3S_VERSION=v1.35.5+k3s1
  K3S_ARCH=amd64|arm64|all
  ARTIFACT_DIR=./k3s/artifacts

说明:
  下载 K3s 官方 airgap 镜像归档和镜像清单。
  输出的 k3s-airgap-images-<arch>.tar.zst 可放入:
    /var/lib/rancher/k3s/agent/images/
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -ne 1 ]]; then
  usage
  exit 1
fi

INVENTORY=$1
if [[ ! -f "$INVENTORY" ]]; then
  echo "配置文件不存在: $INVENTORY" >&2
  exit 1
fi

ENV_K3S_VERSION=${K3S_VERSION:-}
ENV_K3S_ARCH=${K3S_ARCH:-}
ENV_ARTIFACT_DIR=${ARTIFACT_DIR:-}

# shellcheck disable=SC1090
source "$INVENTORY"

K3S_VERSION=${ENV_K3S_VERSION:-${K3S_VERSION:-}}
K3S_ARCH=${ENV_K3S_ARCH:-${K3S_ARCH:-amd64}}
ARTIFACT_DIR=${ENV_ARTIFACT_DIR:-${ARTIFACT_DIR:-./k3s/artifacts}}

if [[ -z "$K3S_VERSION" ]]; then
  echo "K3S_VERSION is required." >&2
  exit 1
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "required command not found: $1" >&2
    exit 1
  }
}

require_cmd curl

sha256_file() {
  local file=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

download() {
  local url=$1
  local output=$2
  if [[ -s "$output" ]]; then
    echo "exists $output"
    return
  fi
  echo "download $url"
  curl -fL --retry 3 --retry-delay 3 -o "$output" "$url"
}

verify_image_tar() {
  local arch=$1
  local image_tar=$2
  local checksum_file=$3
  local expected actual basename_tar

  basename_tar=$(basename "$image_tar")
  expected=$(awk -v f="$basename_tar" '$2 == f || $2 == "./" f {print $1; exit}' "$checksum_file")
  if [[ -z "$expected" ]]; then
    echo "checksum entry not found for $basename_tar in $checksum_file" >&2
    exit 1
  fi

  actual=$(sha256_file "$image_tar")
  if [[ "$actual" != "$expected" ]]; then
    echo "checksum mismatch for $arch image tar: expected=$expected actual=$actual" >&2
    exit 1
  fi
  echo "checksum ok: $basename_tar"
}

download_arch() {
  local arch=$1
  local image_tar checksum_file images_file out_dir version_escaped arch_label

  case "$arch" in
    amd64|arm64)
      arch_label=$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')
      ;;
    *)
      echo "unsupported K3S_ARCH: $arch" >&2
      exit 1
      ;;
  esac

  version_escaped=${K3S_VERSION/+/%2B}
  out_dir="$ARTIFACT_DIR/images/${K3S_VERSION}/${arch}"
  image_tar="$out_dir/k3s-airgap-images-${arch}.tar.zst"
  checksum_file="$out_dir/sha256sum-${arch}.txt"
  images_file="$out_dir/k3s-images.txt"

  mkdir -p "$out_dir"

  download "https://github.com/k3s-io/k3s/releases/download/${version_escaped}/k3s-airgap-images-${arch}.tar.zst" "$image_tar"
  download "https://github.com/k3s-io/k3s/releases/download/${version_escaped}/sha256sum-${arch}.txt" "$checksum_file"
  download "https://github.com/k3s-io/k3s/releases/download/${version_escaped}/k3s-images.txt" "$images_file"
  verify_image_tar "$arch" "$image_tar" "$checksum_file"

  cat <<EOF

镜像归档:
  $image_tar
镜像清单:
  $images_file
部署配置示例:
  K3S_IMAGE_TAR_${arch_label}=$image_tar
EOF
}

case "$K3S_ARCH" in
  all)
    download_arch amd64
    download_arch arm64
    ;;
  amd64|arm64)
    download_arch "$K3S_ARCH"
    ;;
  *)
    echo "unsupported K3S_ARCH: $K3S_ARCH" >&2
    exit 1
    ;;
esac
