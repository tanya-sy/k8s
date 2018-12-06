#!/bin/bash
####这是配置 master&node角色 中的node部分
####同时生成 其他node节点所需要的相关文件



ssl_dir="${ssl_dir}"
csr_dir="/opt/ssl"
master_ip="$(ip addr show dev ens32 | grep inet | grep ens32 | cut -d/ -f1  | awk '{print $NF}')"
##取ip地址的主机号，组成kubelet向master注册的主机名
sign_name="echo ${node_ip} | cut -d"." -f4)"



###kubelet 授权 kube-apiserver 的一些操作 exec run logs 等  授权给kubernetes用户
kubectl create clusterrolebinding kube-apiserver:kubelet-apis --clusterrole=system:kubelet-api-admin --user kubernetes

echo "*******************************生成所有节点的kubelet bootstrap文件*************** "
for id in {master,node1,node2}
do
kubeadm token create --description kubelet-bootstrap-token --groups system:bootstrappers:${id} --kubeconfig ~/.kube/config
cd /root/
kubeadm token list --kubeconfig ~/.kube/config
id_token=$(kubeadm token list --kubeconfig ~/.kube/config | grep "${id}" | awk '{print $1}')

###生成对应节点的bootstrap.kubeconfig
kubectl config set-cluster kubernetes \
  --certificate-authority=${ssl_dir}/ca.pem \
  --embed-certs=true \
  --server=https://${master_ip}:6443 \
  --kubeconfig=${id}-bootstrap.kubeconfig
kubectl config set-credentials kubelet-bootstrap \
  --token=${master_token} \
  --kubeconfig=${id}-bootstrap.kubeconfig
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=${id}-bootstrap.kubeconfig
kubectl config use-context default --kubeconfig=${id}-bootstrap.kubeconfig
scp ${id}-bootstrap.kubeconfig  ${id}:/etc/kubernetes/bootstrap.kubeconfig

done

kubectl create clusterrolebinding kubelet-bootstrap --clusterrole=system:node-bootstrapper --group=system:bootstrappers

####创建自动批准相关 CSR 请求的 ClusterRole

cat > /etc/kubernetes/tls-instructs-csr.yaml <<EOF
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: system:certificates.k8s.io:certificatesigningrequests:selfnodeserver
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeserver"]
  verbs: ["create"]
EOF

kubectl apply -f /etc/kubernetes/tls-instructs-csr.yaml


# 自动批准 system:bootstrappers 组用户 TLS bootstrapping 首次申请证书的 CSR 请求

kubectl create clusterrolebinding node-client-auto-approve-csr --clusterrole=system:certificates.k8s.io:certificatesigningrequests:nodeclient --group=system:bootstrappers


# 自动批准 system:nodes 组用户更新 kubelet 自身与 apiserver 通讯证书的 CSR 请求

kubectl create clusterrolebinding node-client-auto-renew-crt --clusterrole=system:certificates.k8s.io:certificatesigningrequests:selfnodeclient --group=system:nodes


# 自动批准 system:nodes 组用户更新 kubelet 10250 api 端口证书的 CSR 请求

kubectl create clusterrolebinding node-server-auto-renew-crt --clusterrole=system:certificates.k8s.io:certificatesigningrequests:selfnodeserver --group=system:nodes
##

echo "***********************配置kubelet服务文件***********************************************"

mkdir -p /var/lib/kubelet
ssh node1 mkdir -p /var/lib/kubelet
ssh node2 mkdir -p /var/lib/kubelet

cat > /etc/systemd/system/kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/var/lib/kubelet
ExecStart=/usr/local/bin/kubelet \
  --hostname-override=kubernetes-${sign_name} \
  --pod-infra-container-image=jicki/pause-amd64:3.1 \
  --bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
  --config=/etc/kubernetes/kubelet.config.json \
  --cert-dir=/etc/kubernetes/ssl \
  --logtostderr=true \
  --v=2

