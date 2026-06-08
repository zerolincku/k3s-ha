#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
用法:
  deploy-rook-ceph.sh <config.env>

示例:
  bash rook-ceph/scripts/deploy-rook-ceph.sh rook-ceph/prod.env

说明:
  部署 Rook Operator、CephCluster、CephFS StorageClass 和 RGW Object Store。
  如果是完全离线环境，请先执行 upload-rook-ceph-images.sh，并设置本地 Rook manifest 路径。
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

CONFIG=$1
if [[ ! -f "$CONFIG" ]]; then
  echo "配置文件不存在: $CONFIG" >&2
  exit 1
fi

ENV_KUBECONFIG=${KUBECONFIG:-}
ENV_ROOK_CEPH_NAMESPACE=${ROOK_CEPH_NAMESPACE:-}
ENV_ROOK_CEPH_CRDS_MANIFEST=${ROOK_CEPH_CRDS_MANIFEST:-}
ENV_ROOK_CEPH_COMMON_MANIFEST=${ROOK_CEPH_COMMON_MANIFEST:-}
ENV_ROOK_CEPH_CSI_OPERATOR_MANIFEST=${ROOK_CEPH_CSI_OPERATOR_MANIFEST:-}
ENV_ROOK_CEPH_OPERATOR_MANIFEST=${ROOK_CEPH_OPERATOR_MANIFEST:-}
ENV_ROOK_CEPH_CRDS_URL=${ROOK_CEPH_CRDS_URL:-}
ENV_ROOK_CEPH_COMMON_URL=${ROOK_CEPH_COMMON_URL:-}
ENV_ROOK_CEPH_CSI_OPERATOR_URL=${ROOK_CEPH_CSI_OPERATOR_URL:-}
ENV_ROOK_CEPH_OPERATOR_URL=${ROOK_CEPH_OPERATOR_URL:-}
ENV_ROOK_CEPH_IMAGE=${ROOK_CEPH_IMAGE:-}
ENV_ROOK_CEPH_CEPH_IMAGE=${ROOK_CEPH_CEPH_IMAGE:-}
ENV_ROOK_CEPH_IMAGE_PULL_POLICY=${ROOK_CEPH_IMAGE_PULL_POLICY:-}
ENV_ROOK_CEPH_DATA_DIR_HOST_PATH=${ROOK_CEPH_DATA_DIR_HOST_PATH:-}
ENV_ROOK_CEPH_USE_ALL_NODES=${ROOK_CEPH_USE_ALL_NODES:-}
ENV_ROOK_CEPH_USE_ALL_DEVICES=${ROOK_CEPH_USE_ALL_DEVICES:-}
ENV_ROOK_CEPH_DEVICES=${ROOK_CEPH_DEVICES:-}
ENV_ROOK_CEPH_REPLICATED_REQUIRE_SAFE_REPLICA_SIZE=${ROOK_CEPH_REPLICATED_REQUIRE_SAFE_REPLICA_SIZE:-}
ENV_ROOK_CEPH_MON_COUNT=${ROOK_CEPH_MON_COUNT:-}
ENV_ROOK_CEPH_ALLOW_MULTIPLE_PER_NODE=${ROOK_CEPH_ALLOW_MULTIPLE_PER_NODE:-}
ENV_ROOK_CEPH_MGR_COUNT=${ROOK_CEPH_MGR_COUNT:-}
ENV_ROOK_CEPH_DASHBOARD_ENABLED=${ROOK_CEPH_DASHBOARD_ENABLED:-}
ENV_ROOK_CEPH_DASHBOARD_SSL=${ROOK_CEPH_DASHBOARD_SSL:-}
ENV_ROOK_CEPH_WAIT_TIMEOUT=${ROOK_CEPH_WAIT_TIMEOUT:-}
ENV_ROOK_CEPH_FS_NAME=${ROOK_CEPH_FS_NAME:-}
ENV_ROOK_CEPH_FS_MDS_ACTIVE_COUNT=${ROOK_CEPH_FS_MDS_ACTIVE_COUNT:-}
ENV_ROOK_CEPH_FS_MDS_ACTIVE_STANDBY=${ROOK_CEPH_FS_MDS_ACTIVE_STANDBY:-}
ENV_ROOK_CEPH_FS_METADATA_POOL_SIZE=${ROOK_CEPH_FS_METADATA_POOL_SIZE:-}
ENV_ROOK_CEPH_FS_DATA_POOL_SIZE=${ROOK_CEPH_FS_DATA_POOL_SIZE:-}
ENV_ROOK_CEPH_FS_STORAGE_CLASS=${ROOK_CEPH_FS_STORAGE_CLASS:-}
ENV_ROOK_CEPH_FS_RECLAIM_POLICY=${ROOK_CEPH_FS_RECLAIM_POLICY:-}
ENV_ROOK_CEPH_FS_ALLOW_VOLUME_EXPANSION=${ROOK_CEPH_FS_ALLOW_VOLUME_EXPANSION:-}
ENV_ROOK_CEPH_OBJECT_STORE_NAME=${ROOK_CEPH_OBJECT_STORE_NAME:-}
ENV_ROOK_CEPH_OBJECT_STORE_METADATA_POOL_SIZE=${ROOK_CEPH_OBJECT_STORE_METADATA_POOL_SIZE:-}
ENV_ROOK_CEPH_OBJECT_STORE_DATA_POOL_SIZE=${ROOK_CEPH_OBJECT_STORE_DATA_POOL_SIZE:-}
ENV_ROOK_CEPH_OBJECT_STORE_GATEWAY_INSTANCES=${ROOK_CEPH_OBJECT_STORE_GATEWAY_INSTANCES:-}
ENV_ROOK_CEPH_OBJECT_STORE_GATEWAY_PORT=${ROOK_CEPH_OBJECT_STORE_GATEWAY_PORT:-}
ENV_ROOK_CEPH_OBJECT_STORE_PRESERVE_POOLS_ON_DELETE=${ROOK_CEPH_OBJECT_STORE_PRESERVE_POOLS_ON_DELETE:-}
ENV_ROOK_CEPH_BUCKET_STORAGE_CLASS=${ROOK_CEPH_BUCKET_STORAGE_CLASS:-}
ENV_ROOK_CEPH_BUCKET_RECLAIM_POLICY=${ROOK_CEPH_BUCKET_RECLAIM_POLICY:-}
ENV_ROOK_CEPH_OBJECT_USER_NAME=${ROOK_CEPH_OBJECT_USER_NAME:-}
ENV_ROOK_CEPH_OBJECT_USER_DISPLAY_NAME=${ROOK_CEPH_OBJECT_USER_DISPLAY_NAME:-}
ENV_ROOK_CEPH_INSTALL_OPERATOR=${ROOK_CEPH_INSTALL_OPERATOR:-}
ENV_ROOK_CEPH_INSTALL_CLUSTER=${ROOK_CEPH_INSTALL_CLUSTER:-}
ENV_ROOK_CEPH_INSTALL_FILESYSTEM=${ROOK_CEPH_INSTALL_FILESYSTEM:-}
ENV_ROOK_CEPH_INSTALL_OBJECT_STORE=${ROOK_CEPH_INSTALL_OBJECT_STORE:-}

