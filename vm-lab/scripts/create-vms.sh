#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

need_cmd qemu-img
need_cmd cloud-localds
need_cmd virt-install
need_cmd virsh

if [[ ! -f "$BASE_IMAGE" ]]; then
  "$SCRIPT_DIR/prepare-image.sh"
fi

SSH_KEY=$(ssh_public_key)
ensure_libvirt_network

package_yaml=""
for pkg in $CLOUD_INIT_PACKAGES; do
  package_yaml+="  - $pkg"$'\n'
done

for index in $(seq 1 "$VM_COUNT"); do
  name=$(vm_name "$index")
  os_disk=$(vm_os_disk "$name")
  ceph_disk=$(vm_ceph_disk "$name")
  seed_iso=$(vm_seed_iso "$name")
  cloud_dir="$LAB_DIR/cloud-init/$name"

  if domain_exists "$name"; then
    echo "VM 已存在，跳过创建: $name"
    continue
  fi

  mkdir -p "$cloud_dir"

  if [[ ! -f "$os_disk" ]]; then
    qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$os_disk" "$OS_DISK_SIZE" >/dev/null
  fi

  if [[ ! -f "$ceph_disk" ]]; then
    qemu-img create -f qcow2 "$ceph_disk" "$CEPH_DISK_SIZE" >/dev/null
  fi

  cat >"$cloud_dir/meta-data" <<EOF
instance-id: $name
local-hostname: $name
EOF

  cat >"$cloud_dir/user-data" <<EOF
#cloud-config
hostname: $name
manage_etc_hosts: true
disable_root: false
ssh_pwauth: false
package_update: $CLOUD_INIT_PACKAGE_UPDATE
packages:
$package_yaml
users:
  - default
  - name: root
    lock_passwd: true
    ssh_authorized_keys:
      - $SSH_KEY
ssh_authorized_keys:
  - $SSH_KEY
write_files:
  - path: /etc/ssh/sshd_config.d/99-vm-lab-root.conf
    permissions: "0644"
    content: |
      PermitRootLogin prohibit-password
  - path: /etc/sysctl.d/99-kubernetes.conf
    permissions: "0644"
    content: |
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward = 1
runcmd:
  - swapoff -a
  - sed -ri '/[[:space:]]swap[[:space:]]/s/^/#/' /etc/fstab
  - modprobe overlay || true
  - modprobe br_netfilter || true
  - sysctl --system
  - systemctl restart ssh || systemctl restart sshd || true
  - systemctl enable --now qemu-guest-agent || true
  - systemctl enable --now iscsid || true
EOF

  cloud-localds "$seed_iso" "$cloud_dir/user-data" "$cloud_dir/meta-data"
  grant_libvirt_storage_access "$BASE_IMAGE" "$os_disk" "$ceph_disk" "$seed_iso"

  echo "创建 VM: $name"
  sudo_run virt-install \
    --connect qemu:///system \
    --name "$name" \
    --memory "$VM_MEMORY_MB" \
    --vcpus "$VM_CPUS" \
    --cpu host-passthrough \
    --os-variant "$OS_VARIANT" \
    --import \
    --disk "path=$os_disk,format=qcow2,bus=virtio" \
    --disk "path=$ceph_disk,format=qcow2,bus=virtio" \
    --disk "path=$seed_iso,device=cdrom" \
    --network "network=$LIBVIRT_NETWORK,model=virtio" \
    --graphics none \
    --console pty,target_type=serial \
    --noautoconsole
done

"$SCRIPT_DIR/list-vms.sh"
