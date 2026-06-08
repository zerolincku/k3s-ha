#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

need_cmd virsh
ensure_libvirt_network

for index in $(seq 1 "$VM_COUNT"); do
  name=$(vm_name "$index")
  if ! domain_exists "$name"; then
    echo "VM 不存在，跳过: $name"
    continue
  fi
  if domain_running "$name"; then
    echo "VM 已运行: $name"
  else
    echo "启动 VM: $name"
    sudo_run virsh start "$name" >/dev/null
  fi
done

"$SCRIPT_DIR/list-vms.sh"
