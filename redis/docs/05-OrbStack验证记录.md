# OrbStack 验证记录

验证日期：2026-06-05

## K3s 环境

先在 3 台 OrbStack Ubuntu 24.04 VM 上按 `k3s/` 离线方案部署 K3s：

| 节点 | 发行版 | 架构 | cgroup | 节点 IP | SSH 地址 |
| --- | --- | --- | --- | --- | --- |
| ubuntu-1 | Ubuntu 24.04.4 LTS | arm64 | v2 | 192.168.139.137 | ubuntu-1@orb |
| ubuntu-2 | Ubuntu 24.04.4 LTS | arm64 | v2 | 192.168.139.164 | ubuntu-2@orb |
| ubuntu-3 | Ubuntu 24.04.4 LTS | arm64 | v2 | 192.168.139.174 | ubuntu-3@orb |

三台最小 Ubuntu rootfs 初始缺少：

```text
iptables
iptables-save
ip6tables
ip6tables-save
conntrack
socat
```

先通过 apt 补齐 OS 依赖，再使用本地 K3s 离线资源部署：

```text
k3s-arm64                              67M
install.sh                             37K
k3s-airgap-images-arm64.tar.zst       213M
```

K3s 最终状态：

```text
NAME       STATUS   ROLES                VERSION        ARCH
ubuntu-1   Ready    control-plane,etcd   v1.35.5+k3s1   arm64
ubuntu-2   Ready    control-plane,etcd   v1.35.5+k3s1   arm64
ubuntu-3   Ready    control-plane,etcd   v1.35.5+k3s1   arm64
```

系统组件：

```text
coredns                  1/1   Running
local-path-provisioner   1/1   Running
metrics-server           1/1   Running
```

API 健康检查通过：

```text
readyz check passed
```

## Redis 镜像离线准备

第一轮验证按手工方式准备 Redis 镜像：

```bash
docker pull redis:7.2.4
docker save redis:7.2.4 -o /tmp/k3s-ha-ubuntu-redis-test/redis/redis-7.2.4.tar
```

镜像包大小：

```text
redis-7.2.4.tar    136M
```

将镜像导入每台 K3s 节点：

```bash
k3s ctr images import /tmp/redis-7.2.4.tar
```

三台节点均确认存在：

```text
docker.io/library/redis:7.2.4    linux/arm64
```

第二轮验证改为使用脚本上传到 K3s 自动导入目录：

```bash
bash redis/scripts/download-redis-images.sh /tmp/k3s-ha-ubuntu-redis-test/redis-image.env

REDIS_RESET_K3S_IMAGE_CACHE=true \
REDIS_RESTART_K3S_AFTER_IMAGE_UPLOAD=true \
bash redis/scripts/upload-redis-images.sh /tmp/k3s-ha-ubuntu-redis-test/redis-image.env
```

脚本上传到每台节点：

```text
/var/lib/rancher/k3s/agent/images/redis-7.2.4.tar
```

随后逐台滚动重启 K3s，触发 images 目录自动导入。三台节点均确认导入：

```text
docker.io/library/redis:7.2.4    linux/arm64
```

实测结论：在已经运行的 K3s 节点上，镜像 tar 放入 `/var/lib/rancher/k3s/agent/images/` 后，需要重启对应节点的 `k3s` 服务才会立即触发导入。本轮通过上传脚本逐台重启验证，三台节点均恢复 Ready。

## Redis Sentinel 部署验证

使用脚本部署：

```bash
bash redis/scripts/deploy-redis-sentinel.sh /tmp/k3s-ha-ubuntu-redis-test/redis.env
```

部署结果：

```text
NAME         READY   STATUS    NODE
redis-0      1/1     Running   ubuntu-2
redis-1      1/1     Running   ubuntu-3
redis-2      1/1     Running   ubuntu-1
sentinel-0   1/1     Running   ubuntu-3
sentinel-1   1/1     Running   ubuntu-2
sentinel-2   1/1     Running   ubuntu-1
```

StatefulSet 和 PDB：

```text
statefulset.apps/redis      3/3
statefulset.apps/sentinel   3/3

poddisruptionbudget.policy/redis            minAvailable=2
poddisruptionbudget.policy/redis-sentinel   minAvailable=2
```

初始角色：

```text
redis-0   master
redis-1   slave
redis-2   slave
```

Sentinel 初始 master：

```text
redis-0.redis-headless.redis.svc.cluster.local
6379
```

通过临时客户端 Pod 写入和读取成功：

```text
SET k3s-ha-check ok
GET k3s-ha-check
ok
```

第二轮清空 Redis namespace、清理旧镜像后，使用 images 目录自动导入方式重新部署，结果仍然通过：

```text
redis-0      1/1   Running
redis-1      1/1   Running
redis-2      1/1   Running
sentinel-0   1/1   Running
sentinel-1   1/1   Running
sentinel-2   1/1   Running
```

角色：

```text
redis-0   master
redis-1   slave
redis-2   slave
```

读写验证：

```text
SET images-dir-import ok
GET images-dir-import
ok
```

## 故障转移验证

通过 Sentinel 主动触发 failover：

```bash
kubectl -n redis exec sentinel-0 -- redis-cli -p 26379 sentinel failover mymaster
```

Sentinel 切换后的 master：

```text
10.42.3.3
6379
```

刚切换完成的短时间窗口内，曾观察到 `redis-0` 和 `redis-1` 同时报 `master`。继续等待后 Sentinel 完成旧 master 重配置，最终收敛为：

```text
redis-0   slave
redis-1   master
redis-2   slave
```

故障转移后再次写入和读取成功：

```text
SET k3s-ha-failover ok
GET k3s-ha-failover
ok
```

## 结论

- Redis Sentinel 在线脚本在 K3s 3 master 集群上验证通过。
- Redis 镜像按离线手册导入到每台节点后，Pod 不需要外部拉镜像即可启动。
- 3 个 Redis Pod 和 3 个 Sentinel Pod 均成功分散到三台 K3s 节点。
- 主动故障转移验证通过，但故障转移后需要等待单 master 收敛。
- 本方案没有持久化，只适合可丢失或可重建数据。
