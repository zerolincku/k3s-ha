#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  deploy-k3s-ha.sh <配置文件.env>

在线部署:
  bash k3s/scripts/deploy-k3s-ha.sh k3s/prod.env

离线部署:
  K3S_AIRGAP=true AIRGAP_BUNDLE=/path/to/same-arch-bundle.tar.gz \
    bash k3s/scripts/deploy-k3s-ha.sh k3s/prod.env

混合架构离线部署:
  K3S_AIRGAP=true \
  AIRGAP_BUNDLE_AMD64=/path/to/amd64-bundle.tar.gz \
  AIRGAP_BUNDLE_ARM64=/path/to/arm64-bundle.tar.gz \
    bash k3s/scripts/deploy-k3s-ha.sh k3s/prod.env
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

# shellcheck disable=SC1090
source "$INVENTORY"

SSH_USER=${SSH_USER:-root}
SSH_PORT=${SSH_PORT:-22}
SSH_OPTS=${SSH_OPTS:-"-o StrictHostKeyChecking=accept-new"}
K3S_API_PORT=${K3S_API_PORT:-6443}
K3S_CHANNEL=${K3S_CHANNEL:-stable}
K3S_TOKEN=${K3S_TOKEN:-}
K3S_CLUSTER_CIDR=${K3S_CLUSTER_CIDR:-10.42.0.0/16}
K3S_SERVICE_CIDR=${K3S_SERVICE_CIDR:-10.43.0.0/16}
K3S_CLUSTER_DNS=${K3S_CLUSTER_DNS:-10.43.0.10}
CGROUP_MODE=${CGROUP_MODE:-auto}
K3S_CGROUP_DRIVER=${K3S_CGROUP_DRIVER:-auto}
K3S_DISABLE_COMPONENTS=${K3S_DISABLE_COMPONENTS:-traefik}
K3S_AIRGAP=${K3S_AIRGAP:-false}
AIRGAP_BUNDLE=${AIRGAP_BUNDLE:-}
AIRGAP_BUNDLE_AMD64=${AIRGAP_BUNDLE_AMD64:-}
AIRGAP_BUNDLE_ARM64=${AIRGAP_BUNDLE_ARM64:-}
K3S_ARCH=${K3S_ARCH:-amd64}
K3S_JOIN_ENDPOINT=${K3S_JOIN_ENDPOINT:-}
KUBECONFIG_SERVER=${KUBECONFIG_SERVER:-}
TLS_SAN_VALUES=${TLS_SAN_VALUES:-}
ARTIFACT_DIR=${ARTIFACT_DIR:-./k3s/artifacts}

MASTER_NAMES=("${MASTER1_NAME:?}" "${MASTER2_NAME:?}" "${MASTER3_NAME:?}")
MASTER_HOSTS=("${MASTER1_HOST:?}" "${MASTER2_HOST:?}" "${MASTER3_HOST:?}")
MASTER_ARCHES=("${MASTER1_ARCH:-auto}" "${MASTER2_ARCH:-auto}" "${MASTER3_ARCH:-auto}")
DETECTED_ARCHES=()
DETECTED_CGROUPS=()

K3S_JOIN_ENDPOINT=${K3S_JOIN_ENDPOINT:-https://${MASTER1_HOST}:${K3S_API_PORT}}
KUBECONFIG_SERVER=${KUBECONFIG_SERVER:-$K3S_JOIN_ENDPOINT}

if [[ "$K3S_TOKEN" == "change-me-use-openssl-rand-hex-32" || -z "$K3S_TOKEN" ]]; then
  echo "K3S_TOKEN must be changed before deployment." >&2
  echo "Example: openssl rand -hex 32" >&2
  exit 1
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "required command not found: $1" >&2
    exit 1
  }
}

require_cmd ssh
require_cmd scp
require_cmd sed
require_cmd mkdir

mkdir -p "$ARTIFACT_DIR"

ssh_target() {
  local host=$1
  printf '%s@%s' "$SSH_USER" "$host"
}

