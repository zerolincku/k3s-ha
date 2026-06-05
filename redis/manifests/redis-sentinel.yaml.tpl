apiVersion: v1
kind: Service
metadata:
  name: redis-headless
  namespace: __REDIS_NAMESPACE__
  labels:
    app.kubernetes.io/name: redis
    app.kubernetes.io/component: data
spec:
  clusterIP: None
  publishNotReadyAddresses: true
  selector:
    app.kubernetes.io/name: redis
    app.kubernetes.io/component: data
  ports:
    - name: redis
      port: 6379
      targetPort: redis
---
apiVersion: v1
kind: Service
metadata:
  name: redis-sentinel
  namespace: __REDIS_NAMESPACE__
  labels:
    app.kubernetes.io/name: redis
    app.kubernetes.io/component: sentinel
spec:
  selector:
    app.kubernetes.io/name: redis
    app.kubernetes.io/component: sentinel
  ports:
    - name: sentinel
      port: 26379
      targetPort: sentinel
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-scripts
  namespace: __REDIS_NAMESPACE__
  labels:
    app.kubernetes.io/name: redis
data:
  redis-entrypoint.sh: |
    #!/bin/sh
    set -eu

    log() {
      echo "[redis] $*"
    }

    ordinal="${HOSTNAME##*-}"
    self_fqdn="${HOSTNAME}.redis-headless.${POD_NAMESPACE}.svc.cluster.local"
    default_master="redis-0.redis-headless.${POD_NAMESPACE}.svc.cluster.local"
    reported_host=""
    reported_port="6379"

    sentinel_result="$(redis-cli -h redis-sentinel -p 26379 --raw SENTINEL get-master-addr-by-name "${REDIS_MASTER_NAME}" 2>/dev/null || true)"
    if [ -n "${sentinel_result}" ]; then
      reported_host="$(printf '%s\n' "${sentinel_result}" | sed -n '1p')"
      reported_port="$(printf '%s\n' "${sentinel_result}" | sed -n '2p')"
    fi

    replica_args=""
    if [ -n "${reported_host}" ]; then
      case "${reported_host}" in
        "${HOSTNAME}"|"${self_fqdn}"|"${POD_IP}")
          log "Sentinel 当前 master 指向本 Pod，按 master 启动"
          ;;
        *)
          log "Sentinel 当前 master: ${reported_host}:${reported_port}，按 replica 启动"
          replica_args="--replicaof ${reported_host} ${reported_port}"
          ;;
      esac
    elif [ "${ordinal}" = "0" ]; then
      log "没有发现 Sentinel master 信息，redis-0 按初始 master 启动"
    else
      log "没有发现 Sentinel master 信息，${HOSTNAME} 按 redis-0 replica 启动"
      replica_args="--replicaof ${default_master} 6379"
    fi

    exec redis-server \
      --port 6379 \
      --bind 0.0.0.0 \
      --protected-mode no \
      --dir /data \
      --appendonly no \
      --save "" \
      --maxmemory "${REDIS_MAXMEMORY}" \
      --maxmemory-policy "${REDIS_MAXMEMORY_POLICY}" \
      --requirepass "${REDIS_PASSWORD}" \
      --masterauth "${REDIS_PASSWORD}" \
      ${replica_args}
  sentinel-entrypoint.sh: |
    #!/bin/sh
    set -eu

    log() {
      echo "[sentinel] $*"
    }

    mkdir -p /data
    default_master="redis-0.redis-headless.${POD_NAMESPACE}.svc.cluster.local"
    monitor_host="${default_master}"
    monitor_port="6379"

    sentinel_result="$(redis-cli -h redis-sentinel -p 26379 --raw SENTINEL get-master-addr-by-name "${REDIS_MASTER_NAME}" 2>/dev/null || true)"
    if [ -n "${sentinel_result}" ]; then
      candidate_host="$(printf '%s\n' "${sentinel_result}" | sed -n '1p')"
      candidate_port="$(printf '%s\n' "${sentinel_result}" | sed -n '2p')"
      if [ -n "${candidate_host}" ] && [ -n "${candidate_port}" ]; then
        monitor_host="${candidate_host}"
        monitor_port="${candidate_port}"
      fi
    fi

    log "监控 master: ${monitor_host}:${monitor_port}"

    cat >/data/sentinel.conf <<EOF
    port 26379
    bind 0.0.0.0
    protected-mode no
    dir /data
    sentinel resolve-hostnames yes
    sentinel announce-hostnames yes
    sentinel monitor ${REDIS_MASTER_NAME} ${monitor_host} ${monitor_port} ${REDIS_SENTINEL_QUORUM}
    sentinel auth-pass ${REDIS_MASTER_NAME} ${REDIS_PASSWORD}
    sentinel down-after-milliseconds ${REDIS_MASTER_NAME} ${REDIS_SENTINEL_DOWN_AFTER_MS}
    sentinel failover-timeout ${REDIS_MASTER_NAME} ${REDIS_SENTINEL_FAILOVER_TIMEOUT_MS}
    sentinel parallel-syncs ${REDIS_MASTER_NAME} ${REDIS_SENTINEL_PARALLEL_SYNCS}
    EOF

    exec redis-server /data/sentinel.conf --sentinel
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: __REDIS_NAMESPACE__
  labels:
    app.kubernetes.io/name: redis
    app.kubernetes.io/component: data
