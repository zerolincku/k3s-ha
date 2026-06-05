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

## Ubuntu Jammy 重新验证

验证日期：2026-06-05

用户重建了 3 台 OrbStack VM：

| 节点 | 发行版 | 架构 | cgroup | 节点 IP | SSH 地址 |
| --- | --- | --- | --- | --- | --- |
| u-1 | Ubuntu 22.04.5 LTS | arm64 | v2 | 192.168.139.219 | u-1@orb |
| u-2 | Ubuntu 22.04.5 LTS | arm64 | v2 | 192.168.139.229 | u-2@orb |
| u-3 | Ubuntu 22.04.5 LTS | arm64 | v2 | 192.168.139.138 | u-3@orb |

检查结果：

```text
stat -fc %T /sys/fs/cgroup
cgroup2fs

mount | grep cgroup
none on /sys/fs/cgroup type cgroup2
```

结论：这三台不是 cgroup v1，而是 cgroup v2。

按完全离线流程重新下载 arm64 资源、手动传输到 `/tmp/k3s-offline/`，并使用：

```bash
K3S_AIRGAP=true
K3S_ASSETS_PRELOADED=true
K3S_BINARY_ARM64=/tmp/k3s-offline/k3s-arm64
K3S_INSTALL_SCRIPT=/tmp/k3s-offline/install.sh
K3S_IMAGE_TAR_ARM64=/tmp/k3s-offline/k3s-airgap-images-arm64.tar.zst
```

最终结果：

```text
NAME   STATUS   ROLES                VERSION        ARCH    CGROUP-VERSION
u-1    Ready    control-plane,etcd   v1.35.5+k3s1   arm64   v2
u-2    Ready    control-plane,etcd   v1.35.5+k3s1   arm64   v2
u-3    Ready    control-plane,etcd   v1.35.5+k3s1   arm64   v2
```

系统组件：

```text
coredns                  1/1   Running
local-path-provisioner   1/1   Running
metrics-server           1/1   Running
```

这个 jammy 镜像缺少以下命令：

```text
iptables
iptables-save
ip6tables
ip6tables-save
conntrack
socat
```

K3s 核心验证仍然通过，但生产环境不能省略这些 OS 依赖。完全离线方案需要同时准备 K3s 本体、K3s 系统镜像和 OS 依赖包。

后续脚本已调整为：缺少这些 OS 命令时默认阻断部署。只有显式设置 `IGNORE_OS_PREREQ_MISSING=true` 时，才允许在受控测试环境中继续。

## Rocky Linux 8 离线部署验证

验证日期：2026-06-05

用户创建了 3 台 OrbStack Rocky VM：

| 节点 | 发行版 | 架构 | cgroup | 节点 IP | SSH 地址 |
| --- | --- | --- | --- | --- | --- |
| rocky-1 | Rocky Linux 8.10 | arm64 | v2 | 192.168.139.244 | rocky-1@orb |
| rocky-2 | Rocky Linux 8.10 | arm64 | v2 | 192.168.139.177 | rocky-2@orb |
| rocky-3 | Rocky Linux 8.10 | arm64 | v2 | 192.168.139.236 | rocky-3@orb |

检查结果：

```text
stat -fc %T /sys/fs/cgroup
cgroup2fs
```

结论：OrbStack 内的 Rocky Linux 8.10 仍然是 cgroup v2，不是 cgroup v1。不能把 OrbStack Rocky 8 当作 cgroup v1 验证环境。

Rocky 8 最小 rootfs 初始缺少以下 OS 命令：

```text
iptables
iptables-save
ip6tables
ip6tables-save
conntrack
socat
```

按脚本策略，缺少这些命令时离线部署会被阻断。验证前先通过 Rocky 软件源补齐 OS 依赖：

```bash
dnf install -y iptables socat conntrack-tools ca-certificates curl iproute
```

然后在本机通过代理下载 `v1.35.5+k3s1` 的 arm64 离线资源：

```bash
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
export all_proxy=socks5://127.0.0.1:7890

K3S_VERSION=v1.35.5+k3s1 \
K3S_ARCH=arm64 \
ARTIFACT_DIR=/tmp/k3s-ha-rocky-offline-test \
bash k3s/scripts/download-k3s-assets.sh /tmp/k3s-ha-rocky-offline-test/rocky-download.env

K3S_VERSION=v1.35.5+k3s1 \
K3S_ARCH=arm64 \
ARTIFACT_DIR=/tmp/k3s-ha-rocky-offline-test \
bash k3s/scripts/download-k3s-images.sh /tmp/k3s-ha-rocky-offline-test/rocky-download.env
```

离线资源大小：

```text
k3s-arm64                              67M
install.sh                             37K
k3s-airgap-images-arm64.tar.zst       213M
```

部署时使用运维机本地离线资源，由脚本复制到每台 Rocky 节点：

```bash
K3S_AIRGAP=true
K3S_BINARY_ARM64=/tmp/k3s-ha-rocky-offline-test/assets/v1.35.5+k3s1/arm64/k3s-arm64
K3S_INSTALL_SCRIPT=/tmp/k3s-ha-rocky-offline-test/assets/v1.35.5+k3s1/arm64/install.sh
K3S_IMAGE_TAR_ARM64=/tmp/k3s-ha-rocky-offline-test/images/v1.35.5+k3s1/arm64/k3s-airgap-images-arm64.tar.zst
```

部署日志确认跳过 K3s 在线下载：

```text
Skipping k3s download and verify
Skipping installation of SELinux RPM
```

最终结果：

```text
NAME      STATUS   ROLES                VERSION        ARCH    CGROUP-VERSION
rocky-1   Ready    control-plane,etcd   v1.35.5+k3s1   arm64   v2
rocky-2   Ready    control-plane,etcd   v1.35.5+k3s1   arm64   v2
rocky-3   Ready    control-plane,etcd   v1.35.5+k3s1   arm64   v2
```

系统组件：

```text
coredns                  1/1   Running
local-path-provisioner   1/1   Running
metrics-server           1/1   Running
```

API 健康检查：

```text
[+]etcd ok
[+]etcd-readiness ok
readyz check passed
```

每台节点均存在离线镜像归档：

```text
/var/lib/rancher/k3s/agent/images/k3s-airgap-images-arm64.tar.zst
```

本轮结论：

- Rocky Linux 8.10 三 master embedded etcd 离线部署验证通过。
- OrbStack Rocky 8 是 cgroup v2，不能覆盖 cgroup v1 测试。
- 最小 Rocky rootfs 需要先补齐 OS 依赖；K3s 官方离线资源不包含这些 OS 包。
- 在 Rocky 8 上，K3s 安装脚本会打印 `Skipping installation of SELinux RPM`，本轮 OrbStack 环境未因 SELinux RPM 阻塞安装。
