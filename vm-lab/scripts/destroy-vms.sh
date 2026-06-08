#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

need_cmd virsh

CONFIRM=${CONFIRM:-}
if [[ "$CONFIRM" != "yes" ]]; then
  echo "这会删除 $VM_PREFIX-1..$VM_PREFIX-$VM_COUNT 及本地 qcow2/seed 文件。"
  echo "确认执行: CONFIRM=yes $0"
  exit 1
fi

for index in $(seq 1 "$VM_COUNT"); do
  name=$(vm_name "$index")
  if domain_exists "$name"; then
    if domain_running "$name"; then
      sudo_run virsh destroy "$name" >/dev/null
    fi
    sudo_run virsh undefine "$name" --nvram >/dev/null 2>&1 || sudo_run virsh undefine "$name" >/dev/null
  fi

  rm -f "$(vm_os_disk "$name")" "$(vm_ceph_disk "$name")" "$(vm_seed_iso "$name")"
  rm -rf "$LAB_DIR/cloud-init/$name"
done

rm -f "$LAB_DIR/generated/k3s-vm.env"
echo "已删除 VM lab。base image 保留在: $LAB_DIR/images"