run_ssh() {
  local host=$1
  shift
  ssh -p "$SSH_PORT" $SSH_OPTS "$(ssh_target "$host")" "$@"
}

copy_to() {
  local src=$1
  local host=$2
  local dest=$3
  scp -P "$SSH_PORT" $SSH_OPTS "$src" "$(ssh_target "$host"):$dest"
}

normalize_arch() {
  case "$1" in
    auto)
      echo auto
      ;;
    amd64|x86_64)
      echo amd64
      ;;
    arm64|aarch64)
      echo arm64
      ;;
    *)
      echo "unsupported architecture: $1" >&2
      return 1
      ;;
  esac
}

detect_host_profile() {
  local host=$1
  run_ssh "$host" "bash -s" <<'REMOTE'
set -euo pipefail
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
if [[ "$(stat -fc %T /sys/fs/cgroup)" == "cgroup2fs" ]]; then
  cgroup=v2
else
  cgroup=v1
fi
printf '%s %s\n' "$arch" "$cgroup"
REMOTE
}

preflight_host_profiles() {
  local i host detected_arch detected_cgroup expected_arch
  case "$CGROUP_MODE" in
    auto|v1|v2) ;;
    *)
      echo "unsupported CGROUP_MODE: $CGROUP_MODE" >&2
      exit 1
      ;;
  esac
  case "$K3S_CGROUP_DRIVER" in
    auto|systemd|cgroupfs) ;;
    *)
      echo "unsupported K3S_CGROUP_DRIVER: $K3S_CGROUP_DRIVER" >&2
      exit 1
      ;;
  esac

  for i in "${!MASTER_HOSTS[@]}"; do
    host=${MASTER_HOSTS[$i]}
    local profile
    profile=$(detect_host_profile "$host")
    read -r detected_arch detected_cgroup <<<"$profile"
    expected_arch=$(normalize_arch "${MASTER_ARCHES[$i]}")
    if [[ "$expected_arch" != "auto" && "$expected_arch" != "$detected_arch" ]]; then
      echo "arch mismatch on $host: expected $expected_arch, detected $detected_arch" >&2
      exit 1
    fi
    if [[ "$CGROUP_MODE" != "auto" && "$CGROUP_MODE" != "$detected_cgroup" ]]; then
      echo "cgroup mismatch on $host: expected $CGROUP_MODE, detected $detected_cgroup" >&2
      exit 1
    fi
    DETECTED_ARCHES[$i]=$detected_arch
    DETECTED_CGROUPS[$i]=$detected_cgroup
    echo "host profile: ${MASTER_NAMES[$i]} $host arch=$detected_arch cgroup=$detected_cgroup"
  done
}

airgap_bundle_for_arch() {
  local arch=$1
  case "$arch" in
    amd64)
      echo "${AIRGAP_BUNDLE_AMD64:-${AIRGAP_BUNDLE:-}}"
      ;;
    arm64)
      echo "${AIRGAP_BUNDLE_ARM64:-${AIRGAP_BUNDLE:-}}"
      ;;
    *)
      echo "unsupported architecture for airgap bundle: $arch" >&2
      return 1
      ;;
  esac
}

check_connectivity() {
  for host in "${MASTER_HOSTS[@]}"; do
    echo "check ssh: $host"
    run_ssh "$host" "echo ok >/dev/null"
  done
}

install_os_packages() {
  local host=$1
  if [[ "$K3S_AIRGAP" == "true" ]]; then
    return
  fi

  run_ssh "$host" "bash -s" <<'REMOTE'
set -euo pipefail
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y curl ca-certificates iproute2 iptables socat conntrack
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y curl ca-certificates iproute iptables socat conntrack-tools
elif command -v yum >/dev/null 2>&1; then
  yum install -y curl ca-certificates iproute iptables socat conntrack-tools
else
  echo "unsupported package manager; install curl and k3s prerequisites manually" >&2
  exit 1
fi
REMOTE
}

