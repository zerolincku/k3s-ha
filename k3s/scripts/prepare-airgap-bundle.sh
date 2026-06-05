#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  prepare-airgap-bundle.sh <配置文件.env>

可选环境变量:
  K3S_VERSION=v1.34.8+k3s1
  K3S_ARCH=amd64|arm64|all
  ARTIFACT_DIR=./k3s/artifacts
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

K3S_ARCH=${ENV_K3S_ARCH:-${K3S_ARCH:-amd64}}
ARTIFACT_DIR=${ENV_ARTIFACT_DIR:-${ARTIFACT_DIR:-./k3s/artifacts}}
K3S_VERSION=${ENV_K3S_VERSION:-${K3S_VERSION:-}}

if [[ -z "$K3S_VERSION" ]]; then
  echo "K3S_VERSION is required for deterministic airgap bundles." >&2
  echo "Example: K3S_VERSION=v1.34.8+k3s1 $0 $INVENTORY" >&2
  exit 1
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "required command not found: $1" >&2
    exit 1
  }
}

require_cmd curl
require_cmd tar

OUT_DIR="$ARTIFACT_DIR/airgap"
VERSION_ESCAPED=${K3S_VERSION/+/%2B}

mkdir -p "$OUT_DIR"

download() {
  local url=$1
  local output=$2
  echo "download $url"
  curl -fL --retry 3 --retry-delay 3 -o "$output" "$url"
}

bundle_arch() {
  local arch=$1
  local binary_name image_tar work_dir bundle

  case "$arch" in
    amd64)
      binary_name=k3s
      ;;
    arm64)
      binary_name=k3s-arm64
      ;;
    *)
      echo "unsupported K3S_ARCH: $arch" >&2
      exit 1
      ;;
  esac

  image_tar="k3s-airgap-images-${arch}.tar.zst"
  work_dir="$OUT_DIR/work-${arch}"
  bundle="$OUT_DIR/k3s-airgap-bundle-${K3S_VERSION}-${arch}.tar.gz"

  rm -rf "$work_dir"
  mkdir -p "$work_dir"

  download "https://github.com/k3s-io/k3s/releases/download/${VERSION_ESCAPED}/${binary_name}" "$work_dir/k3s"
  download "https://github.com/k3s-io/k3s/releases/download/${VERSION_ESCAPED}/${image_tar}" "$work_dir/${image_tar}"
  download "https://github.com/k3s-io/k3s/releases/download/${VERSION_ESCAPED}/sha256sum-${arch}.txt" "$work_dir/sha256sum-${arch}.txt"
  download "https://get.k3s.io" "$work_dir/install.sh"

  chmod +x "$work_dir/k3s" "$work_dir/install.sh"

  cat > "$work_dir/metadata.env" <<EOF
K3S_VERSION=${K3S_VERSION}
K3S_ARCH=${arch}
K3S_BINARY=${binary_name}
IMAGE_TAR=${image_tar}
CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

  (
    cd "$work_dir"
    tar -czf "$bundle" .
  )

  echo "airgap bundle: $bundle"
}

case "$K3S_ARCH" in
  all)
    bundle_arch amd64
    bundle_arch arm64
    ;;
  amd64|arm64)
    bundle_arch "$K3S_ARCH"
    ;;
  *)
    echo "unsupported K3S_ARCH: $K3S_ARCH" >&2
    exit 1
    ;;
esac
