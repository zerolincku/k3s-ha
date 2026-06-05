#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  download-k3s-assets.sh <config.env>

可选环境变量:
  K3S_VERSION=v1.35.5+k3s1
  K3S_ARCH=amd64|arm64|all
  ARTIFACT_DIR=./k3s/artifacts

说明:
  下载 K3s binary、install.sh 和 checksum 文件。
  K3s 系统镜像归档请使用 download-k3s-images.sh 下载。
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
    echo "resume $url" >&2
    curl --http1.1 -fL -C - --retry 5 --retry-delay 3 --retry-all-errors -o "$output" "$url" || {
      local rc=$?
      if [[ "$rc" -eq 22 || "$rc" -eq 33 ]]; then
        echo "resume skipped, keeping existing file: $output" >&2
      else
        return "$rc"
      fi
    }
  else
    echo "download $url" >&2
    curl --http1.1 -fL --retry 5 --retry-delay 3 --retry-all-errors -o "$output" "$url"
  fi
}

verify_asset() {
  local file=$1
  local checksum_file=$2
  local release_name=$3
  local expected actual

  expected=$(awk -v f="$release_name" '$2 == f || $2 == "./" f {print $1; exit}' "$checksum_file")
  if [[ -z "$expected" ]]; then
    echo "checksum entry not found for $release_name in $checksum_file" >&2
    exit 1
  fi

  actual=$(sha256_file "$file")
  if [[ "$actual" != "$expected" ]]; then
    echo "checksum mismatch for $release_name: expected=$expected actual=$actual" >&2
    exit 1
  fi
  echo "checksum ok: $release_name"
}

download_install_script() {
  local out_dir=$1
  local install_script="$out_dir/install.sh"

  download "https://get.k3s.io" "$install_script"
  chmod +x "$install_script"
  echo "$install_script"
}

download_arch() {
  local arch=$1
  local release_binary out_dir binary checksum_file version_escaped arch_label install_script

  case "$arch" in
    amd64)
      release_binary=k3s
      ;;
    arm64)
      release_binary=k3s-arm64
      ;;
    *)
      echo "unsupported K3S_ARCH: $arch" >&2
      exit 1
      ;;
  esac

  arch_label=$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')
  version_escaped=${K3S_VERSION/+/%2B}
  out_dir="$ARTIFACT_DIR/assets/${K3S_VERSION}/${arch}"
  binary="$out_dir/$release_binary"
  checksum_file="$out_dir/sha256sum-${arch}.txt"

  mkdir -p "$out_dir"

  download "https://github.com/k3s-io/k3s/releases/download/${version_escaped}/${release_binary}" "$binary"
  download "https://github.com/k3s-io/k3s/releases/download/${version_escaped}/sha256sum-${arch}.txt" "$checksum_file"
  install_script=$(download_install_script "$out_dir")

  chmod +x "$binary"
  verify_asset "$binary" "$checksum_file" "$release_binary"

  cat <<EOF

K3s binary:
  $binary
install.sh:
  $install_script
checksum:
  $checksum_file
部署配置示例:
  K3S_BINARY_${arch_label}=$binary
  K3S_INSTALL_SCRIPT=$install_script
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
