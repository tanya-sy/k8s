#!/bin/bash
ssl_dir="/etc/kubernetes/ssl"
rpm_dir= "/root/scripts-tool"
read -p "请输入master ip: "  master_ip

cd ${rpm_dir}
rpm -ivh flannel-0.10.0-1.x86_64.rpm
mv /usr/lib/systemd/system/docker.service.d/flannel.conf /etc/systemd/system/docker.service.d

etcdctl --endpoints=https://${master_ip}g:2379 \
        --cert-file=${ssl_dir}/etcd.pem \
        --ca-file=${ssl_dir}/ca.pem \
        --key-file=${ssl_dir}/etcd-key.pem \
        set /flannel/network/config \ '{"Network":"10.254.64.0/18","SubnetLen":24,"Backend":{"Type":"host-gw"}}'

cat > /etc/sysconfig/flanneld <<EOF
FLANNEL_ETCD_ENDPOINTS="https://${master_ip}g:2379"
FLANNEL_ETCD_PREFIX="/flannel/network"
FLANNEL_OPTIONS="-ip-masq=true -etcd-cafile=${ssl_dir}/ca.pem -etcd-certfile=${ssl_dir}/etcd.pem -etcd-keyfile=${ssl_dir}/etcd-key.pem -iface=ens32"
EOF

for svc in {flanneld,docker,kubelet}
do
systemctl daemon-reload
systemctl enable ${svc}
systemctl start ${svc}
systemctl status ${svc}
done
ip address show dev docker0
