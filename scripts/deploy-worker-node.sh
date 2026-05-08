#!/bin/bash -xe

# 依存パッケージのインストール
echo === 1. 依存パッケージのインストール Start ===
apt-get update
apt-get -y install socat conntrack ipset kmod
echo === 1. 依存パッケージのインストール End ===

# swapの無効化
echo === 2. swap無効化 Start ===
swapoff -a
echo === 2. swap無効化 End ===

# kernelパラメータの調整
echo === 3. kernelパラメータの調整 Start ===
{
  modprobe br-netfilter
  echo "br-netfilter" >> /etc/modules-load.d/modules.conf
}
{
  echo "net.bridge.bridge-nf-call-iptables = 1" \
    >> /etc/sysctl.d/kubernetes.conf
  echo "net.bridge.bridge-nf-call-ip6tables = 1" \
    >> /etc/sysctl.d/kubernetes.conf
  sysctl -p /etc/sysctl.d/kubernetes.conf
}
echo === 3. kernelパラメータの調整 End ===

# systemdサービスの有効化
echo === 4. systemdサービスの有効化 Start ===
{
  systemctl daemon-reload
  systemctl enable containerd kubelet kube-proxy
  systemctl restart containerd kubelet kube-proxy
}
echo === 4. systemdサービスの有効化 End ===