# shellcheck disable=SC1090
source "$CONFIG"

KUBECONFIG=${ENV_KUBECONFIG:-${KUBECONFIG:-}}
ROOK_CEPH_NAMESPACE=${ENV_ROOK_CEPH_NAMESPACE:-${ROOK_CEPH_NAMESPACE:-rook-ceph}}
ROOK_CEPH_CRDS_MANIFEST=${ENV_ROOK_CEPH_CRDS_MANIFEST:-${ROOK_CEPH_CRDS_MANIFEST:-}}
ROOK_CEPH_COMMON_MANIFEST=${ENV_ROOK_CEPH_COMMON_MANIFEST:-${ROOK_CEPH_COMMON_MANIFEST:-}}
ROOK_CEPH_CSI_OPERATOR_MANIFEST=${ENV_ROOK_CEPH_CSI_OPERATOR_MANIFEST:-${ROOK_CEPH_CSI_OPERATOR_MANIFEST:-}}
ROOK_CEPH_OPERATOR_MANIFEST=${ENV_ROOK_CEPH_OPERATOR_MANIFEST:-${ROOK_CEPH_OPERATOR_MANIFEST:-}}
ROOK_CEPH_CRDS_URL=${ENV_ROOK_CEPH_CRDS_URL:-${ROOK_CEPH_CRDS_URL:-https://raw.githubusercontent.com/rook/rook/v1.19.6/deploy/examples/crds.yaml}}
ROOK_CEPH_COMMON_URL=${ENV_ROOK_CEPH_COMMON_URL:-${ROOK_CEPH_COMMON_URL:-https://raw.githubusercontent.com/rook/rook/v1.19.6/deploy/examples/common.yaml}}
ROOK_CEPH_CSI_OPERATOR_URL=${ENV_ROOK_CEPH_CSI_OPERATOR_URL:-${ROOK_CEPH_CSI_OPERATOR_URL:-https://raw.githubusercontent.com/rook/rook/v1.19.6/deploy/examples/csi-operator.yaml}}
ROOK_CEPH_OPERATOR_URL=${ENV_ROOK_CEPH_OPERATOR_URL:-${ROOK_CEPH_OPERATOR_URL:-https://raw.githubusercontent.com/rook/rook/v1.19.6/deploy/examples/operator.yaml}}
ROOK_CEPH_IMAGE=${ENV_ROOK_CEPH_IMAGE:-${ROOK_CEPH_IMAGE:-quay.io/rook/ceph:v1.19.6}}
ROOK_CEPH_CEPH_IMAGE=${ENV_ROOK_CEPH_CEPH_IMAGE:-${ROOK_CEPH_CEPH_IMAGE:-quay.io/ceph/ceph:v19.2.3}}
ROOK_CEPH_IMAGE_PULL_POLICY=${ENV_ROOK_CEPH_IMAGE_PULL_POLICY:-${ROOK_CEPH_IMAGE_PULL_POLICY:-IfNotPresent}}
ROOK_CEPH_DATA_DIR_HOST_PATH=${ENV_ROOK_CEPH_DATA_DIR_HOST_PATH:-${ROOK_CEPH_DATA_DIR_HOST_PATH:-/var/lib/rook}}
ROOK_CEPH_USE_ALL_NODES=${ENV_ROOK_CEPH_USE_ALL_NODES:-${ROOK_CEPH_USE_ALL_NODES:-true}}
ROOK_CEPH_USE_ALL_DEVICES=${ENV_ROOK_CEPH_USE_ALL_DEVICES:-${ROOK_CEPH_USE_ALL_DEVICES:-false}}
ROOK_CEPH_DEVICES=${ENV_ROOK_CEPH_DEVICES:-${ROOK_CEPH_DEVICES:-/dev/vdb}}
ROOK_CEPH_REPLICATED_REQUIRE_SAFE_REPLICA_SIZE=${ENV_ROOK_CEPH_REPLICATED_REQUIRE_SAFE_REPLICA_SIZE:-${ROOK_CEPH_REPLICATED_REQUIRE_SAFE_REPLICA_SIZE:-true}}
ROOK_CEPH_MON_COUNT=${ENV_ROOK_CEPH_MON_COUNT:-${ROOK_CEPH_MON_COUNT:-3}}
ROOK_CEPH_ALLOW_MULTIPLE_PER_NODE=${ENV_ROOK_CEPH_ALLOW_MULTIPLE_PER_NODE:-${ROOK_CEPH_ALLOW_MULTIPLE_PER_NODE:-false}}
ROOK_CEPH_MGR_COUNT=${ENV_ROOK_CEPH_MGR_COUNT:-${ROOK_CEPH_MGR_COUNT:-2}}
ROOK_CEPH_DASHBOARD_ENABLED=${ENV_ROOK_CEPH_DASHBOARD_ENABLED:-${ROOK_CEPH_DASHBOARD_ENABLED:-true}}
ROOK_CEPH_DASHBOARD_SSL=${ENV_ROOK_CEPH_DASHBOARD_SSL:-${ROOK_CEPH_DASHBOARD_SSL:-false}}
ROOK_CEPH_WAIT_TIMEOUT=${ENV_ROOK_CEPH_WAIT_TIMEOUT:-${ROOK_CEPH_WAIT_TIMEOUT:-1200s}}
ROOK_CEPH_FS_NAME=${ENV_ROOK_CEPH_FS_NAME:-${ROOK_CEPH_FS_NAME:-cephfs}}
ROOK_CEPH_FS_MDS_ACTIVE_COUNT=${ENV_ROOK_CEPH_FS_MDS_ACTIVE_COUNT:-${ROOK_CEPH_FS_MDS_ACTIVE_COUNT:-1}}
ROOK_CEPH_FS_MDS_ACTIVE_STANDBY=${ENV_ROOK_CEPH_FS_MDS_ACTIVE_STANDBY:-${ROOK_CEPH_FS_MDS_ACTIVE_STANDBY:-true}}
ROOK_CEPH_FS_METADATA_POOL_SIZE=${ENV_ROOK_CEPH_FS_METADATA_POOL_SIZE:-${ROOK_CEPH_FS_METADATA_POOL_SIZE:-3}}
ROOK_CEPH_FS_DATA_POOL_SIZE=${ENV_ROOK_CEPH_FS_DATA_POOL_SIZE:-${ROOK_CEPH_FS_DATA_POOL_SIZE:-3}}
ROOK_CEPH_FS_STORAGE_CLASS=${ENV_ROOK_CEPH_FS_STORAGE_CLASS:-${ROOK_CEPH_FS_STORAGE_CLASS:-rook-cephfs}}
ROOK_CEPH_FS_RECLAIM_POLICY=${ENV_ROOK_CEPH_FS_RECLAIM_POLICY:-${ROOK_CEPH_FS_RECLAIM_POLICY:-Retain}}
ROOK_CEPH_FS_ALLOW_VOLUME_EXPANSION=${ENV_ROOK_CEPH_FS_ALLOW_VOLUME_EXPANSION:-${ROOK_CEPH_FS_ALLOW_VOLUME_EXPANSION:-true}}
ROOK_CEPH_OBJECT_STORE_NAME=${ENV_ROOK_CEPH_OBJECT_STORE_NAME:-${ROOK_CEPH_OBJECT_STORE_NAME:-objectstore}}
ROOK_CEPH_OBJECT_STORE_METADATA_POOL_SIZE=${ENV_ROOK_CEPH_OBJECT_STORE_METADATA_POOL_SIZE:-${ROOK_CEPH_OBJECT_STORE_METADATA_POOL_SIZE:-3}}
ROOK_CEPH_OBJECT_STORE_DATA_POOL_SIZE=${ENV_ROOK_CEPH_OBJECT_STORE_DATA_POOL_SIZE:-${ROOK_CEPH_OBJECT_STORE_DATA_POOL_SIZE:-3}}
ROOK_CEPH_OBJECT_STORE_GATEWAY_INSTANCES=${ENV_ROOK_CEPH_OBJECT_STORE_GATEWAY_INSTANCES:-${ROOK_CEPH_OBJECT_STORE_GATEWAY_INSTANCES:-2}}
ROOK_CEPH_OBJECT_STORE_GATEWAY_PORT=${ENV_ROOK_CEPH_OBJECT_STORE_GATEWAY_PORT:-${ROOK_CEPH_OBJECT_STORE_GATEWAY_PORT:-80}}
ROOK_CEPH_OBJECT_STORE_PRESERVE_POOLS_ON_DELETE=${ENV_ROOK_CEPH_OBJECT_STORE_PRESERVE_POOLS_ON_DELETE:-${ROOK_CEPH_OBJECT_STORE_PRESERVE_POOLS_ON_DELETE:-true}}
ROOK_CEPH_BUCKET_STORAGE_CLASS=${ENV_ROOK_CEPH_BUCKET_STORAGE_CLASS:-${ROOK_CEPH_BUCKET_STORAGE_CLASS:-rook-ceph-bucket}}
ROOK_CEPH_BUCKET_RECLAIM_POLICY=${ENV_ROOK_CEPH_BUCKET_RECLAIM_POLICY:-${ROOK_CEPH_BUCKET_RECLAIM_POLICY:-Retain}}
ROOK_CEPH_OBJECT_USER_NAME=${ENV_ROOK_CEPH_OBJECT_USER_NAME:-${ROOK_CEPH_OBJECT_USER_NAME:-admin}}
ROOK_CEPH_OBJECT_USER_DISPLAY_NAME=${ENV_ROOK_CEPH_OBJECT_USER_DISPLAY_NAME:-${ROOK_CEPH_OBJECT_USER_DISPLAY_NAME:-Rook Ceph RGW Admin}}
ROOK_CEPH_INSTALL_OPERATOR=${ENV_ROOK_CEPH_INSTALL_OPERATOR:-${ROOK_CEPH_INSTALL_OPERATOR:-true}}
ROOK_CEPH_INSTALL_CLUSTER=${ENV_ROOK_CEPH_INSTALL_CLUSTER:-${ROOK_CEPH_INSTALL_CLUSTER:-true}}
ROOK_CEPH_INSTALL_FILESYSTEM=${ENV_ROOK_CEPH_INSTALL_FILESYSTEM:-${ROOK_CEPH_INSTALL_FILESYSTEM:-true}}
ROOK_CEPH_INSTALL_OBJECT_STORE=${ENV_ROOK_CEPH_INSTALL_OBJECT_STORE:-${ROOK_CEPH_INSTALL_OBJECT_STORE:-true}}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少本地命令: $1" >&2
    exit 1
  }
}

escape_sed() {
  printf '%s' "$1" | sed -e 's/[\/&|]/\\&/g'
}

render_devices() {
  if [[ "$ROOK_CEPH_USE_ALL_DEVICES" == "true" ]]; then
    printf '      []\n'
    return
  fi

  if [[ -z "$ROOK_CEPH_DEVICES" ]]; then
    echo "ROOK_CEPH_USE_ALL_DEVICES=false 时必须设置 ROOK_CEPH_DEVICES。" >&2
    exit 1
  fi

  IFS=',' read -r -a devices <<<"$ROOK_CEPH_DEVICES"
  for device in "${devices[@]}"; do
    [[ -z "$device" ]] && continue
    printf '      - name: "%s"\n' "$device"
  done
}

apply_manifest() {
  local local_file=$1
  local url=$2
  local name=$3

  if [[ -n "$local_file" ]]; then
    if [[ ! -f "$local_file" ]]; then
      echo "找不到 ${name} 本地 manifest: $local_file" >&2
      exit 1
    fi
    echo "应用 ${name} 本地 manifest: $local_file"
    kubectl apply -f "$local_file"
  else
    echo "应用 ${name} 在线 manifest: $url"
    kubectl apply -f "$url"
  fi
}

wait_deployments() {
  echo "等待 Rook Operator 和 CSI 组件就绪"
  kubectl -n "$ROOK_CEPH_NAMESPACE" wait --for=condition=Available deployment --all --timeout="$ROOK_CEPH_WAIT_TIMEOUT"
}

wait_ceph_cluster() {
  echo "等待 CephCluster 基础组件就绪"
  kubectl -n "$ROOK_CEPH_NAMESPACE" wait --for=condition=Ready "cephcluster/rook-ceph" --timeout="$ROOK_CEPH_WAIT_TIMEOUT" || {
    echo "CephCluster 未在预期时间内 Ready，输出当前状态和最近事件。" >&2
    kubectl -n "$ROOK_CEPH_NAMESPACE" get pods -o wide || true
    kubectl -n "$ROOK_CEPH_NAMESPACE" describe cephcluster rook-ceph || true
    kubectl -n "$ROOK_CEPH_NAMESPACE" get events --sort-by=.lastTimestamp | tail -40 || true
    exit 1
  }
}

wait_ceph_filesystem() {
  echo "等待 CephFilesystem 就绪: $ROOK_CEPH_FS_NAME"
  kubectl -n "$ROOK_CEPH_NAMESPACE" wait --for=condition=Ready "cephfilesystem/$ROOK_CEPH_FS_NAME" --timeout="$ROOK_CEPH_WAIT_TIMEOUT" || {
    echo "CephFilesystem 未在预期时间内 Ready，输出当前状态和最近事件。" >&2
    kubectl -n "$ROOK_CEPH_NAMESPACE" get pods -l app=rook-ceph-mds -o wide || true
    kubectl -n "$ROOK_CEPH_NAMESPACE" describe cephfilesystem "$ROOK_CEPH_FS_NAME" || true
    kubectl -n "$ROOK_CEPH_NAMESPACE" get events --sort-by=.lastTimestamp | tail -40 || true
    exit 1
  }
}

wait_object_store() {
  echo "等待 CephObjectStore 就绪: $ROOK_CEPH_OBJECT_STORE_NAME"
  kubectl -n "$ROOK_CEPH_NAMESPACE" wait --for=condition=Ready "cephobjectstore/$ROOK_CEPH_OBJECT_STORE_NAME" --timeout="$ROOK_CEPH_WAIT_TIMEOUT" || {
    echo "CephObjectStore 未在预期时间内 Ready，输出当前状态和最近事件。" >&2
    kubectl -n "$ROOK_CEPH_NAMESPACE" get pods -l app=rook-ceph-rgw -o wide || true
    kubectl -n "$ROOK_CEPH_NAMESPACE" describe cephobjectstore "$ROOK_CEPH_OBJECT_STORE_NAME" || true
    kubectl -n "$ROOK_CEPH_NAMESPACE" get events --sort-by=.lastTimestamp | tail -40 || true
    exit 1
  }
}

require_cmd kubectl
require_cmd sed
require_cmd mktemp
require_cmd tail

if [[ -n "$KUBECONFIG" ]]; then
  export KUBECONFIG
fi

if [[ "$ROOK_CEPH_NAMESPACE" != "rook-ceph" ]]; then
  echo "当前脚本使用 Rook 官方示例 manifest，namespace 固定为 rook-ceph。请保持 ROOK_CEPH_NAMESPACE=rook-ceph。" >&2
  exit 1
fi

case "$ROOK_CEPH_IMAGE_PULL_POLICY" in
  IfNotPresent | Never | Always) ;;
  *)
    echo "ROOK_CEPH_IMAGE_PULL_POLICY 取值不合法: $ROOK_CEPH_IMAGE_PULL_POLICY" >&2
    echo "Kubernetes 只支持 IfNotPresent、Never、Always。离线导入场景建议使用 IfNotPresent。" >&2
    exit 1
    ;;
esac

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RESOURCE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
CLUSTER_TEMPLATE="$RESOURCE_DIR/manifests/ceph-cluster.yaml.tpl"
FILESYSTEM_TEMPLATE="$RESOURCE_DIR/manifests/ceph-filesystem.yaml.tpl"
OBJECTSTORE_TEMPLATE="$RESOURCE_DIR/manifests/ceph-objectstore.yaml.tpl"

for template in "$CLUSTER_TEMPLATE" "$FILESYSTEM_TEMPLATE" "$OBJECTSTORE_TEMPLATE"; do
  if [[ ! -f "$template" ]]; then
    echo "找不到 manifest 模板: $template" >&2
    exit 1
  fi
done

cluster_rendered=$(mktemp "${TMPDIR:-/tmp}/rook-ceph-cluster.XXXXXX.yaml")
filesystem_rendered=$(mktemp "${TMPDIR:-/tmp}/rook-ceph-filesystem.XXXXXX.yaml")
objectstore_rendered=$(mktemp "${TMPDIR:-/tmp}/rook-ceph-objectstore.XXXXXX.yaml")
devices_rendered=$(mktemp "${TMPDIR:-/tmp}/rook-ceph-devices.XXXXXX.yaml")
trap 'rm -f "$cluster_rendered" "$filesystem_rendered" "$objectstore_rendered" "$devices_rendered"' EXIT

echo "检查 Kubernetes 连接"
kubectl version --client >/dev/null
kubectl cluster-info >/dev/null

if [[ "$ROOK_CEPH_INSTALL_OPERATOR" == "true" ]]; then
  apply_manifest "$ROOK_CEPH_CRDS_MANIFEST" "$ROOK_CEPH_CRDS_URL" "Rook CRD"
  apply_manifest "$ROOK_CEPH_COMMON_MANIFEST" "$ROOK_CEPH_COMMON_URL" "Rook common"
  apply_manifest "$ROOK_CEPH_CSI_OPERATOR_MANIFEST" "$ROOK_CEPH_CSI_OPERATOR_URL" "Rook CSI Operator"
  apply_manifest "$ROOK_CEPH_OPERATOR_MANIFEST" "$ROOK_CEPH_OPERATOR_URL" "Rook Operator"
  echo "设置 Rook Operator 镜像: $ROOK_CEPH_IMAGE"
  kubectl -n "$ROOK_CEPH_NAMESPACE" set image deployment/rook-ceph-operator "rook-ceph-operator=$ROOK_CEPH_IMAGE"
  echo "设置 Rook / CSI 镜像拉取策略: $ROOK_CEPH_IMAGE_PULL_POLICY"
  kubectl -n "$ROOK_CEPH_NAMESPACE" patch deployment rook-ceph-operator --type=strategic \
    -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"rook-ceph-operator\",\"imagePullPolicy\":\"$ROOK_CEPH_IMAGE_PULL_POLICY\"}]}}}}"
  kubectl -n "$ROOK_CEPH_NAMESPACE" set env deployment/rook-ceph-operator "ROOK_CSI_IMAGE_PULL_POLICY=$ROOK_CEPH_IMAGE_PULL_POLICY"
  wait_deployments
else
  echo "跳过 Rook Operator 安装，确认集群中已经存在 CRD、RBAC、Operator 和 CSI 组件。"
fi

if [[ "$ROOK_CEPH_INSTALL_CLUSTER" == "true" ]]; then
  render_devices >"$devices_rendered"
  sed \
    -e "s|__ROOK_CEPH_NAMESPACE__|$(escape_sed "$ROOK_CEPH_NAMESPACE")|g" \
    -e "s|__ROOK_CEPH_CEPH_IMAGE__|$(escape_sed "$ROOK_CEPH_CEPH_IMAGE")|g" \
    -e "s|__ROOK_CEPH_DATA_DIR_HOST_PATH__|$(escape_sed "$ROOK_CEPH_DATA_DIR_HOST_PATH")|g" \
    -e "s|__ROOK_CEPH_USE_ALL_NODES__|$(escape_sed "$ROOK_CEPH_USE_ALL_NODES")|g" \
    -e "s|__ROOK_CEPH_USE_ALL_DEVICES__|$(escape_sed "$ROOK_CEPH_USE_ALL_DEVICES")|g" \
    -e "s|__ROOK_CEPH_MON_COUNT__|$(escape_sed "$ROOK_CEPH_MON_COUNT")|g" \
    -e "s|__ROOK_CEPH_ALLOW_MULTIPLE_PER_NODE__|$(escape_sed "$ROOK_CEPH_ALLOW_MULTIPLE_PER_NODE")|g" \
    -e "s|__ROOK_CEPH_MGR_COUNT__|$(escape_sed "$ROOK_CEPH_MGR_COUNT")|g" \
    -e "s|__ROOK_CEPH_DASHBOARD_ENABLED__|$(escape_sed "$ROOK_CEPH_DASHBOARD_ENABLED")|g" \
    -e "s|__ROOK_CEPH_DASHBOARD_SSL__|$(escape_sed "$ROOK_CEPH_DASHBOARD_SSL")|g" \
    "$CLUSTER_TEMPLATE" | sed "/__ROOK_CEPH_DEVICES__/{
      r $devices_rendered
      d
    }" >"$cluster_rendered"

  echo "应用 CephCluster: ${ROOK_CEPH_NAMESPACE}/rook-ceph"
  kubectl apply -f "$cluster_rendered"
  wait_ceph_cluster
else
  echo "跳过 CephCluster 安装。"
fi

if [[ "$ROOK_CEPH_INSTALL_FILESYSTEM" == "true" ]]; then
  sed \
    -e "s|__ROOK_CEPH_NAMESPACE__|$(escape_sed "$ROOK_CEPH_NAMESPACE")|g" \
    -e "s|__ROOK_CEPH_FS_NAME__|$(escape_sed "$ROOK_CEPH_FS_NAME")|g" \
    -e "s|__ROOK_CEPH_FS_MDS_ACTIVE_COUNT__|$(escape_sed "$ROOK_CEPH_FS_MDS_ACTIVE_COUNT")|g" \
    -e "s|__ROOK_CEPH_FS_MDS_ACTIVE_STANDBY__|$(escape_sed "$ROOK_CEPH_FS_MDS_ACTIVE_STANDBY")|g" \
    -e "s|__ROOK_CEPH_FS_METADATA_POOL_SIZE__|$(escape_sed "$ROOK_CEPH_FS_METADATA_POOL_SIZE")|g" \
    -e "s|__ROOK_CEPH_FS_DATA_POOL_SIZE__|$(escape_sed "$ROOK_CEPH_FS_DATA_POOL_SIZE")|g" \
    -e "s|__ROOK_CEPH_FS_STORAGE_CLASS__|$(escape_sed "$ROOK_CEPH_FS_STORAGE_CLASS")|g" \
    -e "s|__ROOK_CEPH_FS_RECLAIM_POLICY__|$(escape_sed "$ROOK_CEPH_FS_RECLAIM_POLICY")|g" \
    -e "s|__ROOK_CEPH_FS_ALLOW_VOLUME_EXPANSION__|$(escape_sed "$ROOK_CEPH_FS_ALLOW_VOLUME_EXPANSION")|g" \
    -e "s|__ROOK_CEPH_REPLICATED_REQUIRE_SAFE_REPLICA_SIZE__|$(escape_sed "$ROOK_CEPH_REPLICATED_REQUIRE_SAFE_REPLICA_SIZE")|g" \
    "$FILESYSTEM_TEMPLATE" >"$filesystem_rendered"

  echo "应用 CephFS 和 StorageClass: $ROOK_CEPH_FS_STORAGE_CLASS"
  kubectl apply -f "$filesystem_rendered"
  wait_ceph_filesystem
else
  echo "跳过 CephFS 安装。"
fi

if [[ "$ROOK_CEPH_INSTALL_OBJECT_STORE" == "true" ]]; then
  sed \
    -e "s|__ROOK_CEPH_NAMESPACE__|$(escape_sed "$ROOK_CEPH_NAMESPACE")|g" \
    -e "s|__ROOK_CEPH_OBJECT_STORE_NAME__|$(escape_sed "$ROOK_CEPH_OBJECT_STORE_NAME")|g" \
    -e "s|__ROOK_CEPH_OBJECT_STORE_METADATA_POOL_SIZE__|$(escape_sed "$ROOK_CEPH_OBJECT_STORE_METADATA_POOL_SIZE")|g" \
    -e "s|__ROOK_CEPH_OBJECT_STORE_DATA_POOL_SIZE__|$(escape_sed "$ROOK_CEPH_OBJECT_STORE_DATA_POOL_SIZE")|g" \
    -e "s|__ROOK_CEPH_OBJECT_STORE_GATEWAY_INSTANCES__|$(escape_sed "$ROOK_CEPH_OBJECT_STORE_GATEWAY_INSTANCES")|g" \
    -e "s|__ROOK_CEPH_OBJECT_STORE_GATEWAY_PORT__|$(escape_sed "$ROOK_CEPH_OBJECT_STORE_GATEWAY_PORT")|g" \
    -e "s|__ROOK_CEPH_OBJECT_STORE_PRESERVE_POOLS_ON_DELETE__|$(escape_sed "$ROOK_CEPH_OBJECT_STORE_PRESERVE_POOLS_ON_DELETE")|g" \
    -e "s|__ROOK_CEPH_BUCKET_STORAGE_CLASS__|$(escape_sed "$ROOK_CEPH_BUCKET_STORAGE_CLASS")|g" \
    -e "s|__ROOK_CEPH_BUCKET_RECLAIM_POLICY__|$(escape_sed "$ROOK_CEPH_BUCKET_RECLAIM_POLICY")|g" \
    -e "s|__ROOK_CEPH_OBJECT_USER_NAME__|$(escape_sed "$ROOK_CEPH_OBJECT_USER_NAME")|g" \
    -e "s|__ROOK_CEPH_OBJECT_USER_DISPLAY_NAME__|$(escape_sed "$ROOK_CEPH_OBJECT_USER_DISPLAY_NAME")|g" \
    -e "s|__ROOK_CEPH_REPLICATED_REQUIRE_SAFE_REPLICA_SIZE__|$(escape_sed "$ROOK_CEPH_REPLICATED_REQUIRE_SAFE_REPLICA_SIZE")|g" \
    "$OBJECTSTORE_TEMPLATE" >"$objectstore_rendered"

  echo "应用 RGW Object Store 和 Bucket StorageClass: $ROOK_CEPH_OBJECT_STORE_NAME"
  kubectl apply -f "$objectstore_rendered"
  wait_object_store
else
  echo "跳过 RGW Object Store 安装。"
fi

echo "当前 Rook Ceph Pod 状态"
kubectl -n "$ROOK_CEPH_NAMESPACE" get pods -o wide

echo "当前 Ceph CR 状态"
kubectl -n "$ROOK_CEPH_NAMESPACE" get cephcluster,cephfilesystem,cephobjectstore,cephobjectstoreuser || true

echo "当前 StorageClass"
kubectl get storageclass | grep -E "$ROOK_CEPH_FS_STORAGE_CLASS|$ROOK_CEPH_BUCKET_STORAGE_CLASS" || true

echo "RGW 集群内访问地址:"
echo "  http://rook-ceph-rgw-${ROOK_CEPH_OBJECT_STORE_NAME}.${ROOK_CEPH_NAMESPACE}.svc:${ROOK_CEPH_OBJECT_STORE_GATEWAY_PORT}"
echo "RGW 管理用户 Secret:"
echo "  rook-ceph-object-user-${ROOK_CEPH_OBJECT_STORE_NAME}-${ROOK_CEPH_OBJECT_USER_NAME}"

echo "完成"
