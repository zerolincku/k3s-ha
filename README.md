# k3s-ha

面向生产环境的高可用部署手册与脚本仓库。

当前已完成第一阶段：3 台 master 节点的 K3s 高可用集群方案，包含在线一键部署脚本和离线部署方案。后续 Redis、RabbitMQ、MinIO 等中间件高可用部署方案按同一目录约定扩展。

已考虑：

- `amd64` 与 `arm64` 主机架构。
- cgroup v1 与 cgroup v2 主机预检。
- 在线与离线两种部署路径。

## 目录结构

```text
.
├── README.md
├── k3s/
│   ├── 说明.md
│   ├── 配置示例.env
│   ├── docs/
│   │   ├── 01-架构说明.md
│   │   ├── 02-在线部署.md
│   │   ├── 03-离线部署.md
│   │   ├── 04-运维手册.md
│   │   └── 05-OrbStack验证记录.md
│   └── scripts/
│       ├── deploy-k3s-ha.sh
│       └── prepare-airgap-bundle.sh
├── keepalived-haproxy/
│   ├── 说明.md
│   ├── 配置示例.env
│   ├── docs/
│   └── scripts/
└── <resource>/      # 后续 redis、mysql、rabbitmq、minio 等资源目录
```

每个资源目录独立描述一个资源的部署，建议固定包含：

```text
<resource>/
├── 说明.md
├── 配置示例.env
├── docs/
│   ├── 01-架构说明.md
│   ├── 02-在线部署.md
│   ├── 03-离线部署.md
│   └── 04-运维手册.md
└── scripts/
```

## 第一阶段交付

- Keepalived + HAProxy 高可用入口：[keepalived-haproxy/说明.md](keepalived-haproxy/说明.md)
- K3s 3 master 高可用架构：[k3s/docs/01-架构说明.md](k3s/docs/01-架构说明.md)
- 在线一键部署：[k3s/docs/02-在线部署.md](k3s/docs/02-在线部署.md)
- 离线部署方案：[k3s/docs/03-离线部署.md](k3s/docs/03-离线部署.md)
- 运维检查与故障处理：[k3s/docs/04-运维手册.md](k3s/docs/04-运维手册.md)
- OrbStack 三节点验证记录：[k3s/docs/05-OrbStack验证记录.md](k3s/docs/05-OrbStack验证记录.md)

## 快速开始

复制并修改配置文件：

```bash
cp keepalived-haproxy/配置示例.env keepalived-haproxy/prod.env
cp k3s/配置示例.env k3s/prod.env
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

准备离线包：

```bash
bash k3s/scripts/prepare-airgap-bundle.sh k3s/prod.env
```

同时准备 `amd64` 与 `arm64` 离线包：

```bash
K3S_VERSION=v1.34.8+k3s1 K3S_ARCH=all \
bash k3s/scripts/prepare-airgap-bundle.sh k3s/prod.env
```

离线部署：

```bash
K3S_AIRGAP=true \
AIRGAP_BUNDLE_AMD64=/path/to/k3s-airgap-bundle-<version>-amd64.tar.gz \
AIRGAP_BUNDLE_ARM64=/path/to/k3s-airgap-bundle-<version>-arm64.tar.gz \
bash k3s/scripts/deploy-k3s-ha.sh k3s/prod.env
```