[Install]
WantedBy=multi-user.target
EOF
cat > /etc/kubernetes/kubelet.config.json <<EOF
{
  "kind": "KubeletConfiguration",
  "apiVersion": "kubelet.config.k8s.io/v1beta1",
  "authentication": {
    "x509": {
      "clientCAFile": "/etc/kubernetes/ssl/ca.pem"
    },
    "webhook": {
      "enabled": true,
      "cacheTTL": "2m0s"
    },
    "anonymous": {
      "enabled": false
    }
  },
  "authorization": {
    "mode": "Webhook",
    "webhook": {
      "cacheAuthorizedTTL": "5m0s",
      "cacheUnauthorizedTTL": "30s"
    }
  },
  "address": "71",
  "port": 10250,
  "readOnlyPort": 0,
  "cgroupDriver": "cgroupfs",
  "hairpinMode": "promiscuous-bridge",
  "serializeImagePulls": false,
  "RotateCertificates": true,
  "featureGates": {
    "RotateKubeletClientCertificate": true,
    "RotateKubeletServerCertificate": true
  },
  "MaxPods": "512",
  "failSwapOn": false,
  "containerLogMaxSize": "10Mi",
  "containerLogMaxFiles": 5,
  "clusterDomain": "cluster.local.",
  "clusterDNS": ["10.254.0.2"]
}
EOF

sleep 3

echo ***************拷贝kubelet服务文件到所有节点*************************
systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet
systemctl status kubelet


echo "**********************配置kube-proxy*****************************************************"
yum install ipset ipvsadm conntrack-tools.x86_64 -y

echo "**************************生成kube-proxy证书****************************************"
cd ${csr_dir}
cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShenZhen",
      "L": "ShenZhen",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

/opt/local/cfssl/cfssl gencert -ca=${ssl_dir}/ca.pem \
  -ca-key=${ssl_dir}/ca-key.pem \
  -config=${csr_dir}/config.json \
  -profile=kubernetes  kube-proxy-csr.json | /opt/local/cfssl/cfssljson -bare kube-proxy

cp kube-proxy* ${ssl_dir}/
echo "*****************************拷贝kube-proxy证书到所有节点*************************"
scp kube-proxy* node1:${ssl_dir}/
scp kube-proxy* node2:${ssl_dir}/

echo"*****************创建  kube-proxy kubeconfig 文件***********************"
cd /root/
kubectl config set-cluster kubernetes \
  --certificate-authority=${ssl_dir}/ca.pem \
  --embed-certs=true \
  --server=https://${master_ip}:6443 \
  --kubeconfig=kube-proxy.kubeconfig
# 配置客户端认证
kubectl config set-credentials kube-proxy \
  --client-certificate=${ssl_dir}/kube-proxy.pem \
  --client-key=${ssl_dir}/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
# 配置关联
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
cp -v kube-proxy.kubeconfig  /etc/kubernetes/

echo "*******************拷贝kube-proxy的kubeconfig文件到所有节点*********************************"
scp kube-proxy.kubeconfig  node1:/etc/kubernetes/
scp kube-proxy.kubeconfig  node2:/etc/kubernetes/


cd /etc/kubernetes/
cat > kube-proxy.config.yaml<<EOF
apiVersion: kubeproxy.config.k8s.io/v1alpha1
bindAddress: 192.168.31.71
clientConnection:
  kubeconfig: /etc/kubernetes/kube-proxy.kubeconfig
clusterCIDR: 10.254.64.0/18
healthzBindAddress: 192.168.31.71:10256
hostnameOverride: kubernetes-64
kind: KubeProxyConfiguration
metricsBindAddress: 192.168.31.71:10249
mode: "ipvs"
EOF
mkdir -p /var/lib/kube-proxy
cat > /etc/systemd/system/kube-proxy.service<<EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
WorkingDirectory=/var/lib/kube-proxy
ExecStart=/usr/local/bin/kube-proxy \
  --config=/etc/kubernetes/kube-proxy.config.yaml \
  --logtostderr=true \
  --v=1
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kube-proxy
systemctl start kube-proxy
systemctl status kube-proxy
