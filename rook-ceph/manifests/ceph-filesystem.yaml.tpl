apiVersion: ceph.rook.io/v1
kind: CephFilesystem
metadata:
  name: __ROOK_CEPH_FS_NAME__
  namespace: __ROOK_CEPH_NAMESPACE__
spec:
  metadataPool:
    replicated:
      size: __ROOK_CEPH_FS_METADATA_POOL_SIZE__
      requireSafeReplicaSize: __ROOK_CEPH_REPLICATED_REQUIRE_SAFE_REPLICA_SIZE__
  dataPools:
    - name: replicated
      replicated:
        size: __ROOK_CEPH_FS_DATA_POOL_SIZE__
        requireSafeReplicaSize: __ROOK_CEPH_REPLICATED_REQUIRE_SAFE_REPLICA_SIZE__
  preserveFilesystemOnDelete: true
  metadataServer:
    activeCount: __ROOK_CEPH_FS_MDS_ACTIVE_COUNT__
    activeStandby: __ROOK_CEPH_FS_MDS_ACTIVE_STANDBY__
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: __ROOK_CEPH_FS_STORAGE_CLASS__
provisioner: __ROOK_CEPH_NAMESPACE__.cephfs.csi.ceph.com
parameters:
  clusterID: __ROOK_CEPH_NAMESPACE__
  fsName: __ROOK_CEPH_FS_NAME__
  pool: __ROOK_CEPH_FS_NAME__-replicated
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: __ROOK_CEPH_NAMESPACE__
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: __ROOK_CEPH_NAMESPACE__
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-cephfs-node
  csi.storage.k8s.io/node-stage-secret-namespace: __ROOK_CEPH_NAMESPACE__
reclaimPolicy: __ROOK_CEPH_FS_RECLAIM_POLICY__
allowVolumeExpansion: __ROOK_CEPH_FS_ALLOW_VOLUME_EXPANSION__
