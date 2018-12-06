#!/bin/bash

ssl_dir="/etc/kubernetes/ssl"
csr_dir="/opt/ssl"
master_ip="$(ip addr show dev ens32 | grep inet | grep ens32 | cut -d/ -f1  | awk '{print $NF}')"

echo "*****************************下载源文件*************************"

id etcd || useradd etcd && rm -rf /home/etcd
mkdir /home/src-etcd && cd /home/etcd

wget https://github.com/coreos/etcd/releases/download/v3.2.18/etcd-v3.2.18-linux-amd64.tar.gz
tar zxvf etcd-v3.2.18-linux-amd64.tar.gz
cd etcd-v3.2.18-linux-amd64
mv etcd  etcdctl /usr/bin/


echo "****************************生成etcd证书*************************"
cd ${csr_dir}/
cat > etcd-csr.json <<EOF
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "${master_ip}"
    "${node1_ip}"
    "${node2_ip}"
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

/opt/local/cfssl/cfssl gencert -ca=${csr_dir}/ca.pem \
  -ca-key=${csr_dir}/ca-key.pem \
  -config=${csr_dir}/config.json \
  -profile=kubernetes etcd-csr.json | /opt/local/cfssl/cfssljson -bare etcd
ls etcd*
cp etcd*.pem ${ssl_dir}/
chmod 644 ${ssl_dir}/etcd-key.pem
sleep 2


echo "*******************拷贝etcd证书到所有的机器***********************"
scp etcd*   node1:${ssl_dir}
scp etcd*   node2:${ssl_dir}

echo "*******************修改etcd配置文件*******************************"
mkdir -p /opt/etcd
chown -R etcd:etcd /opt/etcd


cat > /etc/systemd/system/etcd.service << EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
WorkingDirectory=/opt/etcd/
User=etcd
# set GOMAXPROCS to number of processors
ExecStart=/usr/bin/etcd \
  --name=etcd1 \
  --cert-file=${ssl_dir}/etcd.pem \
  --key-file=${ssl_dir}/etcd-key.pem \
  --peer-cert-file=${ssl_dir}/etcd.pem \
  --peer-key-file=${ssl_dir}/etcd-key.pem \
  --trusted-ca-file=${ssl_dir}/ca.pem \
  --peer-trusted-ca-file=${ssl_dir}/ca.pem \
  --initial-advertise-peer-urls=https://${master_ip}:2380 \
  --listen-peer-urls=https://${master_ip}:2380 \
  --listen-client-urls=https://${master_ip}:2379,http://127.0.0.1:2379 \
  --advertise-client-urls=https://${master_ip}:2379 \
  --initial-cluster-token=k8s-etcd-cluster \
  --initial-cluster=etcd1=https://${master_ip}:2380 \
  --initial-cluster-state=new \
  --data-dir=/opt/etcd/
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sleep 4

echo "**************************启动etcd服务************************"
systemctl daemon-reload
systemctl enable etcd
systemctl start etcd || journalctl -u etcd

sleep 2

echo "**************************查看etcd状态*******************************"
etcdctl --endpoints=https://${master_ip}:2379 \
        --cert-file=${ssl_dir}/etcd.pem \
        --ca-file=${ssl_dir}/ca.pem \
        --key-file=${ssl_dir}/etcd-key.pem \
        cluster-health

etcdctl --endpoints=https://${master_ip}:2379 \
        --cert-file=${ssl_dir}/etcd.pem \
        --ca-file=${ssl_dir}/ca.pem \
        --key-file=${ssl_dir}/etcd-key.pem \
        member list
