# OrbStack 验证记录

验证日期：2026-06-05

## 验证环境

```text
ubuntu-1  Ubuntu 24.04.4 LTS  arm64  cgroup v2  192.168.139.137
ubuntu-2  Ubuntu 24.04.4 LTS  arm64  cgroup v2  192.168.139.164
ubuntu-3  Ubuntu 24.04.4 LTS  arm64  cgroup v2  192.168.139.174
```

K3s：

```text
v1.35.5+k3s1
3 control-plane + embedded etcd
containerd 2.2.3-k3s1
```

RabbitMQ：

```text
RabbitMQ image: rabbitmq:4.3.1-management
RabbitMQ Cluster Operator: ghcr.io/rabbitmq/cluster-operator:2.21.0
StorageClass: local-path
```

## 离线资源

本地生成的离线资源：

```text
rabbitmq/artifacts/operator/cluster-operator-v2.21.0.yml
rabbitmq/artifacts/images/rabbitmq-4.3.1-management.tar              257M
rabbitmq/artifacts/images/ghcr.io-rabbitmq-cluster-operator-2.21.0.tar 79M
```

验证中发现 Docker daemon 拉取 GHCR 镜像可能长时间卡住，改用 `crane` 可以稳定生成 tar：

```bash
RABBITMQ_IMAGE_DOWNLOAD_TOOL=crane \
CRANE_BIN=/tmp/k3s-ha-bin/crane \
bash rabbitmq/scripts/download-rabbitmq-images.sh rabbitmq/config.example.env
```

## 镜像导入验证

执行：

```bash
KUBECONFIG=/tmp/k3s-ubuntu-rabbitmq.yaml \
RABBITMQ_IMAGE_TAR=./rabbitmq/artifacts/images/rabbitmq-4.3.1-management.tar \
RABBITMQ_OPERATOR_IMAGE_TAR=./rabbitmq/artifacts/images/ghcr.io-rabbitmq-cluster-operator-2.21.0.tar \
RABBITMQ_NODE_SSH_HOSTS=192.168.139.137,192.168.139.164,192.168.139.174 \
RABBITMQ_NODE_NAMES=ubuntu-1,ubuntu-2,ubuntu-3 \
RABBITMQ_RESTART_K3S_AFTER_IMAGE_UPLOAD=true \
RABBITMQ_RESET_K3S_IMAGE_CACHE=true \
bash rabbitmq/scripts/upload-rabbitmq-images.sh rabbitmq/config.example.env
```

三台节点均确认导入：

```text
docker.io/library/rabbitmq:4.3.1-management
ghcr.io/rabbitmq/cluster-operator:2.21.0
```

验证中发现如果直接 `scp` 到 `/var/lib/rancher/k3s/agent/images/` 的最终文件名，K3s 启动或扫描 images 目录时可能读到未传输完成的 tar，日志出现 `short read` 或 `unexpected EOF`。脚本已修复为先上传 `.uploading-*.tmp`，传完后再 `mv` 为最终 tar。

## 离线部署验证

执行：

```bash
KUBECONFIG=/tmp/k3s-ubuntu-rabbitmq.yaml \
RABBITMQ_OPERATOR_MANIFEST=./rabbitmq/artifacts/operator/cluster-operator-v2.21.0.yml \
RABBITMQ_OPERATOR_IMAGE_PULL_POLICY=Never \
bash rabbitmq/scripts/deploy-rabbitmq.sh rabbitmq/config.example.env
```

这里使用 `Never` 是为了严格验证镜像已经通过 K3s images 目录导入。常规生产配置默认使用 `IfNotPresent`。

验证结果：

```text
rabbitmq-server-0  1/1 Running  ubuntu-2
rabbitmq-server-1  1/1 Running  ubuntu-3
rabbitmq-server-2  1/1 Running  ubuntu-1
```

Pod 事件确认镜像来自本地导入：

```text
Container image "rabbitmq:4.3.1-management" already present on machine and can be accessed by the pod
Container image "ghcr.io/rabbitmq/cluster-operator:2.21.0" already present on machine and can be accessed by the pod
```

集群状态：

```text
Running Nodes
rabbit@rabbitmq-server-0.rabbitmq-nodes.rabbitmq
rabbit@rabbitmq-server-1.rabbitmq-nodes.rabbitmq
rabbit@rabbitmq-server-2.rabbitmq-nodes.rabbitmq
```

## 存储与节点亲和验证

PVC 均绑定 `local-path` PV：

```text
persistence-rabbitmq-server-0  Bound  20Gi  local-path
persistence-rabbitmq-server-1  Bound  20Gi  local-path
persistence-rabbitmq-server-2  Bound  20Gi  local-path
```

PV nodeAffinity 分别绑定到 Pod 所在节点，删除 Pod 后会回到原节点挂载原 PVC。

## Quorum 队列验证

创建测试队列：

```bash
user=$(kubectl -n rabbitmq get secret rabbitmq-default-user -o jsonpath='{.data.username}' | base64 -d)
pass=$(kubectl -n rabbitmq get secret rabbitmq-default-user -o jsonpath='{.data.password}' | base64 -d)
kubectl -n rabbitmq exec rabbitmq-server-0 -- \
  rabbitmqadmin --username "$user" --password "$pass" \
  declare queue --name codex_quorum_test --type quorum --durable true --non-interactive
```

队列类型：

```text
codex_quorum_test  quorum  durable=true
```

`rabbitmq-queues quorum_status codex_quorum_test` 显示 3 个 voter：

```text
rabbitmq-server-0  follower  voter
rabbitmq-server-1  follower  voter
rabbitmq-server-2  leader    voter
```

## 故障恢复验证

删除一个 RabbitMQ Pod：

```bash
kubectl -n rabbitmq delete pod rabbitmq-server-0
```

恢复结果：

```text
rabbitmq-server-0  1/1 Running  ubuntu-2
rabbitmq-server-1  1/1 Running  ubuntu-3
rabbitmq-server-2  1/1 Running  ubuntu-1
```

quorum 队列恢复为 3 voter。

## 注意事项

RabbitMQ Cluster Operator 在 Pod 重建期间可能尝试执行 `rabbitmqctl enable_feature_flag all`，如果此时集群节点还在恢复，`RabbitmqCluster.status.conditions[ReconcileSuccess]` 可能出现 `False:FailedCLICommand`。本次验证中 RabbitMQ Pod、`cluster_status`、`quorum_status` 均恢复正常，`quorumStatus=ok`。

生产监控不要只看 `ReconcileSuccess` 一个字段，应同时检查：

```text
Pod Ready
cluster_status Running Nodes
quorum_status
quorumStatus=ok
```

删除 RabbitMQ 时不要直接先删 Operator。建议顺序：

```bash
kubectl delete rabbitmqcluster rabbitmq -n rabbitmq
kubectl delete namespace rabbitmq
kubectl delete -f rabbitmq/artifacts/operator/cluster-operator-v2.21.0.yml
```

验证环境如果强制删除 namespace，可能留下 PV finalizer，需要人工清理测试残留。
