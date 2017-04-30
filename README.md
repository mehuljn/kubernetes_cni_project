# Kubernetes IPSEC CNI Project

## Description
This is a project that sets up a Kubernetes Cluster and configures the minions via CNI Plugin for allocation of POD ips which are configured for IPSEC.
The CNI code is implemented in Python

The Vagrantfile spins up a kubernetes cluster (One Master and 3 Minion Nodes).

## How to use

### First lets start the kubernetes master. This configures certs and also authentication. At the end gives the TOKEN CODE which needs to be updated in Vagrant file
```
vagrant up master
```

### Second update the token code in Vagrantfile for minions. Then start the minions one-by-one
```
vagrant up minion1
vagrant up minion2
vagrant up minion3
```

### Check all health using the commands below after login to master. All should show healthy and ready.
``` 
vagrant ssh master
kubectl get componentstatuses
kubectl get nodes
```

### Also to the minions and verify if the ipsec tunnel is up and running
```
vagrant ssh minionX
ipsec status
(if not running use the command below to start the ipsec tunnels e.g on minion1)
ipsec up minion2
ipsec up minion3
```
