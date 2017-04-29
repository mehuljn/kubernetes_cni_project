#!/bin/bash
#Provision Kubernetes Master based on https://www.joyent.com/blog/kubernetes-the-hard-way and 
#https://github.com/kelseyhightower/kubernetes-the-hard-way/blob/master/docs/

#ENVs REQUIRED
export IP=${IP:-192.168.10.10}
export IPS=${IPS:-"\"192.168.10.10\","}
export INITIAL_CLUSTER=${INITIAL_CLUSTER:-"master=https://192.168.10.10:2380"}
export ETCD_CLIENT_ACCESS=${ETCD_CLIENT_ACCESS:-https://192.168.10.10:2379}

apt-get update

# For cert generation
wget --no-verbose -O /usr/local/bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
wget --no-verbose -O /usr/local/bin/cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
chmod +x /usr/local/bin/cfssl
chmod +x /usr/local/bin/cfssljson

# Config setup for Cert Generation
echo '{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}' > ca-config.json


echo '{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IN",
      "L": "Mumbai",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "MH"
    }
  ]
}' > ca-csr.json

cfssl gencert -initca ca-csr.json | cfssljson -bare ca

cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "hosts": [
    "kubernetes",
    $IPS
    "127.0.0.1"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IN",
      "L": "Mumbai",
      "O": "Kubernetes",
      "OU": "Cluster",
      "ST": "MH"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes


# Setup ETCD
wget https://github.com/coreos/etcd/releases/download/v3.1.6/etcd-v3.1.6-linux-amd64.tar.gz
tar -xvf etcd-v3.1.6-linux-amd64.tar.gz 
mv etcd-v3.1.6-linux-amd64/etcd* /usr/bin/

mkdir -p /var/lib/etcd /etc/etcd/
cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/

cp /dev/stdin /etc/systemd/system/etcd.service <<< "[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
ExecStart=/usr/bin/etcd --name master \
  --cert-file=/etc/etcd/kubernetes.pem \
  --key-file=/etc/etcd/kubernetes-key.pem \
  --peer-cert-file=/etc/etcd/kubernetes.pem \
  --peer-key-file=/etc/etcd/kubernetes-key.pem \
  --trusted-ca-file=/etc/etcd/ca.pem \
  --peer-trusted-ca-file=/etc/etcd/ca.pem \
  --initial-advertise-peer-urls https://$IP:2380 \
  --listen-peer-urls https://$IP:2380 \
  --listen-client-urls https://$IP:2379,http://127.0.0.1:2379 \
  --advertise-client-urls https://$IP:2379 \
  --initial-cluster-token etcd-cluster-0 \
  --initial-cluster $INITIAL_CLUSTER \
  --initial-cluster-state new \
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
"

systemctl daemon-reload 
systemctl enable etcd.service 
systemctl start etcd.service 

# Download all Kubernetes Binaries
wget --no-verbose -P /usr/local/bin/ https://storage.googleapis.com/kubernetes-release/release/v1.6.1/bin/linux/amd64/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl}
chmod +x /usr/local/bin/{kube-apiserver,kube-controller-manager,kube-scheduler,kubectl}

# Setup cert for Kubernetes 
mkdir -p /var/lib/kubernetes
cp ca.pem kubernetes-key.pem kubernetes.pem /var/lib/kubernetes/

COMMON_TOKEN=${COMMON_TOKEN:=$(head /dev/urandom | base32 | head -c 8)}
echo "Your common token is: ${COMMON_TOKEN}. Please update this in Vagrantfile for Minion Startup"
cp /dev/stdin /var/lib/kubernetes/token.csv <<< "${COMMON_TOKEN},admin,admin
${COMMON_TOKEN},scheduler,scheduler
${COMMON_TOKEN},kubelet,kubelet
"

cp /dev/stdin /var/lib/kubernetes/authorization-policy.jsonl <<< '{"apiVersion": "abac.authorization.kubernetes.io/v1beta1", "kind": "Policy", "spec": {"user":"*", "nonResourcePath": "*", "readonly": true}}
{"apiVersion": "abac.authorization.kubernetes.io/v1beta1", "kind": "Policy", "spec": {"user":"admin", "namespace": "*", "resource": "*", "apiGroup": "*"}}
{"apiVersion": "abac.authorization.kubernetes.io/v1beta1", "kind": "Policy", "spec": {"user":"scheduler", "namespace": "*", "resource": "*", "apiGroup": "*"}}
{"apiVersion": "abac.authorization.kubernetes.io/v1beta1", "kind": "Policy", "spec": {"user":"kubelet", "namespace": "*", "resource": "*", "apiGroup": "*"}}
{"apiVersion": "abac.authorization.kubernetes.io/v1beta1", "kind": "Policy", "spec": {"group":"system:serviceaccounts", "namespace": "*", "resource": "*", "apiGroup": "*", "nonResourcePath": "*"}}
'
# Setup Kube api 
cp /dev/stdin /etc/systemd/system/kube-apiserver.service <<< \
"[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \
  --admission-control=NamespaceLifecycle,LimitRanger,SecurityContextDeny,ServiceAccount,ResourceQuota \
  --advertise-address=${IP} \
  --allow-privileged=true \
  --apiserver-count=3 \
  --authorization-mode=ABAC \
  --authorization-policy-file=/var/lib/kubernetes/authorization-policy.jsonl \
  --bind-address=0.0.0.0 \
  --enable-swagger-ui=true \
  --etcd-cafile=/var/lib/kubernetes/ca.pem \
  --insecure-bind-address=0.0.0.0 \
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \
  --etcd-servers=${ETCD_CLIENT_ACCESS} \
  --service-account-key-file=/var/lib/kubernetes/kubernetes-key.pem \
  --service-cluster-ip-range=10.30.0.0/24 \
  --service-node-port-range=30000-32767 \
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \
  --token-auth-file=/var/lib/kubernetes/token.csv \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
"


systemctl daemon-reload
systemctl enable kube-apiserver
systemctl start kube-apiserver

# Setup Kube Controller Manager
cp /dev/stdin /etc/systemd/system/kube-controller-manager.service <<< \
"[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \
  --cluster-name=kubernetes \
  --leader-elect=true \
  --master=http://$IP:8080 \
  --root-ca-file=/var/lib/kubernetes/ca.pem \
  --service-account-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \
  --service-cluster-ip-range=10.30.0.0/16 \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
"

systemctl daemon-reload
systemctl enable kube-controller-manager
systemctl start kube-controller-manager

# Setup Kube Scheduler
cp /dev/stdin /etc/systemd/system/kube-scheduler.service <<< \
"[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \
  --leader-elect=true \
  --master=http://$IP:8080 \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
"

systemctl daemon-reload
systemctl enable kube-scheduler
systemctl start kube-scheduler

# Setup http service for Minions to get certs 
apt-get install -y apache2
cp ca.pem kubernetes.pem kubernetes-key.pem /var/www/html/
chmod 666 /var/www/html/kubernetes-key.pem
