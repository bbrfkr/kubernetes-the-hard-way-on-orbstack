#!/bin/bash -xe

cd /scripts

# 必要パッケージのインストール
apt-get update
apt-get install -y git gettext-base

# バイナリのダウンロードと配布
echo === バイナリのダウンロードと配布 Start ===
{
  ARCH=arm64
  DOWNLOAD_DIR=/downloads
  mkdir -p /downloads

  cat downloads-arm64.txt | xargs -I url curl url -L -O --output-dir ${DOWNLOAD_DIR}

  mkdir -p ${DOWNLOAD_DIR}/{client,cni-plugins,controller,worker}
  tar -xvf ${DOWNLOAD_DIR}/crictl-v1.32.0-linux-${ARCH}.tar.gz \
    -C ${DOWNLOAD_DIR}/worker/
  tar -xvf ${DOWNLOAD_DIR}/containerd-2.1.0-beta.0-linux-${ARCH}.tar.gz \
    --strip-components 1 \
    -C ${DOWNLOAD_DIR}/worker/
  tar -xvf ${DOWNLOAD_DIR}/cni-plugins-linux-${ARCH}-v1.6.2.tgz \
    -C ${DOWNLOAD_DIR}/cni-plugins/
  tar -xvf ${DOWNLOAD_DIR}/etcd-v3.6.0-rc.3-linux-${ARCH}.tar.gz \
    -C ${DOWNLOAD_DIR}/ \
    --strip-components 1 \
    etcd-v3.6.0-rc.3-linux-${ARCH}/etcdctl \
    etcd-v3.6.0-rc.3-linux-${ARCH}/etcd

  chmod 755 ${DOWNLOAD_DIR}/*

  cp -p ${DOWNLOAD_DIR}/{etcdctl,kubectl} /usr/bin
  cp -p ${DOWNLOAD_DIR}/{etcd,kube-apiserver,kube-controller-manager,kube-scheduler} /usr/bin
}
for host in worker-0 worker-1 worker-2; do
  mkdir -p \
    /mnt/machines/${host}/etc/cni/net.d \
    /mnt/machines/${host}/opt/cni/bin \
    /mnt/machines/${host}/var/lib/kubelet \
    /mnt/machines/${host}/var/lib/kube-proxy \
    /mnt/machines/${host}/var/lib/kubernetes \
    /mnt/machines/${host}/var/run/kubernetes
  cp -p ${DOWNLOAD_DIR}/{kubelet,kube-proxy} /mnt/machines/${host}/usr/bin
  cp -p ${DOWNLOAD_DIR}/runc.${ARCH} /mnt/machines/${host}/usr/bin/runc
  cp -p ${DOWNLOAD_DIR}/worker/{containerd,containerd-shim-runc-v2,containerd-stress} /mnt/machines/${host}/bin
  cp -p ${DOWNLOAD_DIR}/cni-plugins/* /mnt/machines/${host}/opt/cni/bin
done
echo === バイナリのダウンロードと配布 End ===

# 証明書作成・配布
echo === CA証明書と鍵の作成 Start ===
{
  openssl genrsa -out ca.key 4096
  openssl req -x509 -new -sha512 -noenc \
    -key ca.key -days 3653 \
    -config ca.conf \
    -out ca.crt
}
echo === CA証明書と鍵の作成 End ===

echo === クライアントおよびサーバー証明書と鍵の作成 Start ===
certs=(
  "admin" "worker-0" "worker-1" "worker-2" # kubelet
  "kube-proxy" "kube-scheduler"
  "kube-controller-manager"
  "kube-api-server"
  "service-accounts"
)
for i in ${certs[*]}; do
  openssl genrsa -out "${i}.key" 4096

  openssl req -new -key "${i}.key" -sha256 \
    -config "ca.conf" -section ${i} \
    -out "${i}.csr"

  openssl x509 -req -days 3653 -in "${i}.csr" \
    -copy_extensions copyall \
    -sha256 -CA "ca.crt" \
    -CAkey "ca.key" \
    -CAcreateserial \
    -out "${i}.crt"
done
echo === クライアントおよびサーバー証明書と鍵の作成 End ===

echo === クライアントおよびサーバー証明書と鍵の配布 Start ===
for host in worker-0 worker-1 worker-2; do
  mkdir -p /mnt/machines/${host}/var/lib/kubelet
  cp ca.crt /mnt/machines/${host}/var/lib/kubelet/
  cp ${host}.crt \
    /mnt/machines/${host}/var/lib/kubelet/kubelet.crt
  cp ${host}.key \
    /mnt/machines/${host}/var/lib/kubelet/kubelet.key
done

mkdir -p /var/lib/kubernetes
cp ca.key ca.crt \
  kube-api-server.key kube-api-server.crt \
  service-accounts.key service-accounts.crt \
  /var/lib/kubernetes

echo === クライアントおよびサーバー証明書と鍵の配布 End ===

# kubeconfigの作成と配布
echo === Kubeconfigの作成と配布 Start ===
for host in worker-0 worker-1 worker-2; do
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://master-0.orb.local:6443 \
    --kubeconfig=${host}.kubeconfig

  kubectl config set-credentials system:node:${host} \
    --client-certificate=${host}.crt \
    --client-key=${host}.key \
    --embed-certs=true \
    --kubeconfig=${host}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${host} \
    --kubeconfig=${host}.kubeconfig

  kubectl config use-context default \
    --kubeconfig=${host}.kubeconfig
done
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://master-0.orb.local:6443 \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=kube-proxy.crt \
    --client-key=kube-proxy.key \
    --embed-certs=true \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config use-context default \
    --kubeconfig=kube-proxy.kubeconfig
}
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://master-0.orb.local:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=kube-controller-manager.crt \
    --client-key=kube-controller-manager.key \
    --embed-certs=true \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config use-context default \
    --kubeconfig=kube-controller-manager.kubeconfig
}
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://master-0.orb.local:6443 \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=kube-scheduler.crt \
    --client-key=kube-scheduler.key \
    --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config use-context default \
    --kubeconfig=kube-scheduler.kubeconfig
}
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://master-0.orb.local:6443 \
    --kubeconfig=admin.kubeconfig

  kubectl config set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=admin \
    --kubeconfig=admin.kubeconfig

  kubectl config use-context default \
    --kubeconfig=admin.kubeconfig
}
for host in worker-0 worker-1 worker-2; do
  mkdir -p /mnt/machines/${host}/var/lib/{kube-proxy,kubelet}

  cp kube-proxy.kubeconfig \
    /mnt/machines/${host}/var/lib/kube-proxy/kubeconfig \

  cp ${host}.kubeconfig \
    /mnt/machines/${host}/var/lib/kubelet/kubeconfig
done

mkdir -p /var/lib/kubernetes
cp admin.kubeconfig \
  kube-controller-manager.kubeconfig \
  kube-scheduler.kubeconfig \
  /var/lib/kubernetes
echo === Kubeconfigの作成と配布 End ===

# data暗号化設定および鍵の作成
echo === data暗号化設定および鍵の作成 Start ===
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64) envsubst < configs/encryption-config.yaml \
  > /var/lib/kubernetes/encryption-config.yaml
echo === data暗号化設定および鍵の作成 End ===

# systemdのサービスユニットファイルの配置
echo === systemdのサービスユニットファイル暗号化設定および鍵の作成 Start ===
cp units/{etcd,kube-apiserver,kube-controller-manager,kube-scheduler}.service /etc/systemd/system
for host in worker-0 worker-1 worker-2; do
  HOSTNAME_OVERRIDE=${host}.orb.local envsubst < units/kubelet.service > /mnt/machines/${host}/etc/systemd/system/kubelet.service
  cp units/{containerd,kube-proxy}.service /mnt/machines/${host}/etc/systemd/system
done
echo === systemdのサービスユニットファイル暗号化設定および鍵の作成 End ===

# etcdのブートストラップ
echo === etcdのブートストラップ Start ===
{
  systemctl daemon-reload
  systemctl enable etcd
  systemctl restart etcd
}
echo === etcdのブートストラップ End ===

echo 10秒待機
sleep 10

# master nodeのブートストラップ
echo === master nodeのブートストラップ Start ===
scp \
  configs/kube-scheduler.yaml \
  configs/kube-apiserver-to-kubelet.yaml \
  /var/lib/kubernetes

{
  systemctl daemon-reload
  systemctl enable kube-apiserver kube-controller-manager kube-scheduler
  systemctl restart kube-apiserver kube-controller-manager kube-scheduler
}

echo 10秒待機
sleep 10

kubectl apply -f /var/lib/kubernetes/kube-apiserver-to-kubelet.yaml --kubeconfig /var/lib/kubernetes/admin.kubeconfig
echo === master nodeのブートストラップ End ===

# worker nodeのブートストラップ準備
echo === worker nodeのブートストラップ準備 Start ===
for host in worker-0 worker-1 worker-2; do
  cp configs/99-loopback.conf /mnt/machines/${host}/etc/cni/net.d
  mkdir -p /mnt/machines/${host}/var/lib/kubelet
  cp configs/kubelet-config.yaml /mnt/machines/${host}/var/lib/kubelet

  mkdir -p  /mnt/machines/${host}/etc/containerd
  cp configs/containerd-config.toml /mnt/machines/${host}/etc/containerd

  mkdir -p /mnt/machines/${host}/var/lib/kube-proxy
  HOSTNAME_OVERRIDE=${host}.orb.local envsubst < configs/kube-proxy-config.yaml > /mnt/machines/${host}/var/lib/kube-proxy/kube-proxy-config.yaml
done
echo === worker nodeのブートストラップ準備 End ===
