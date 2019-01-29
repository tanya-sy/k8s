#!/bin/bash

echo "***********************清理docker环境**********************"
yum -y install yum-utils
yum remove docker \
                  docker-ce \
                  docker-client \
                  docker-client-latest \
                  docker-common \
                  docker-latest \
                  docker-latest-logrotate \
                  docker-logrotate \
                  docker-selinux \
                  docker-engine-selinux \
                  docker-engine

rm -rf /var/lib/docker 

echo "***********************导入yum源**************************************"
yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum makecache
yum list docker-ce.x86_64  --showduplicates |sort -r


echo "***********************安装docker**********************************************"
wget https://download.docker.com/linux/centos/7/x86_64/stable/Packages/docker-ce-selinux-17.03.2.ce-1.el7.centos.noarch.rpm
cd  /root/scripts-tool
yum -y install policycoreutils-python
rpm -ivh docker-ce-selinux-17.03.2.ce-1.el7.centos.noarch.rpm
yum -y install docker-ce-17.03.2.ce
docker version
sleep 3

echo "***********************修改配置文件**********************************************"
####EOF上加冒号 文件中就会 是 $DOCKER_OPTS 否则就是变量的值
cat > /etc/systemd/system/docker.service <<"EOF"
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.com
After=network.target docker-storage-setup.service
Wants=docker-storage-setup.service

[Service]
Type=notify
Environment=GOTRACEBACK=crash
ExecReload=/bin/kill -s HUP $MAINPID
Delegate=yes
KillMode=process
ExecStart=/usr/bin/dockerd \
          $DOCKER_OPTS \
          $DOCKER_STORAGE_OPTIONS \
          $DOCKER_NETWORK_OPTIONS \
          $DOCKER_DNS_OPTIONS \
          $INSECURE_REGISTRY
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity
TimeoutStartSec=1min
Restart=on-abnormal

[Install]
WantedBy=multi-user.target
EOF
####configured other
cat > /etc/docker/daemon.json <<EOF
{
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF

mkdir -p /etc/systemd/system/docker.service.d/

cat > /etc/systemd/system/docker.service.d/docker-options.conf <<EOF
[Service]
Environment="DOCKER_OPTS=--insecure-registry=10.254.0.0/16 \
    --graph=/opt/docker --log-opt max-size=50m --log-opt max-file=5"
EOF

cat > /etc/systemd/system/docker.service.d/docker-dns.conf <<EOF
[Service]
Environment="DOCKER_DNS_OPTIONS=\
    --dns 10.254.0.2 --dns 114.114.114.114  \
    --dns-search default.svc.cluster.local --dns-search svc.cluster.local  \
    --dns-opt ndots:2 --dns-opt timeout:2 --dns-opt attempts:2"
EOF
sleep 3

echo "***********************启动docker服务*********************"

systemctl daemon-reload
systemctl enable docker
systemctl start docker || journalctl -u docker