spec:
  serviceName: redis-headless
  replicas: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: redis
      app.kubernetes.io/component: data
  template:
    metadata:
      labels:
        app.kubernetes.io/name: redis
        app.kubernetes.io/component: data
    spec:
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
        - key: node-role.kubernetes.io/master
          operator: Exists
          effect: NoSchedule
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app.kubernetes.io/name: redis
                    app.kubernetes.io/component: data
                topologyKey: kubernetes.io/hostname
      containers:
        - name: redis
          image: __REDIS_IMAGE__
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - /opt/redis-scripts/redis-entrypoint.sh
          ports:
            - name: redis
              containerPort: 6379
          env:
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-auth
                  key: password
            - name: REDIS_MASTER_NAME
              value: "__REDIS_MASTER_NAME__"
            - name: REDIS_MAXMEMORY
              value: "__REDIS_MAXMEMORY__"
            - name: REDIS_MAXMEMORY_POLICY
              value: "__REDIS_MAXMEMORY_POLICY__"
          readinessProbe:
            exec:
              command:
                - /bin/sh
                - -ec
                - redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping | grep -q PONG
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 3
          livenessProbe:
            exec:
              command:
                - /bin/sh
                - -ec
                - redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping | grep -q PONG
            initialDelaySeconds: 20
            periodSeconds: 10
            timeoutSeconds: 3
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
          volumeMounts:
            - name: data
              mountPath: /data
            - name: scripts
              mountPath: /opt/redis-scripts
      volumes:
        - name: data
          emptyDir: {}
        - name: scripts
          configMap:
            name: redis-scripts
            defaultMode: 0755
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: sentinel
  namespace: __REDIS_NAMESPACE__
  labels:
    app.kubernetes.io/name: redis
    app.kubernetes.io/component: sentinel
spec:
  serviceName: redis-sentinel
  replicas: 3
  selector:
    matchLabels:
      app.kubernetes.io/name: redis
      app.kubernetes.io/component: sentinel
  template:
    metadata:
      labels:
        app.kubernetes.io/name: redis
        app.kubernetes.io/component: sentinel
    spec:
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
        - key: node-role.kubernetes.io/master
          operator: Exists
          effect: NoSchedule
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels:
                    app.kubernetes.io/name: redis
                    app.kubernetes.io/component: sentinel
                topologyKey: kubernetes.io/hostname
      containers:
        - name: sentinel
          image: __REDIS_IMAGE__
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - /opt/redis-scripts/sentinel-entrypoint.sh
          ports:
            - name: sentinel
              containerPort: 26379
          env:
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-auth
                  key: password
            - name: REDIS_MASTER_NAME
              value: "__REDIS_MASTER_NAME__"
            - name: REDIS_SENTINEL_QUORUM
              value: "__REDIS_SENTINEL_QUORUM__"
            - name: REDIS_SENTINEL_DOWN_AFTER_MS
              value: "__REDIS_SENTINEL_DOWN_AFTER_MS__"
            - name: REDIS_SENTINEL_FAILOVER_TIMEOUT_MS
              value: "__REDIS_SENTINEL_FAILOVER_TIMEOUT_MS__"
            - name: REDIS_SENTINEL_PARALLEL_SYNCS
              value: "__REDIS_SENTINEL_PARALLEL_SYNCS__"
          readinessProbe:
            exec:
              command:
                - /bin/sh
                - -ec
                - redis-cli -p 26379 ping | grep -q PONG
            initialDelaySeconds: 5
            periodSeconds: 5
            timeoutSeconds: 3
          livenessProbe:
            exec:
              command:
                - /bin/sh
                - -ec
                - redis-cli -p 26379 ping | grep -q PONG
            initialDelaySeconds: 20
            periodSeconds: 10
            timeoutSeconds: 3
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          volumeMounts:
            - name: data
              mountPath: /data
            - name: scripts
              mountPath: /opt/redis-scripts
      volumes:
        - name: data
          emptyDir: {}
        - name: scripts
          configMap:
            name: redis-scripts
            defaultMode: 0755
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: redis
  namespace: __REDIS_NAMESPACE__
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: redis
      app.kubernetes.io/component: data
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: redis-sentinel
  namespace: __REDIS_NAMESPACE__
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: redis
      app.kubernetes.io/component: sentinel
