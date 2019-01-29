#!/bin/bash
###使用 CloudFlare 的 PKI 工具集 cfssl 来生成 Certificate Authority (CA) 证书和秘钥文件##

echo “*************安装cfssl工具**********”
#mkdir -p ${cfssl_dir}
cfssl_dir="/opt/local/cfssl"
ssl_dir="/etc/kubernetes/ssl"
csr_dir="/opt/ssl"

mkdir -p ${cfssl_dir}
cd ${cfssl_dir}

wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
mv cfssl_linux-amd64 cfssl

wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
mv cfssljson_linux-amd64 cfssljson

wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
mv cfssl-certinfo_linux-amd64 cfssl-certinfo

chmod +x *

sleep 3

echo "************创建CA机构**************************"
##该文件定义了CA签发证书的具体信息
mkdir ${csr_dir} 
cd ${csr_dir}/
cat > config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "87600h"
      }
    }
  }
}
EOF

cat > csr.json <<EOF
{
  "CN": "kubernetes",
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

cd ${csr_dir}/
${cfssl_dir}/cfssl gencert -initca csr.json | ${cfssl_dir}/cfssljson -bare ca
ls -l

echo "************颁发CA证书到所有机器**************************"
mkdir -p ${ssl_dir}
cp *.pem ${ssl_dir}
cp ca.csr ${ssl_dir}

ssh node1 mkdir -p ${ssl_dir}
scp *.pem *.csr node1:${ssl_dir}

ssh node2 mkdir -p ${ssl_dir}
scp *.pem *.csr node2:${ssl_dir}


