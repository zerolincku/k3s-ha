#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

need_cmd virsh
need_cmd openssl

ips=()
for index in $(seq 1 "$VM_COUNT"); do
  name=$(vm_name "$index")
  ip=$(wait_for_vm_ip "$name" 180)
  ips+=("$ip")
done

if [[ "${#ips[@]}" -ne 3 ]]; then
  echo "当前 K3s HA 部署脚本需要刚好 3 台 master，实际发现: ${#ips[@]}" >&2
  exit 1
fi

token=$(openssl rand -hex 32)
tls_sans="${ips[0]},${ips[1]},${ips[2]}"
if [[ -n "$TLS_SAN_VALUES_EXTRA" ]]; then
  tls_sans="$tls_sans,$TLS_SAN_VALUES_EXTRA"
fi

out="$LAB_DIR/generated/k3s-vm.env"
cat >"$out" <<EOF
SSH_USER=root
SSH_PORT=22
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$LAB_DIR/generated/known_hosts"

MASTER1_NAME=$(vm_name 1)
MASTER1_HOST=${ips[0]}
MASTER1_SSH_HOST=
MASTER1_ARCH=amd64
MASTER2_NAME=$(vm_name 2)
MASTER2_HOST=${ips[1]}
MASTER2_SSH_HOST=
MASTER2_ARCH=amd64
MASTER3_NAME=$(vm_name 3)
MASTER3_HOST=${ips[2]}
MASTER3_SSH_HOST=
MASTER3_ARCH=amd64

K3S_JOIN_ENDPOINT=
K3S_API_PORT=6443
KUBECONFIG_SERVER=
TLS_SAN_VALUES=$tls_sans

K3S_VERSION=v1.35.5+k3s1
K3S_CHANNEL=stable
K3S_TOKEN=$token
K3S_CLUSTER_CIDR=10.42.0.0/16
K3S_SERVICE_CIDR=10.43.0.0/16
K3S_CLUSTER_DNS=10.43.0.10

CGROUP_MODE=auto
K3S_CGROUP_DRIVER=auto
IGNORE_OS_PREREQ_MISSING=false
K3S_DISABLE_COMPONENTS=traefik

K3S_PRIVATE_REGISTRY_FILE=
K3S_SYSTEM_DEFAULT_REGISTRY=
K3S_PAUSE_IMAGE=

K3S_AIRGAP=false
AIRGAP_BUNDLE=
AIRGAP_BUNDLE_AMD64=
AIRGAP_BUNDLE_ARM64=
K3S_ASSETS_PRELOADED=false
K3S_BINARY=
K3S_BINARY_AMD64=
K3S_BINARY_ARM64=
K3S_INSTALL_SCRIPT=
K3S_IMAGE_TAR=
K3S_IMAGE_TAR_AMD64=
K3S_IMAGE_TAR_ARM64=
K3S_ARCH=amd64

ARTIFACT_DIR=./k3s/artifacts
EOF

echo "已生成: $out"
echo
echo "下一步:"
echo "  bash k3s/scripts/deploy-k3s-ha.sh $out"
