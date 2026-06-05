#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  deploy-keepalived-haproxy.sh <配置文件.env>

示例:
  bash keepalived-haproxy/scripts/deploy-keepalived-haproxy.sh keepalived-haproxy/prod.env
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
VIP=${VIP:?}
VIP_CIDR=${VIP_CIDR:-24}
NODE_INTERFACE=${NODE_INTERFACE:?}
API_LB_PORT=${API_LB_PORT:-8443}
BACKEND_PORT=${BACKEND_PORT:-${K3S_API_PORT:-6443}}
VRRP_ROUTER_ID=${VRRP_ROUTER_ID:-51}
VRRP_AUTH_PASS=${VRRP_AUTH_PASS:-k3s-ha}
VRRP_PRIORITIES=${VRRP_PRIORITIES:-120,110,100}
LB_AIRGAP=${LB_AIRGAP:-false}

LB_NAMES=(
  "${LB1_NAME:-${MASTER1_NAME:?}}"
  "${LB2_NAME:-${MASTER2_NAME:?}}"
  "${LB3_NAME:-${MASTER3_NAME:?}}"
)
LB_HOSTS=(
  "${LB1_HOST:-${MASTER1_HOST:?}}"
  "${LB2_HOST:-${MASTER2_HOST:?}}"
  "${LB3_HOST:-${MASTER3_HOST:?}}"
)
BACKEND_NAMES=(
  "${BACKEND1_NAME:-${MASTER1_NAME:?}}"
  "${BACKEND2_NAME:-${MASTER2_NAME:?}}"
  "${BACKEND3_NAME:-${MASTER3_NAME:?}}"
)
BACKEND_HOSTS=(
  "${BACKEND1_HOST:-${MASTER1_HOST:?}}"
  "${BACKEND2_HOST:-${MASTER2_HOST:?}}"
  "${BACKEND3_HOST:-${MASTER3_HOST:?}}"
)

IFS=',' read -r -a PRIORITIES <<<"$VRRP_PRIORITIES"
if [[ "${#PRIORITIES[@]}" -ne "${#LB_HOSTS[@]}" ]]; then
  echo "VRRP_PRIORITIES count must match LB node count." >&2
  exit 1
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "required command not found: $1" >&2
    exit 1
  }
}

require_cmd ssh

ssh_target() {
  local host=$1
  printf '%s@%s' "$SSH_USER" "$host"
}

run_ssh() {
  local host=$1
  shift
  ssh -p "$SSH_PORT" $SSH_OPTS "$(ssh_target "$host")" "$@"
}

backend_lines() {
  local lines=""
  for i in "${!BACKEND_HOSTS[@]}"; do
    lines+="    server ${BACKEND_NAMES[$i]} ${BACKEND_HOSTS[$i]}:${BACKEND_PORT} check fall 3 rise 2"$'\n'
  done
  printf '%s' "$lines"
}

check_connectivity() {
  local host
  for host in "${LB_HOSTS[@]}"; do
    echo "check ssh: $host"
    run_ssh "$host" "echo ok >/dev/null"
  done
}

install_os_packages() {
  local host=$1
  if [[ "$LB_AIRGAP" == "true" ]]; then
    run_ssh "$host" "command -v haproxy >/dev/null && command -v keepalived >/dev/null"
    return
  fi

  run_ssh "$host" "bash -s" <<'REMOTE'
set -euo pipefail
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y haproxy keepalived iproute2 iptables psmisc
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y haproxy keepalived iproute iptables psmisc
elif command -v yum >/dev/null 2>&1; then
  yum install -y haproxy keepalived iproute iptables psmisc
else
  echo "unsupported package manager; install haproxy and keepalived manually" >&2
  exit 1
fi
REMOTE
}

configure_sysctl() {
  local host=$1
  run_ssh "$host" "bash -s" <<'REMOTE'
set -euo pipefail
cat >/etc/sysctl.d/99-keepalived-haproxy.conf <<'EOF'
net.ipv4.ip_nonlocal_bind = 1
EOF
sysctl --system >/dev/null
REMOTE
}

configure_haproxy() {
  local host=$1
  local backends
  backends=$(backend_lines)
  run_ssh "$host" "VIP='$VIP' API_LB_PORT='$API_LB_PORT' bash -s" <<REMOTE
set -euo pipefail
cat >/etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log local0
    log /dev/log local1 notice
    daemon
    maxconn 4096

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 5s
    timeout client  50s
    timeout server  50s

frontend k3s_api
    bind \${VIP}:\${API_LB_PORT}
    default_backend k3s_masters

backend k3s_masters
    balance roundrobin
    option tcp-check
${backends}EOF
haproxy -c -f /etc/haproxy/haproxy.cfg
systemctl enable --now haproxy
systemctl restart haproxy
REMOTE
}

configure_keepalived() {
  local host=$1
  local state=$2
  local priority=$3
  run_ssh "$host" "VIP='$VIP' VIP_CIDR='$VIP_CIDR' NODE_INTERFACE='$NODE_INTERFACE' VRRP_ROUTER_ID='$VRRP_ROUTER_ID' VRRP_AUTH_PASS='$VRRP_AUTH_PASS' STATE='$state' PRIORITY='$priority' bash -s" <<'REMOTE'
set -euo pipefail
cat >/etc/keepalived/check_haproxy.sh <<'EOF'
#!/usr/bin/env bash
killall -0 haproxy
EOF
chmod +x /etc/keepalived/check_haproxy.sh

cat >/etc/keepalived/keepalived.conf <<EOF
global_defs {
    enable_script_security
    script_user root
}

vrrp_script chk_haproxy {
    script "/etc/keepalived/check_haproxy.sh"
    interval 2
    timeout 2
    fall 2
    rise 2
    weight -30
}

vrrp_instance VI_K3S_API {
    state ${STATE}
    interface ${NODE_INTERFACE}
    virtual_router_id ${VRRP_ROUTER_ID}
    priority ${PRIORITY}
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass ${VRRP_AUTH_PASS}
    }
    virtual_ipaddress {
        ${VIP}/${VIP_CIDR}
    }
    track_script {
        chk_haproxy
    }
}
EOF
systemctl enable --now keepalived
systemctl restart keepalived
REMOTE
}

wait_for_vip() {
  echo "wait VIP: $VIP:$API_LB_PORT"
  for _ in {1..60}; do
    for host in "${LB_HOSTS[@]}"; do
      if run_ssh "$host" "timeout 2 bash -c '</dev/tcp/$VIP/$API_LB_PORT' >/dev/null 2>&1"; then
        return 0
      fi
    done
    sleep 2
  done
  echo "VIP is not reachable: $VIP:$API_LB_PORT" >&2
  return 1
}

main() {
  check_connectivity
  for host in "${LB_HOSTS[@]}"; do
    echo "prepare lb host: $host"
    install_os_packages "$host"
    configure_sysctl "$host"
    configure_haproxy "$host"
  done

  configure_keepalived "${LB_HOSTS[0]}" MASTER "${PRIORITIES[0]}"
  configure_keepalived "${LB_HOSTS[1]}" BACKUP "${PRIORITIES[1]}"
  configure_keepalived "${LB_HOSTS[2]}" BACKUP "${PRIORITIES[2]}"

  wait_for_vip
  echo "done"
}

main "$@"
