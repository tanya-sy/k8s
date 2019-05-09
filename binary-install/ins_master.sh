#!/bin/bash

echo "*********************下载源文件*****************************************"
k8s_src="/root/k8s_src"
ssl_dir="/etc/kubernetes/ssl"
csr_dir="/opt/ssl"
master_ip="$(ip addr show dev ens32 | grep inet | grep ens32 | cut -d/ -f1  | awk '{print $NF}')"

mkdir ${k8s_src} && cd ${k8s_src} 
wget https://dl.k8s.io/v1.11.2/kubernetes-server-linux-amd64.tar.gz
tar -xzvf kubernetes-server-linux-amd64.tar.gz  && cd kubernetes
cp -r server/bin/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl,kubelet,kubeadm} /usr/local/bin/

echo "*********************拷贝源文件到所有node*****************************************"
scp server/bin/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl,kube-proxy,kubelet,kubeadm} node1:/usr/local/bin/
scp server/bin/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl,kube-proxy,kubelet,kubeadm} node2:/usr/local/bin/

echo "*********************生成kubectl配置文件*******************************************"
####配置kubectl与api-server的安全访问

cd ${csr_dir}/
cat > admin-csr.json << EOF
{
  "CN": "admin",
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
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF

cd ${csr_dir}/

/opt/local/cfssl/cfssl gencert -ca=${ssl_dir}/ca.pem \
  -ca-key=${ssl_dir}/ca-key.pem \
  -config=${csr_dir}/config.json \
  -profile=kubernetes admin-csr.json | /opt/local/cfssl/cfssljson -bare admin
ls admin*
cp admin*.pem ${ssl_dir}

#####配置kubectl的kubeconfig配置文件
kubectl config set-cluster kubernetes \
  --certificate-authority=${ssl_dir}/ca.pem \
  --embed-certs=true \
  --server=https://127.0.0.1:6443

kubectl config set-credentials admin \
  --client-certificate=${ssl_dir}/admin.pem \
  --embed-certs=true \
  --client-key=${ssl_dir}/admin-key.pem

kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin

kubectl config use-context kubernetes

ll /root/.kube/


echo "*********************生成kubernetes证书*******************************************"
####说个实话我嗯是没相通这个证书是拿来干啥的
###2019年5月8日更新
###如果api组件都没有证书的话，那其他组件又何必用https访问呢
cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
    "${master_ip}",
    "${node1}",
    "${node2}",
    "10.254.0.1",
    "kubernetes",
    "kubernetes.default",
    "kubernetes.default.svc",
    "kubernetes.default.svc.cluster",
    "kubernetes.default.svc.cluster.local"
  ],
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
  -profile=kubernetes kubernetes-csr.json | /opt/local/cfssl/cfssljson -bare kubernetes

ls -lt kubernetes*

cp kubernetes*.pem ${ssl_dir}/

echo "**************************拷贝证书到所有节点****************************************"

scp kubernetes*.pem  node1:${ssl_dir}/
scp kubernetes*.pem  node2:${ssl_dir}/


echo "**************************配置kube-apiserver*****************************************"

# 创建 encryption-config.yaml 配置
cd /etc/kubernetes/
cat > encryption-config.yaml <<EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: 40179b02a8f6da07d90392ae966f7749
      - identity: {}
EOF

#配置最低限度日志审核
cat >> audit-policy.yaml <<EOF
# Log all requests at the Metadata level.
apiVersion: audit.k8s.io/v1beta1
kind: Policy
rules:
- level: Metadata
EOF

###配置service文件
cat > /etc/systemd/system/kube-apiserver.service <<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/kube-apiserver \
  --admission-control=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota,NodeRestriction \
  --anonymous-auth=false \
  --experimental-encryption-provider-config=/etc/kubernetes/encryption-config.yaml \
  --advertise-address=${master_ip} \
  --allow-privileged=true \
  --apiserver-count=1 \
  --audit-policy-file=/etc/kubernetes/audit-policy.yaml \
  --audit-log-maxage=30 \
  --audit-log-maxbackup=3 \
  --audit-log-maxsize=100 \
  --audit-log-path=/var/log/kubernetes/audit.log \
  --authorization-mode=Node,RBAC \
  --bind-address=0.0.0.0 \
  --secure-port=6443 \
  --client-ca-file=${ssl_dir}/ca.pem \
  --kubelet-client-certificate=${ssl_dir}/kubernetes.pem \
  --kubelet-client-key=${ssl_dir}/kubernetes-key.pem \
  --enable-swagger-ui=true \
  --etcd-cafile=${ssl_dir}/ca.pem \
  --etcd-certfile=${ssl_dir}/etcd.pem \
  --etcd-keyfile=${ssl_dir}/etcd-key.pem \
  --etcd-servers=https://${master_ip}:2379 \
  --event-ttl=1h \
  --kubelet-https=true \
  --insecure-bind-address=127.0.0.1 \
  --insecure-port=8080 \
  --service-account-key-file=${ssl_dir}/ca-key.pem \
  --service-cluster-ip-range=10.254.0.0/18 \
  --service-node-port-range=30000-32000 \
  --tls-cert-file=${ssl_dir}/kubernetes.pem \
  --tls-private-key-file=${ssl_dir}/kubernetes-key.pem \
  --enable-bootstrap-token-auth \
  --v=1
Restart=on-failure
RestartSec=5
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kube-apiserver
systemctl start kube-apiserver
systemctl status kube-apiserver

echo "**********************配置kube-controller-manager*********************************"

cat > /etc/systemd/system/kube-controller-manager.service <<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \
  --address=0.0.0.0 \
  --master=http://127.0.0.1:8080 \
  --allocate-node-cidrs=true \
  --service-cluster-ip-range=10.254.0.0/18 \
  --cluster-cidr=10.254.64.0/18 \
  --cluster-signing-cert-file=${ssl_dir}/ca.pem \
  --cluster-signing-key-file=${ssl_dir}/ca-key.pem \
  --feature-gates=RotateKubeletServerCertificate=true \
  --controllers=*,tokencleaner,bootstrapsigner \
  --experimental-cluster-signing-duration=86700h0m0s \
  --cluster-name=kubernetes \
  --service-account-private-key-file=${ssl_dir}/ca-key.pem \
  --root-ca-file=${ssl_dir}/ca.pem \
  --leader-elect=true \
  --node-monitor-grace-period=40s \
  --node-monitor-period=5s \
  --pod-eviction-timeout=5m0s \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sleep 2

echo "**********************启动kube-controller-manager*********************************"
systemctl daemon-reload
systemctl enable kube-controller-manager
systemctl start kube-controller-manager
systemctl status kube-controller-manager


echo "**********************配置kube-scheduler*********************************"
cat > /etc/systemd/system/kube-scheduler.service <<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \
  --address=0.0.0.0 \
  --master=http://127.0.0.1:8080 \
  --leader-elect=true \
  --v=1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sleep3

echo "********************启动kube-scheduler*********************************"
systemctl daemon-reload
systemctl enable kube-scheduler
systemctl start kube-scheduler
systemctl status kube-scheduler

kubectl get componentstatuses