configure_sysctl() {
  local host=$1
  run_ssh "$host" "bash -s" <<'REMOTE'
set -euo pipefail
cat >/etc/sysctl.d/99-k3s-ha.conf <<'EOF'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
modprobe br_netfilter || true
sysctl --system >/dev/null
swapoff -a || true
REMOTE
}

install_airgap_payload() {
  local host=$1
  local arch=$2
  local bundle
  bundle=$(airgap_bundle_for_arch "$arch")
  if [[ -z "$bundle" || ! -f "$bundle" ]]; then
    echo "airgap bundle for $arch not found: $bundle" >&2
    exit 1
  fi

  local remote_bundle="/tmp/$(basename "$bundle")"
  copy_to "$bundle" "$host" "$remote_bundle"
  run_ssh "$host" "REMOTE_BUNDLE='$remote_bundle' K3S_ARCH='$arch' bash -s" <<'REMOTE'
set -euo pipefail
rm -rf /opt/k3s-airgap
mkdir -p /opt/k3s-airgap /var/lib/rancher/k3s/agent/images /usr/local/bin
tar -xzf "$REMOTE_BUNDLE" -C /opt/k3s-airgap
install -m 0755 /opt/k3s-airgap/k3s /usr/local/bin/k3s
install -m 0755 /opt/k3s-airgap/install.sh /opt/k3s-airgap/install.sh
if [[ -f /opt/k3s-airgap/metadata.env ]]; then
  # shellcheck disable=SC1091
  source /opt/k3s-airgap/metadata.env
fi
IMAGE_TAR=${IMAGE_TAR:-k3s-airgap-images-${K3S_ARCH}.tar.zst}
cp "/opt/k3s-airgap/${IMAGE_TAR}" "/var/lib/rancher/k3s/agent/images/${IMAGE_TAR}"
touch /var/lib/rancher/k3s/agent/images/.cache.json
REMOTE
}

write_k3s_config() {
  local host=$1
  local node_name=$2
  local server_url=$3
  local cluster_init=$4
  local cgroup_version=$5
  local disabled_yaml=""
  local tls_san_yaml=""

  IFS=',' read -r -a disabled_components <<<"$K3S_DISABLE_COMPONENTS"
  for item in "${disabled_components[@]}"; do
    [[ -n "$item" ]] && disabled_yaml+="  - ${item}"$'\n'
  done

  local disable_block=""
  if [[ -n "$disabled_yaml" ]]; then
    disable_block=$'disable:\n'"$disabled_yaml"
  fi

  if [[ -n "$TLS_SAN_VALUES" ]]; then
    IFS=',' read -r -a tls_sans <<<"$TLS_SAN_VALUES"
    for item in "${tls_sans[@]}"; do
      [[ -n "$item" ]] && tls_san_yaml+="  - \"${item}\""$'\n'
    done
  fi

  local tls_san_block=""
  if [[ -n "$tls_san_yaml" ]]; then
    tls_san_block=$'tls-san:\n'"$tls_san_yaml"
  fi

  local kubelet_arg_block=""
  kubelet_arg_block+="  - \"node-labels=node.k3s-ha.io/cgroup-version=${cgroup_version}\""$'\n'
  if [[ "$K3S_CGROUP_DRIVER" != "auto" ]]; then
    kubelet_arg_block+="  - \"cgroup-driver=${K3S_CGROUP_DRIVER}\""$'\n'
  fi

  run_ssh "$host" "NODE_NAME='$node_name' K3S_TOKEN='$K3S_TOKEN' SERVER_URL='$server_url' CLUSTER_INIT='$cluster_init' K3S_CLUSTER_CIDR='$K3S_CLUSTER_CIDR' K3S_SERVICE_CIDR='$K3S_SERVICE_CIDR' K3S_CLUSTER_DNS='$K3S_CLUSTER_DNS' bash -s" <<REMOTE
set -euo pipefail
mkdir -p /etc/rancher/k3s
cat >/etc/rancher/k3s/config.yaml <<EOF
node-name: "\${NODE_NAME}"
token: "\${K3S_TOKEN}"
${tls_san_block}
write-kubeconfig-mode: "0600"
cluster-cidr: "\${K3S_CLUSTER_CIDR}"
service-cidr: "\${K3S_SERVICE_CIDR}"
cluster-dns: "\${K3S_CLUSTER_DNS}"
${disable_block}
kubelet-arg:
${kubelet_arg_block}
EOF
if [[ "\$CLUSTER_INIT" == "true" ]]; then
  cat >>/etc/rancher/k3s/config.yaml <<EOF
cluster-init: true
EOF
else
  cat >>/etc/rancher/k3s/config.yaml <<EOF
server: "\${SERVER_URL}"
EOF
fi
REMOTE
}

