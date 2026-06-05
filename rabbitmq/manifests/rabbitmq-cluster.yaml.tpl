apiVersion: v1
kind: Namespace
metadata:
  name: __RABBITMQ_NAMESPACE__
---
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: __RABBITMQ_CLUSTER_NAME__
  namespace: __RABBITMQ_NAMESPACE__
spec:
  replicas: __RABBITMQ_REPLICAS__
  image: __RABBITMQ_IMAGE__
  autoEnableAllFeatureFlags: __RABBITMQ_AUTO_ENABLE_ALL_FEATURE_FLAGS__
  service:
    type: ClusterIP
  persistence:
    storageClassName: __RABBITMQ_STORAGE_CLASS__
    storage: __RABBITMQ_STORAGE__
  resources:
    requests:
      cpu: __RABBITMQ_CPU_REQUEST__
      memory: __RABBITMQ_MEMORY_REQUEST__
    limits:
      cpu: __RABBITMQ_CPU_LIMIT__
      memory: __RABBITMQ_MEMORY_LIMIT__
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app.kubernetes.io/name: __RABBITMQ_CLUSTER_NAME__
              app.kubernetes.io/component: rabbitmq
          topologyKey: kubernetes.io/hostname
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
    - key: node-role.kubernetes.io/master
      operator: Exists
      effect: NoSchedule
  rabbitmq:
    additionalConfig: |
      default_queue_type = __RABBITMQ_DEFAULT_QUEUE_TYPE__
      vm_memory_high_watermark.relative = __RABBITMQ_VM_MEMORY_HIGH_WATERMARK__
      disk_free_limit.absolute = __RABBITMQ_DISK_FREE_LIMIT__
