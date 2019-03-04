#!/bin/bash

##在我用kubeadm安装集群遇到的问题主要是：镜像问题 ;默认的基础镜像一直无法下载

swapoff -a
cat >>/etc/sysctl.d/k8s.conf <<EOF

net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.swappiness=0

EOF

##加载指定模块
modprobe br_netfilter
sysctl -p /etc/sysctl.d/k8s.conf

######################################################

#清理环境
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

##导入阿里云的docker yum源
yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
yum makecache
###下载
##
yum -y install docker-ce-selinux-17.03.2.ce
yum -y install docker-ce-17.03.2.ce

##
systemctl start docker
systemctl enable docker

#####################################################
#添加k8syum源

cat >/etc/yum.repos.d/kubernetes.repo<<EOF
[kubernetes]
name=Kubernetes
baseurl=http://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=http://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
       http://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg

EOF

###还是要保证三个软件的版本一致
yum makecache

##有一次直接使用这条命令下载的时候，kubelet的版本是1.13,初始化报错版本不匹配，所以可以先下载指定版本的kubelet
##再下载kubeadm
#yum install -y  kubeadm-1.11.3-0
rpm -q kubeadm kubelet kubectl

####




