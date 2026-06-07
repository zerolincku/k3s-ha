#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

need_cmd virsh

printf '%-12s %-10s %-16s %s\n' "NAME" "STATE" "IP" "CEPH_DISK"
for index in $(seq 1 "$VM_COUNT"); do
  name=$(vm_name "$index")
  if domain_exists "$name"; then
    state=$(sudo_run virsh domstate "$name" 2>/dev/null || true)
    ip=$(vm_ip "$name" || true)
    printf '%-12s %-10s %-16s %s\n' "$name" "${state:-unknown}" "${ip:-pending}" "$(vm_ceph_disk "$name")"
  else
    printf '%-12s %-10s %-16s %s\n' "$name" "missing" "-" "$(vm_ceph_disk "$name")"
  fi
done
