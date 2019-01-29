#!/bin/bash

##证书生成等操作，master已经将相关文件生成

node_ip="$(ip addr show dev ens32 | grep inet | grep ens32 | cut -d/ -f1  | awk '{print $NF}')"
##取ip地址的主机号，组成kubelet向master注册的主机名
sign_name="echo ${node_ip} | cut -d"." -f4)"

echo "***********************配置kubelet服务文件***********************************************"

kubelet_home="/var/lib/kubelet"
mkdir -p ${kubelet_home}

cat > /etc/systemd/system/kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=${kubelet_home}
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
  "address": "${node_ip}",
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

echo ***************启动kubelet服务*************************
systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet
systemctl status kubelet


echo "**********************配置kube-proxy*****************************************************"
yum install ipset ipvsadm conntrack-tools.x86_64 -y
kubeproxy_home="/var/lib/kube-proxy"

cd /etc/kubernetes/
cat > kube-proxy.config.yaml<<EOF
apiVersion: kubeproxy.config.k8s.io/v1alpha1
bindAddress: ${node_ip}
clientConnection:
  kubeconfig: /etc/kubernetes/kube-proxy.kubeconfig
clusterCIDR: 10.254.64.0/18
healthzBindAddress: ${node_ip}:10256
hostnameOverride: kubernetes-64
kind: KubeProxyConfiguration
metricsBindAddress: ${node_ip}:10249
mode: "ipvs"
EOF

mkdir -p ${kubeproxy_home}
cat > /etc/systemd/system/kube-proxy.service<<EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
WorkingDirectory=${kubeproxy_home}
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
sleep 3

echo "***************************启动kube-proxy服务*******************************"
systemctl daemon-reload
systemctl enable kube-proxy
systemctl start kube-proxy
systemctl status kube-proxy
