# k3s-ha

面向生产环境的高可用部署手册与脚本仓库。

当前已完成：3 台 master 节点的 K3s 高可用集群方案、Redis Sentinel 高可用部署方案，以及 RabbitMQ 高可用部署方案。后续 MinIO、MySQL 等中间件高可用部署方案按同一目录约定扩展。

已考虑：

- `amd64` 与 `arm64` 主机架构。
- cgroup v1 与 cgroup v2 主机预检。
- 在线与离线两种部署路径。

## K3s 离线镜像导入约定

所有资源目录如果需要把镜像归档放入 K3s 自动导入目录：

```text
/var/lib/rancher/k3s/agent/images/
```

脚本必须先上传或复制为 `.uploading-*.tmp`，确认传输完成后再 `mv` 为最终 `.tar` 或 `.tar.zst` 文件名。不要把正在传输的半成品直接写成最终文件名，否则 K3s 启动扫描 images 目录时可能读到未完成归档，出现 `short read` 或 `unexpected EOF`。

K3s 已经运行时，归档放入 images 目录通常不会立即导入；需要重启对应节点的 `k3s` 服务才会触发导入。生产环境应逐台滚动重启。

## 目录结构

```text
.
├── README.md
├── k3s/
│   ├── 说明.md
│   ├── config.example.env
│   ├── docs/
│   │   ├── 01-架构说明.md
│   │   ├── 02-在线部署.md
│   │   ├── 03-离线部署.md
│   │   ├── 04-运维手册.md
│   │   └── 05-OrbStack验证记录.md
│   └── scripts/
│       ├── deploy-k3s-ha.sh
│       ├── download-k3s-assets.sh
│       ├── download-k3s-images.sh
│       └── prepare-airgap-bundle.sh
├── keepalived-haproxy/
│   ├── 说明.md
│   ├── config.example.env
│   ├── docs/
│   └── scripts/
├── redis/
│   ├── 说明.md
│   ├── config.example.env
│   ├── docs/
│   ├── manifests/
│   └── scripts/
├── rabbitmq/
│   ├── 说明.md
│   ├── config.example.env
│   ├── docs/
│   ├── manifests/
│   └── scripts/
└── <resource>/      # 后续 mysql、minio 等资源目录
```

每个资源目录独立描述一个资源的部署，建议固定包含：

```text
<resource>/
├── 说明.md
├── config.example.env
├── docs/
│   ├── 01-架构说明.md
│   ├── 02-在线部署.md
│   ├── 03-离线部署.md
│   └── 04-运维手册.md
└── scripts/
```

## 当前交付

- Keepalived + HAProxy 高可用入口：[keepalived-haproxy/说明.md](keepalived-haproxy/说明.md)
- Redis Sentinel 高可用部署：[redis/说明.md](redis/说明.md)
- RabbitMQ 高可用部署：[rabbitmq/说明.md](rabbitmq/说明.md)
- K3s 3 master 高可用架构：[k3s/docs/01-架构说明.md](k3s/docs/01-架构说明.md)
- 在线一键部署：[k3s/docs/02-在线部署.md](k3s/docs/02-在线部署.md)
- 离线部署方案：[k3s/docs/03-离线部署.md](k3s/docs/03-离线部署.md)
- 运维检查与故障处理：[k3s/docs/04-运维手册.md](k3s/docs/04-运维手册.md)
- OrbStack 三节点验证记录：[k3s/docs/05-OrbStack验证记录.md](k3s/docs/05-OrbStack验证记录.md)
- RabbitMQ OrbStack 验证记录：[rabbitmq/docs/05-OrbStack验证记录.md](rabbitmq/docs/05-OrbStack验证记录.md)

## 快速开始

复制并修改配置文件：

```bash
cp keepalived-haproxy/config.example.env keepalived-haproxy/prod.env
cp k3s/config.example.env k3s/prod.env
vim keepalived-haproxy/prod.env
vim k3s/prod.env
```

在线部署：

```bash
bash k3s/scripts/deploy-k3s-ha.sh k3s/prod.env
```

需要 Kubernetes API 统一入口时，再单独部署：

```bash
bash keepalived-haproxy/scripts/deploy-keepalived-haproxy.sh keepalived-haproxy/prod.env
```

下载 K3s 本体离线资源：

```bash
K3S_ARCH=all bash k3s/scripts/download-k3s-assets.sh k3s/prod.env
```

下载 K3s 系统镜像归档：

```bash
K3S_ARCH=all bash k3s/scripts/download-k3s-images.sh k3s/prod.env
```

准备完整离线包：

```bash
bash k3s/scripts/prepare-airgap-bundle.sh k3s/prod.env
```

同时准备 `amd64` 与 `arm64` 离线包：

```bash
K3S_VERSION=v1.35.5+k3s1 K3S_ARCH=all \
bash k3s/scripts/prepare-airgap-bundle.sh k3s/prod.env
```

离线部署：

```bash
K3S_AIRGAP=true \
AIRGAP_BUNDLE_AMD64=/path/to/k3s-airgap-bundle-<version>-amd64.tar.gz \
AIRGAP_BUNDLE_ARM64=/path/to/k3s-airgap-bundle-<version>-arm64.tar.gz \
bash k3s/scripts/deploy-k3s-ha.sh k3s/prod.env
```

部署 RabbitMQ：

```bash
cp rabbitmq/config.example.env rabbitmq/prod.env
vim rabbitmq/prod.env
bash rabbitmq/scripts/deploy-rabbitmq.sh rabbitmq/prod.env
```

准备 RabbitMQ 离线资源：

```bash
bash rabbitmq/scripts/download-rabbitmq-images.sh rabbitmq/prod.env
bash rabbitmq/scripts/upload-rabbitmq-images.sh rabbitmq/prod.env
```
