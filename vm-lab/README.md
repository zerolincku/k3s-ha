# vm-lab

这个目录用于在当前 WSL2 环境里用 libvirt/QEMU/KVM 创建 3 台 VM，验证 `k3s/` 里的 3 master HA 部署，以及后续 Rook-Ceph。

## 资源规划

默认创建：

| VM | vCPU | RAM | OS disk | Ceph disk |
| --- | ---: | ---: | ---: | ---: |
| `k3s-1` | 2 | 4G | 30G | 30G |
| `k3s-2` | 2 | 4G | 30G | 30G |
| `k3s-3` | 2 | 4G | 30G | 30G |

当前机器约 15G 内存、949G 可用磁盘，够做 K3s + Rook-Ceph 功能验证。

## 首次准备

```bash
cp vm-lab/lab.env.example vm-lab/lab.env
bash vm-lab/scripts/install-tools.sh
```

如果是第一次加入 `kvm/libvirt` 组，重新打开 shell。脚本也会在需要时使用 `sudo`。

在没有 TTY 的自动化环境里，可以提供 `SUDO_ASKPASS` 后再运行脚本。

确保有 SSH 公钥：

```bash
test -f ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519
```

## 创建 VM

```bash
bash vm-lab/scripts/prepare-image.sh
bash vm-lab/scripts/create-vms.sh
bash vm-lab/scripts/list-vms.sh
```

`create-vms.sh` 会：

- 下载 Ubuntu 24.04 cloud image；
- 为每台 VM 创建 OS qcow2；
- 为每台 VM 创建一块额外的 Ceph 数据盘；
- 通过 cloud-init 注入 root SSH key；
- 安装 K3s/Rook-Ceph 常用宿主机依赖。

## 生成 K3s 配置并部署

```bash
bash vm-lab/scripts/render-k3s-env.sh
bash k3s/scripts/deploy-k3s-ha.sh vm-lab/generated/k3s-vm.env
```

部署完成后：

```bash
export KUBECONFIG=./k3s/artifacts/kubeconfig.yaml
kubectl get nodes -o wide
kubectl -n kube-system get pods -o wide
kubectl get --raw=/readyz?verbose
```

## Rook-Ceph 验证建议

每台 VM 都有一块额外盘，通常会在 guest 内显示为 `/dev/vdb`。部署 Rook-Ceph 前先确认：

```bash
ssh root@<vm-ip> lsblk
```

Rook-Ceph 的最小验收建议：

```bash
kubectl -n rook-ceph get pods -o wide
kubectl -n rook-ceph get cephcluster
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
kubectl get storageclass
```

再创建一个 PVC 和临时 Pod 做实际读写。最后可以关停一台 VM，观察 Ceph 从 degraded 恢复到 clean。

## VM 生命周期

```bash
bash vm-lab/scripts/start-vms.sh
bash vm-lab/scripts/stop-vms.sh
FORCE=true bash vm-lab/scripts/stop-vms.sh
CONFIRM=yes bash vm-lab/scripts/destroy-vms.sh
```

`destroy-vms.sh` 会删除 VM、OS disk、Ceph disk 和 cloud-init seed，但保留下载好的 base image。
