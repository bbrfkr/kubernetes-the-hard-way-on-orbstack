#!/bin/bash -xe

# 依存パッケージのインストール
echo === 依存パッケージのインストール Start ===
apt-get update
apt-get -y install socat conntrack ipset kmod
echo === 依存パッケージのインストール End ===

# swapの無効化
swapoff -a

# kernelパラメータの調整
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

# systemdサービスの有効化
{
  systemctl daemon-reload
  systemctl enable containerd kubelet kube-proxy
  systemctl restart containerd kubelet kube-proxy
}
