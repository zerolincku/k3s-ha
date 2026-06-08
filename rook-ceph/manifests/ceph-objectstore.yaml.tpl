apiVersion: ceph.rook.io/v1
kind: CephObjectStore
metadata:
  name: __ROOK_CEPH_OBJECT_STORE_NAME__
  namespace: __ROOK_CEPH_NAMESPACE__
spec:
  metadataPool:
    replicated:
      size: __ROOK_CEPH_OBJECT_STORE_METADATA_POOL_SIZE__
      requireSafeReplicaSize: __ROOK_CEPH_REPLICATED_REQUIRE_SAFE_REPLICA_SIZE__
  dataPool:
    replicated:
      size: __ROOK_CEPH_OBJECT_STORE_DATA_POOL_SIZE__
      requireSafeReplicaSize: __ROOK_CEPH_REPLICATED_REQUIRE_SAFE_REPLICA_SIZE__
  preservePoolsOnDelete: __ROOK_CEPH_OBJECT_STORE_PRESERVE_POOLS_ON_DELETE__
  gateway:
    port: __ROOK_CEPH_OBJECT_STORE_GATEWAY_PORT__
    instances: __ROOK_CEPH_OBJECT_STORE_GATEWAY_INSTANCES__
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: __ROOK_CEPH_BUCKET_STORAGE_CLASS__
provisioner: __ROOK_CEPH_NAMESPACE__.ceph.rook.io/bucket
reclaimPolicy: __ROOK_CEPH_BUCKET_RECLAIM_POLICY__
parameters:
  objectStoreName: __ROOK_CEPH_OBJECT_STORE_NAME__
  objectStoreNamespace: __ROOK_CEPH_NAMESPACE__
---
apiVersion: ceph.rook.io/v1
kind: CephObjectStoreUser
metadata:
  name: __ROOK_CEPH_OBJECT_USER_NAME__
  namespace: __ROOK_CEPH_NAMESPACE__
spec:
  store: __ROOK_CEPH_OBJECT_STORE_NAME__
  displayName: __ROOK_CEPH_OBJECT_USER_DISPLAY_NAME__
