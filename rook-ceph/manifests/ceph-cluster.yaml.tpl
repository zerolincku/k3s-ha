apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: __ROOK_CEPH_NAMESPACE__
spec:
  cephVersion:
    image: __ROOK_CEPH_CEPH_IMAGE__
    allowUnsupported: false
  dataDirHostPath: __ROOK_CEPH_DATA_DIR_HOST_PATH__
  skipUpgradeChecks: false
  continueUpgradeAfterChecksEvenIfNotHealthy: false
  mon:
    count: __ROOK_CEPH_MON_COUNT__
    allowMultiplePerNode: __ROOK_CEPH_ALLOW_MULTIPLE_PER_NODE__
  mgr:
    count: __ROOK_CEPH_MGR_COUNT__
    modules:
      - name: pg_autoscaler
        enabled: true
  dashboard:
    enabled: __ROOK_CEPH_DASHBOARD_ENABLED__
    ssl: __ROOK_CEPH_DASHBOARD_SSL__
  crashCollector:
    disable: false
  cleanupPolicy:
    confirmation: ""
  monitoring:
    enabled: false
  healthCheck:
    daemonHealth:
      mon:
        disabled: false
        interval: 45s
      osd:
        disabled: false
        interval: 60s
      status:
        disabled: false
        interval: 60s
    livenessProbe:
      mon:
        disabled: false
      mgr:
        disabled: false
      osd:
        disabled: false
  storage:
    useAllNodes: __ROOK_CEPH_USE_ALL_NODES__
    useAllDevices: __ROOK_CEPH_USE_ALL_DEVICES__
    config:
      osdsPerDevice: "1"
    devices:
__ROOK_CEPH_DEVICES__
