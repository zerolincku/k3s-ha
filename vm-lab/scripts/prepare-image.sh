#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

need_cmd curl
need_cmd qemu-img

if [[ -f "$BASE_IMAGE" ]]; then
  echo "base image 已存在: $BASE_IMAGE"
else
  echo "下载 base image:"
  echo "  $IMAGE_URL"
  echo "  -> $BASE_IMAGE"
  curl -fL --retry 5 --retry-delay 3 -o "$BASE_IMAGE.tmp" "$IMAGE_URL"
  mv "$BASE_IMAGE.tmp" "$BASE_IMAGE"
fi

qemu-img info "$BASE_IMAGE"
