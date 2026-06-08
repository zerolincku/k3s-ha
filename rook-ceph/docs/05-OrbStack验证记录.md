# OrbStack 验证记录

验证时间：2026-06-05

验证目标：

```text
在 OrbStack 3 台 Ubuntu 24.04 K3s master 上，使用 loop 设备模拟数据盘，按离线路径验证 Rook Ceph、CephFS、RGW 部署流程。
```

## 环境

```text
ubuntu-1 192.168.139.137 Ubuntu 24.04.4 LTS arm64
ubuntu-2 192.168.139.164 Ubuntu 24.04.4 LTS arm64
ubuntu-3 192.168.139.174 Ubuntu 24.04.4 LTS arm64

K3s: v1.35.5+k3s1
containerd: 2.2.3-k3s1
节点角色: control-plane,etcd
```

预检结果：

```text
3 台节点 Ready
每台约 11GiB 内存、8 核
losetup 可用
无独立数据盘
宿主机可用空间约 82GiB
```

为了验证，曾在每台节点创建 6GiB loop 设备：

```text
/var/lib/rook-loop/rook-ceph-osd.img -> /dev/loop0
```

## 已验证通过

1. Rook manifest 本地下载

显式配置代理后，Rook 官方 manifest 能正常下载：

```bash
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890
export all_proxy=socks5://127.0.0.1:7890
```

未显式配置代理时，本机访问 `raw.githubusercontent.com` 出现过 TLS 主机名不匹配和下载慢的问题。

2. 离线镜像下载脚本

发现并修复两个问题：

```text
ROOK_CEPH_OBJECT_USER_DISPLAY_NAME 未加引号，source env 时会失败
镜像提取逻辑会把 CRD schema 中的 image:/value: 当成镜像名
```

修复后，`linux/arm64` 离线镜像清单包括：

```text
quay.io/ceph/ceph:v19.2.3
quay.io/cephcsi/ceph-csi-operator:v0.6.0
quay.io/cephcsi/cephcsi:v3.16.2
quay.io/csiaddons/k8s-sidecar:v0.14.0
quay.io/rook/ceph:v1.19.6
registry.k8s.io/sig-storage/csi-attacher:v4.11.0
registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.16.0
registry.k8s.io/sig-storage/csi-provisioner:v6.1.1
registry.k8s.io/sig-storage/csi-resizer:v2.1.0
registry.k8s.io/sig-storage/csi-snapshotter:v8.5.0
```

实际镜像 tar 总大小约 5.6GiB。

3. K3s images 目录上传与自动导入

上传脚本成功使用 `.uploading-*.tmp` 传输，再 `mv` 为最终 tar 文件。

三台节点重启 K3s 后都能从以下目录导入镜像：

```text
/var/lib/rancher/k3s/agent/images/
```

导入后可以在节点上看到 Rook/Ceph/CSI 镜像。

4. Rook Operator 部分部署

Rook CRD、RBAC、CSI Operator、Rook Operator 可以应用。

发现并修复：

```text
官方 operator.yaml 默认使用 docker.io/rook/ceph:v1.19.6
国内网络下 Docker Hub / CloudFront 多次 EOF
```

本目录默认改为：

```text
ROOK_CEPH_IMAGE=quay.io/rook/ceph:v1.19.6
```

部署脚本会 patch Operator Deployment 到该镜像。

## 未完成

未完成：

```text
CephCluster Ready
CephFS PVC RWX 测试
RGW bucket 创建和 S3 上传下载测试
```

停止原因：

```text
OrbStack 虚机没有独立数据盘
3 台虚机实际共享宿主机磁盘 IO
离线 tar 上传到每台约 5.6GiB
containerd 解包后每台额外占用 7GiB 到 20GiB 以上
K3s、etcd、containerd、Rook 同时抢 IO
```

故障现象：

```text
Kubernetes API 多次返回 ServiceUnavailable
节点一度 NotReady
etcd 日志出现 leader is overloaded likely from slow disk
三台节点根盘使用率一度达到约 93%
load average 达到约 18
```

因此本次验证主动停止，没有继续等待 CephCluster Ready。

## 清理结果

已清理：

```text
rook-ceph namespace
Rook/Ceph CRD
Rook/Ceph RBAC
Rook/Ceph Pod
loop 设备和 /var/lib/rook-loop
/var/lib/rook
K3s images 目录中的 Rook/Ceph tar
containerd 中的 Rook/Ceph/CSI 镜像引用
```

清理后：

```text
3 台节点恢复 Ready
rook-ceph namespace 不存在
Rook/Ceph 相关 CRD 不存在
```

## 结论

OrbStack 3 台 Ubuntu 虚机可以用于：

```text
验证脚本语法
验证 manifest 下载
验证镜像离线下载
验证 K3s images 目录上传和导入
验证 Operator manifest 可应用
```

不适合用于：

```text
完整验证 Rook CephFS / RGW
验证 Ceph OSD、MON、MDS、RGW 长时间稳定性
验证磁盘故障恢复
验证生产容量和性能
```

后续要完整验证 Rook CephFS 和 RGW，建议使用真实 3 节点环境：

```text
每台节点 1 块独立裸数据盘
每台系统盘预留 80GiB 以上
每台内存 16GiB 更合理
验证环境允许长时间高 IO
```
