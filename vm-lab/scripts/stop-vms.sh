#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

need_cmd virsh

FORCE=${FORCE:-false}
TIMEOUT=${TIMEOUT:-90}

for index in $(seq 1 "$VM_COUNT"); do
  name=$(vm_name "$index")
  if ! domain_exists "$name"; then
    echo "VM 不存在，跳过: $name"
    continue
  fi
  if ! domain_running "$name"; then
    echo "VM 未运行: $name"
    continue
  fi

  echo "关闭 VM: $name"
  sudo_run virsh shutdown "$name" >/dev/null || true

  start=$(date +%s)
  while domain_running "$name"; do
    now=$(date +%s)
    if (( now - start >= TIMEOUT )); then
      if [[ "$FORCE" == "true" ]]; then
        echo "强制关闭 VM: $name"
        sudo_run virsh destroy "$name" >/dev/null
      else
        echo "关闭超时: $name。需要强制关闭时设置 FORCE=true。" >&2
      fi
      break
    fi
    sleep 3
  done
done
