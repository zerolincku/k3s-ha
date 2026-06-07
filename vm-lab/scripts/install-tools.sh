#!/usr/bin/env bash
set -euo pipefail

TARGET_USER=${SUDO_USER:-$USER}

sudo_cmd() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    "$@"
  elif [[ -n "${SUDO_ASKPASS:-}" ]]; then
    sudo -A "$@"
  else
    sudo "$@"
  fi
}

sudo_cmd apt update
sudo_cmd apt install -y \
  qemu-system-x86 \
  qemu-utils \
  libvirt-daemon-system \
  virtinst \
  cloud-image-utils \
  acl \
  curl \
  openssh-client

sudo_cmd usermod -aG kvm,libvirt "$TARGET_USER"

cat <<EOF
工具安装完成。

如果这是第一次把 $TARGET_USER 加入 kvm/libvirt 组，请重新打开 shell 或执行:
  newgrp libvirt

当前 WSL2 环境也可以直接通过 sudo 运行 vm-lab 脚本。
EOF
