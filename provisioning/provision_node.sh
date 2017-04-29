#!/bin/bash
#Provision Kubernetes Minion based on https://www.joyent.com/blog/kubernetes-the-hard-way and 
#https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/

#ENV
export CERT_MASTER=${CERT_MASTER:-http://192.168.10.10}
export CONTROLLER0=${CONTROLLER0:-https://192.168.10.10:6443}
export COMMON_TOKEN=${COMMON_TOKEN:-"DCS3LWLQ"}
export API_SERVERS=${API_SERVERS:-https://192.168.10.10:6443}
export MYSUBNET=${MYSUBNET:-\""10.240.10.0/24\""}
export MYSUBNET_GW=${MYSUBNET_GW:-\""10.240.10.1\""}
export MYNODE=${MYNODE:-"minion1"}
export OTHERSUBNETS_1=${OTHERSUBNETS_1:-"10.240.20.0/24"}
export OTHERNODE_1=${OTHERNODE_1:-"minion2"}
export OTHERNODE_1_IP=${OTHERNODE_1_IP:-"192.168.10.22"}
export OTHERSUBNETS_2=${OTHERSUBNETS_2:-"10.240.30.0/24"}
export OTHERNODE_2=${OTHERNODE_2:-"minion3"}
export OTHERNODE_2_IP=${OTHERNODE_2_IP:-"192.168.10.23"}

apt-get update
apt-get install -y strongswan python python-pip

# Get Docker
#wget https://get.docker.com/builds/Linux/x86_64/docker-1.12.6.tgz
wget $CERT_MASTER/docker-1.12.6.tgz
tar -xvf docker-1.12.6.tgz
cp docker/docker* /usr/bin/

# Get certs from Master http server
wget ${CERT_MASTER}/ca.pem
wget ${CERT_MASTER}/kubernetes-key.pem
wget ${CERT_MASTER}/kubernetes.pem
chmod 600 kubernetes-key.pem

mkdir -p /var/lib/kubernetes
cp ca.pem kubernetes-key.pem kubernetes.pem /var/lib/kubernetes/

# Setup Docker
cp /dev/stdin /etc/systemd/system/docker.service <<< \
"[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io

[Service]
ExecStart=/usr/bin/dockerd \
  --iptables=false \
  --ip-masq=false \
  --host=unix:///var/run/docker.sock \
  --log-level=error \
  --storage-driver=overlay
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target"

systemctl daemon-reload
systemctl enable docker
systemctl start docker

# Setup CNI
mkdir -p /opt/cni
wget --no-verbose https://storage.googleapis.com/kubernetes-release/network-plugins/cni-07a8a28637e97b22eb8dfe710eeae1344f69d16e.tar.gz
#wget --no-verbose $CERT_MASTER/cni-07a8a28637e97b22eb8dfe710eeae1344f69d16e.tar.gz
tar -xvf cni-07a8a28637e97b22eb8dfe710eeae1344f69d16e.tar.gz -C /opt/cni

mkdir -p /etc/cni/net.d
echo '{
    "name": "ipseccni",
    "type": "ipseccni",
    "bridge": "ipseccni-br0",
    "isGateway": "true",
    "ipMasq": "true",
    "subnet": '$MYSUBNET',
    "subnet_gw" : '$MYSUBNET_GW'
}' >/etc/cni/net.d/10-ipseccni.conf  

# setup Bridge for IPSECCNI
ip link add ipseccni-br0 type bridge
ip link set ipseccni-br0 up 
ip address add $MYSUBNET_GW dev ipseccni-br0

# Get Kubernetes Binaries
wget --no-verbose -P /usr/bin https://storage.googleapis.com/kubernetes-release/release/v1.6.1/bin/linux/amd64/{kubectl,kube-proxy,kubelet}
#wget --no-verbose -P /usr/bin $CERT_MASTER/{kubectl,kube-proxy,kubelet}
chmod +x /usr/bin/{kubectl,kube-proxy,kubelet}

mkdir -p /var/lib/kubelet/
# Setup Kubeconfig
cp /dev/stdin /var/lib/kubelet/kubeconfig <<< \
"apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: /var/lib/kubernetes/ca.pem
    server: ${CONTROLLER0}
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kubelet
  name: kubelet
current-context: kubelet
users:
- name: kubelet
  user:
    token: $COMMON_TOKEN"

# Setup Kubelet
cp /dev/stdin /etc/systemd/system/kubelet.service <<< \
"[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/bin/kubelet \
  --allow-privileged=true \
  --api-servers=${API_SERVERS} \
  --cluster-dns=10.32.0.10 \
  --cluster-domain=cluster.local \
  --container-runtime=docker \
  --network-plugin=cni \
  --kubeconfig=/var/lib/kubelet/kubeconfig \
  --serialize-image-pulls=false \
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \
  --v=2

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target"


systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet

#Setup Kube Proxy
cp /dev/stdin /etc/systemd/system/kube-proxy.service <<< \
"[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/bin/kube-proxy \
  --masquerade-all \
  --master=${CONTROLLER0} \
  --kubeconfig=/var/lib/kubelet/kubeconfig \
  --proxy-mode=iptables \
  --v=2

Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target"

systemctl daemon-reload
systemctl enable kube-proxy
systemctl start kube-proxy


#Setup IPSEC Secrets
echo "
: PSK \"ipseccnisecret\"
" > /etc/ipsec.secrets

# Setup IPSEC Host to Host
echo "
config setup

conn %default
  ikelifetime=60m
  keylife=20m
  rekeymargin=3m
  keyingtries=1
  keyexchange=ikev2
  authby=psk

conn $OTHERNODE_1
  left=%defaultroute
  leftsubnet=$MYSUBNET
  leftid=$MYNODE
  leftfirewall=yes
  rightid=$OTHERNODE_1
  right=$OTHERNODE_1_IP
  rightsubnet=$OTHERSUBNETS_1
  auto=add

conn $OTHERNODE_2
  left=%defaultroute
  leftsubnet=$MYSUBNET
  leftid=$MYNODE
  leftfirewall=yes
  rightid=$OTHERNODE_2
  right=$OTHERNODE_2_IP
  rightsubnet=$OTHERSUBNETS_2
  auto=add

" > /etc/ipsec.conf

ipsec restart 

export LC_ALL=C
mkdir /var/cni/
cp /vagrant/provisioning/ipseccni.py /opt/cni/bin/
pip install -r /vagrant/requirements