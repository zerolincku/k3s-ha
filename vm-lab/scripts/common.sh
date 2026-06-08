#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LAB_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
CONFIG_FILE=${CONFIG_FILE:-"$LAB_DIR/lab.env"}

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

VM_PREFIX=${VM_PREFIX:-k3s}
VM_COUNT=${VM_COUNT:-3}
VM_CPUS=${VM_CPUS:-2}
VM_MEMORY_MB=${VM_MEMORY_MB:-4096}
OS_DISK_SIZE=${OS_DISK_SIZE:-30G}
CEPH_DISK_SIZE=${CEPH_DISK_SIZE:-30G}
LIBVIRT_NETWORK=${LIBVIRT_NETWORK:-default}

IMAGE_URL=${IMAGE_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img}
OS_VARIANT=${OS_VARIANT:-ubuntu24.04}
BASE_IMAGE=${BASE_IMAGE:-"$LAB_DIR/images/$(basename "$IMAGE_URL")"}

CLOUD_INIT_PACKAGE_UPDATE=${CLOUD_INIT_PACKAGE_UPDATE:-true}
CLOUD_INIT_PACKAGES=${CLOUD_INIT_PACKAGES:-"qemu-guest-agent curl ca-certificates socat conntrack ipset iptables nfs-common open-iscsi lvm2 cryptsetup sg3-utils"}
TLS_SAN_VALUES_EXTRA=${TLS_SAN_VALUES_EXTRA:-}

mkdir -p "$LAB_DIR/images" "$LAB_DIR/disks" "$LAB_DIR/seed" "$LAB_DIR/cloud-init" "$LAB_DIR/generated"

need_cmd() {
  local cmd=$1
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "缺少命令: $cmd" >&2
    exit 1
  }
}

sudo_refresh() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    if [[ -n "${SUDO_ASKPASS:-}" ]]; then
      sudo -A -v
    else
      sudo -v
    fi
  fi
}

sudo_run() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  elif [[ -n "${SUDO_ASKPASS:-}" ]]; then
    sudo -A "$@"
  else
    sudo "$@"
  fi
}

vm_name() {
  local index=$1
  printf '%s-%s' "$VM_PREFIX" "$index"
}

vm_os_disk() {
  local name=$1
  printf '%s/disks/%s-os.qcow2' "$LAB_DIR" "$name"
}

vm_ceph_disk() {
  local name=$1
  printf '%s/disks/%s-ceph.qcow2' "$LAB_DIR" "$name"
}

vm_seed_iso() {
  local name=$1
  printf '%s/seed/%s-seed.iso' "$LAB_DIR" "$name"
}

ssh_public_key() {
  if [[ -n "${SSH_PUBLIC_KEY:-}" ]]; then
    printf '%s\n' "$SSH_PUBLIC_KEY"
    return
  fi

  local key_file=${SSH_PUBLIC_KEY_FILE:-}
  if [[ -n "$key_file" ]]; then
    key_file=${key_file/#\~/$HOME}
    if [[ -f "$key_file" ]]; then
      cat "$key_file"
      return
    fi
  fi

  for key_file in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
    if [[ -f "$key_file" ]]; then
      cat "$key_file"
      return
    fi
  done

  echo "找不到 SSH 公钥。请先 ssh-keygen，或在 vm-lab/lab.env 设置 SSH_PUBLIC_KEY_FILE。" >&2
  exit 1
}

domain_exists() {
  local name=$1
  sudo_run virsh dominfo "$name" >/dev/null 2>&1
}

domain_running() {
  local name=$1
  [[ "$(sudo_run virsh domstate "$name" 2>/dev/null || true)" == "running" ]]
}

network_running() {
  local name=$1
  sudo_run virsh net-list --all | awk -v name="$name" '
    NR > 2 && $1 == name {
      found = 1
      active = ($2 == "active")
    }
    END {
      exit(found && active ? 0 : 1)
    }
  '
}

ensure_libvirt_network() {
  sudo_refresh

  if command -v systemctl >/dev/null 2>&1; then
    sudo_run systemctl enable --now libvirtd >/dev/null 2>&1 || true
    sudo_run systemctl enable --now virtqemud >/dev/null 2>&1 || true
  fi

  if ! sudo_run virsh net-info "$LIBVIRT_NETWORK" >/dev/null 2>&1; then
    if [[ "$LIBVIRT_NETWORK" == "default" && -f /usr/share/libvirt/networks/default.xml ]]; then
      sudo_run virsh net-define /usr/share/libvirt/networks/default.xml >/dev/null
    else
      echo "libvirt network 不存在: $LIBVIRT_NETWORK" >&2
      exit 1
    fi
  fi

  if ! network_running "$LIBVIRT_NETWORK"; then
    if ! sudo_run virsh net-start "$LIBVIRT_NETWORK" >/dev/null; then
      if ! network_running "$LIBVIRT_NETWORK"; then
        echo "无法启动 libvirt network: $LIBVIRT_NETWORK" >&2
        exit 1
      fi
    fi
  fi
  sudo_run virsh net-autostart "$LIBVIRT_NETWORK" >/dev/null 2>&1 || true
}

grant_libvirt_storage_access() {
  local file
  local path=$LAB_DIR

  command -v setfacl >/dev/null 2>&1 || {
    echo "缺少 setfacl，请先安装 acl 包。" >&2
    exit 1
  }

  getent passwd libvirt-qemu >/dev/null || return 0

  while [[ "$path" != "/" ]]; do
    sudo_run setfacl -m u:libvirt-qemu:x "$path"
    path=$(dirname "$path")
  done

  sudo_run setfacl -m u:libvirt-qemu:rx "$LAB_DIR" "$LAB_DIR/disks" "$LAB_DIR/seed" "$LAB_DIR/images"

  for file in "$@"; do
    if [[ -e "$file" ]]; then
      sudo_run setfacl -m u:libvirt-qemu:rw "$file"
    fi
  done
}

vm_ip() {
  local name=$1
  local ip=

  ip=$(sudo_run virsh domifaddr "$name" --source agent 2>/dev/null | awk '
    /ipv4/ {
      split($4, a, "/")
      if (a[1] !~ /^127\./ && a[1] !~ /^169\.254\./) {
        print a[1]
        exit
      }
    }
  ' || true)
  if [[ -n "$ip" ]]; then
    printf '%s\n' "$ip"
    return
  fi

  ip=$(sudo_run virsh domifaddr "$name" --source lease 2>/dev/null | awk '
    /ipv4/ {
      split($4, a, "/")
      if (a[1] !~ /^127\./ && a[1] !~ /^169\.254\./) {
        print a[1]
        exit
      }
    }
  ' || true)
  if [[ -n "$ip" ]]; then
    printf '%s\n' "$ip"
    return
  fi

  sudo_run virsh net-dhcp-leases "$LIBVIRT_NETWORK" 2>/dev/null |
    awk -v name="$name" '$0 ~ name && /ipv4/ { split($5, a, "/"); print a[1]; exit }'
}

wait_for_vm_ip() {
  local name=$1
  local timeout=${2:-180}
  local start now ip
  start=$(date +%s)

  while true; do
    ip=$(vm_ip "$name" || true)
    if [[ -n "$ip" ]]; then
      printf '%s\n' "$ip"
      return
    fi

    now=$(date +%s)
    if (( now - start >= timeout )); then
      echo "等待 $name 获取 IP 超时" >&2
      return 1
    fi
    sleep 3
  done
}
