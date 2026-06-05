# OrbStack 验证记录

验证日期：2026-06-05

## 验证环境

| 节点 | 发行版 | 架构 | cgroup | 节点 IP | SSH 地址 |
| --- | --- | --- | --- | --- | --- |
| ubuntu-1 | Ubuntu 24.04.4 LTS | arm64 | v2 | 192.168.139.124 | ubuntu-1@orb |
| ubuntu-2 | Ubuntu 24.04.4 LTS | arm64 | v2 | 192.168.139.159 | ubuntu-2@orb |
| ubuntu-3 | Ubuntu 24.04.4 LTS | arm64 | v2 | 192.168.139.107 | ubuntu-3@orb |

OrbStack 机器的节点 IP 可以互通，但 SSH 登录使用 `root@<machine>@orb`。因此配置中使用：

```bash
MASTER1_HOST=192.168.139.124
MASTER1_SSH_HOST=ubuntu-1@orb
```

`MASTER*_HOST` 用于 K3s 集群通信，`MASTER*_SSH_HOST` 用于部署脚本 SSH 登录。

## 执行结果

使用 `k3s/scripts/deploy-k3s-ha.sh` 完成 3 master embedded etcd 集群部署，K3s 版本为：

```text
v1.35.5+k3s1
```

节点验证结果：

```text
NAME       STATUS   ROLES                VERSION        ARCH    CGROUP-VERSION
ubuntu-1   Ready    control-plane,etcd   v1.35.5+k3s1   arm64   v2
ubuntu-2   Ready    control-plane,etcd   v1.35.5+k3s1   arm64   v2
ubuntu-3   Ready    control-plane,etcd   v1.35.5+k3s1   arm64   v2
```

API 健康检查：

```text
kubectl get --raw=/readyz
ok
```

CoreDNS 和 metrics-server 在补齐可访问镜像后可以正常运行：

```text
kube-system   coredns          1/1   Running
kube-system   metrics-server   1/1   Running
```

## 发现的问题

OrbStack VM 内无法稳定访问 Docker Hub：

```text
registry-1.docker.io
auth.docker.io
EOF
tls: handshake failure
```

这会导致默认 K3s 系统组件镜像拉取失败。验证过程中通过 `registry.k8s.io` 拉取并本地标记了 `pause`、`coredns`、`metrics-server` 镜像后，对应组件恢复正常。

`local-path-provisioner` 仍然依赖：

```text
rancher/local-path-provisioner:v0.0.36
```

在 Docker Hub 不可用且没有官方 airgap 包或内网 registry 的情况下，它会继续 `ImagePullBackOff`。

## 结论

- 3 master K3s embedded etcd 部署流程验证通过。
- `MASTER*_SSH_HOST` 与 `MASTER*_HOST` 分离是必要能力，已补入脚本和配置模板。
- 在线部署不能假设 Docker Hub 稳定可用。
- 生产环境建议优先使用 K3s airgap 包，或准备完整同步 K3s 系统镜像的内网 registry。
- VIP、HAProxy、Ingress、NodePort 与 K3s 集群部署可以解耦，K3s 可先独立部署并验证控制面健康。

## 完全离线重建验证

验证日期：2026-06-05

第二轮验证先在三台节点执行官方卸载脚本，并清理：

```text
/etc/rancher/k3s
/var/lib/rancher/k3s
/opt/k3s-airgap
```

然后在本机通过代理下载 `v1.35.5+k3s1` 的 arm64 离线资源：

```bash
K3S_ARCH=arm64 ARTIFACT_DIR=/tmp/k3s-ha-offline-test \
bash k3s/scripts/download-k3s-assets.sh k3s/config.example.env

K3S_ARCH=arm64 ARTIFACT_DIR=/tmp/k3s-ha-offline-test \
bash k3s/scripts/download-k3s-images.sh k3s/config.example.env
```

手动传输到每台节点：

```text
/tmp/k3s-offline/k3s-arm64
/tmp/k3s-offline/install.sh
/tmp/k3s-offline/k3s-airgap-images-arm64.tar.zst
```

部署时使用远端预置资源：

```bash
K3S_AIRGAP=true
K3S_ASSETS_PRELOADED=true
K3S_BINARY_ARM64=/tmp/k3s-offline/k3s-arm64
K3S_INSTALL_SCRIPT=/tmp/k3s-offline/install.sh
K3S_IMAGE_TAR_ARM64=/tmp/k3s-offline/k3s-airgap-images-arm64.tar.zst
```

部署日志确认没有在线下载 K3s：

```text
Skipping k3s download and verify
```

最终结果：

```text
NAME       STATUS   ROLES                VERSION        ARCH    CGROUP-VERSION
ubuntu-1   Ready    control-plane,etcd   v1.35.5+k3s1   arm64   v2
ubuntu-2   Ready    control-plane,etcd   v1.35.5+k3s1   arm64   v2
ubuntu-3   Ready    control-plane,etcd   v1.35.5+k3s1   arm64   v2
```

API 健康检查：

```text
kubectl get --raw=/readyz
ok
```

系统组件全部运行：

```text
coredns                  1/1   Running
local-path-provisioner   1/1   Running
metrics-server           1/1   Running
```

每台节点的镜像归档位置：

```text
/var/lib/rancher/k3s/agent/images/k3s-airgap-images-arm64.tar.zst
```

每台节点均可看到 airgap 归档导入后的系统镜像：

```text
docker.io/rancher/local-path-provisioner:v0.0.36
docker.io/rancher/mirrored-coredns-coredns:1.14.3
docker.io/rancher/mirrored-library-busybox:1.37.0
docker.io/rancher/mirrored-metrics-server:v0.8.1
docker.io/rancher/mirrored-pause:3.6
```
