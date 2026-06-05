#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
用法:
  download-k3s-images.sh <config.env>

可选环境变量:
  K3S_VERSION=v1.35.5+k3s1
  K3S_ARCH=amd64|arm64|all
  ARTIFACT_DIR=./k3s/artifacts

说明:
  下载 K3s 官方离线镜像归档和镜像清单。
  输出的 k3s-airgap-images-<arch>.tar.zst 可放入:
    /var/lib/rancher/k3s/agent/images/
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
  echo "必须设置 K3S_VERSION。" >&2
  exit 1
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少本地命令: $1" >&2
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
    echo "继续下载: $url" >&2
    curl --http1.1 -fL -C - --retry 5 --retry-delay 3 --retry-all-errors -o "$output" "$url" || {
      local rc=$?
      if [[ "$rc" -eq 22 || "$rc" -eq 33 ]]; then
        echo "无法继续下载，保留已有文件: $output" >&2
      else
        return "$rc"
      fi
    }
  else
    echo "下载: $url" >&2
    curl --http1.1 -fL --retry 5 --retry-delay 3 --retry-all-errors -o "$output" "$url"
  fi
}

verify_image_tar() {
  local arch=$1
  local image_tar=$2
  local checksum_file=$3
  local expected actual basename_tar

  basename_tar=$(basename "$image_tar")
  expected=$(awk -v f="$basename_tar" '$2 == f || $2 == "./" f {print $1; exit}' "$checksum_file")
  if [[ -z "$expected" ]]; then
    echo "校验文件中找不到条目: $basename_tar，校验文件: $checksum_file" >&2
    exit 1
  fi

  actual=$(sha256_file "$image_tar")
  if [[ "$actual" != "$expected" ]]; then
    echo "镜像归档校验失败: 架构=$arch，期望=$expected 实际=$actual" >&2
    exit 1
  fi
  echo "校验通过: $basename_tar"
}

download_arch() {
  local arch=$1
  local image_tar checksum_file images_file out_dir version_escaped arch_label

  case "$arch" in
    amd64|arm64)
      arch_label=$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')
      ;;
    *)
      echo "不支持的 K3S_ARCH: $arch" >&2
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
    echo "不支持的 K3S_ARCH: $K3S_ARCH" >&2
    exit 1
    ;;
esac