install_k3s() {
  local host=$1
  local install_env="INSTALL_K3S_CHANNEL='${K3S_CHANNEL}'"

  if [[ -n "${K3S_VERSION:-}" ]]; then
    install_env+=" INSTALL_K3S_VERSION='${K3S_VERSION}'"
  fi

  if [[ "$K3S_AIRGAP" == "true" ]]; then
    run_ssh "$host" "INSTALL_K3S_SKIP_DOWNLOAD=true /opt/k3s-airgap/install.sh"
  else
    run_ssh "$host" "$install_env sh -c 'curl -sfL https://get.k3s.io | sh -s - server'"
  fi
}

wait_for_node() {
  local host=$1
  local node=$2
  echo "wait node ready: $node"
  for _ in {1..60}; do
    if run_ssh "$host" "k3s kubectl get node '$node' >/dev/null 2>&1"; then
      return 0
    fi
    sleep 5
  done
  echo "node not visible after timeout: $node" >&2
  return 1
}

fetch_kubeconfig() {
  local first_host=${MASTER_HOSTS[0]}
  local kubeconfig="$ARTIFACT_DIR/kubeconfig.yaml"
  scp -P "$SSH_PORT" $SSH_OPTS "$(ssh_target "$first_host"):/etc/rancher/k3s/k3s.yaml" "$kubeconfig"
  sed -i.bak "s#https://127.0.0.1:6443#${KUBECONFIG_SERVER}#g" "$kubeconfig"
  rm -f "$kubeconfig.bak"
  chmod 0600 "$kubeconfig"
  echo "kubeconfig: $kubeconfig"
}

main() {
  local server_url="$K3S_JOIN_ENDPOINT"
  local host

  check_connectivity
  preflight_host_profiles

  for host in "${MASTER_HOSTS[@]}"; do
    local i
    for i in "${!MASTER_HOSTS[@]}"; do
      [[ "${MASTER_HOSTS[$i]}" == "$host" ]] && break
    done
    echo "prepare host: $host"
    install_os_packages "$host"
    configure_sysctl "$host"
    if [[ "$K3S_AIRGAP" == "true" ]]; then
      install_airgap_payload "$host" "${DETECTED_ARCHES[$i]}"
    fi
  done

  write_k3s_config "${MASTER_HOSTS[0]}" "${MASTER_NAMES[0]}" "" true "${DETECTED_CGROUPS[0]}"
  install_k3s "${MASTER_HOSTS[0]}"
  wait_for_node "${MASTER_HOSTS[0]}" "${MASTER_NAMES[0]}"

  write_k3s_config "${MASTER_HOSTS[1]}" "${MASTER_NAMES[1]}" "$server_url" false "${DETECTED_CGROUPS[1]}"
  install_k3s "${MASTER_HOSTS[1]}"
  wait_for_node "${MASTER_HOSTS[0]}" "${MASTER_NAMES[1]}"

  write_k3s_config "${MASTER_HOSTS[2]}" "${MASTER_NAMES[2]}" "$server_url" false "${DETECTED_CGROUPS[2]}"
  install_k3s "${MASTER_HOSTS[2]}"
  wait_for_node "${MASTER_HOSTS[0]}" "${MASTER_NAMES[2]}"

  fetch_kubeconfig
  run_ssh "${MASTER_HOSTS[0]}" "k3s kubectl get nodes -o wide"
  echo "done"
}

main "$@"
