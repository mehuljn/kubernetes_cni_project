# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|

  if Vagrant.has_plugin?("vagrant-cachier")
    config.cache.scope = :machine
  end

  config.vm.provider :virtualbox do |virtualbox|
     virtualbox.customize ["modifyvm", :id, "--memory", 3072]
     virtualbox.customize ["modifyvm", :id, "--cpus", 2]
  end


  config.vm.define "master" do |master|
    master.vm.box = "ubuntu/xenial64"
    master.vm.hostname = "master"
    master.vm.network :private_network, ip: "192.168.10.10"

    master.vm.provision "shell", path: "provisioning/provision_master.sh", env: { \
      "IP" => "192.168.10.10", \
      "IPS" => "\"192.168.10.10\",", \
       "INITIAL_CLUSTER" => "\"master=https://192.168.10.10:2380\"" ,\
        "ETCD_CLIENT_ACCESS" => "https://192.168.10.10:2379"}
  end 
 

  config.vm.define "minion1" do |minion1|
    minion1.vm.box = "ubuntu/xenial64"
    minion1.vm.hostname = "minion1" 
    minion1.vm.network :private_network, ip: "192.168.10.21"

    minion1.vm.provision "shell", path: "provisioning/provision_node.sh", env: { \
        "CERT_MASTER" => "http://192.168.10.10",\
        "CONTROLLER0" => "https://192.168.10.10:6443",\
        "COMMON_TOKEN" => "DCS3LWLQ",\
        "API_SERVERS" => "https://192.168.10.10:6443",\
        "MYSUBNET" => '"10.240.10.0/24"',\
        "MYSUBNET_GW" => '"10.240.10.1"',\
        "MYNODE" =>"minion1",\
        "OTHERSUBNETS_1" => "10.240.20.0/24","OTHERNODE_1" => "minion2","OTHERNODE_1_IP" => "192.168.10.22",\
        "OTHERSUBNETS_2" => "10.240.30.0/24","OTHERNODE_2" => "minion3","OTHERNODE_2_IP" => "192.168.10.23"}
  end

  config.vm.define "minion2" do |minion2|
    minion2.vm.box = "ubuntu/xenial64"
    minion2.vm.hostname = "minion2" 
    minion2.vm.network :private_network, ip: "192.168.10.22"

    minion2.vm.provision "shell", path: "provisioning/provision_node.sh", env: { \
        "CERT_MASTER" => "http://192.168.10.10",\
        "CONTROLLER0" => "https://192.168.10.10:6443",\
        "COMMON_TOKEN" => "DCS3LWLQ",\
        "API_SERVERS" => "https://192.168.10.10:6443",\
        "MYSUBNET" => "10.240.20.0/24",\
        "MYSUBNET_GW" => "10.240.20.1",\
        "MYNODE" =>"minion2",\
        "OTHERSUBNETS_1" => "10.240.10.0/24","OTHERNODE_1" => "minion1","OTHERNODE_1_IP" => "192.168.10.21",\
        "OTHERSUBNETS_2" => "10.240.30.0/24","OTHERNODE_2" => "minion3","OTHERNODE_2_IP" => "192.168.10.23"}

  end

  config.vm.define "minion3" do |minion3|
    minion3.vm.box = "ubuntu/xenial64"
    minion3.vm.hostname = "minion3" 
    minion3.vm.network :private_network, ip: "192.168.10.23"

    minion3.vm.provision "shell", path: "provisioning/provision_node.sh", env: { \
        "CERT_MASTER" => "http://192.168.10.10",\
        "CONTROLLER0" => "https://192.168.10.10:6443",\
        "COMMON_TOKEN" => "DCS3LWLQ",\
        "API_SERVERS" => "https://192.168.10.10:6443",\
        "MYSUBNET" => "10.240.30.0/24",\
        "MYSUBNET_GW" => "10.240.30.1",\
        "MYNODE" =>"minion3",\
        "OTHERSUBNETS_1" => "10.240.10.0/24","OTHERNODE_1" => "minion1","OTHERNODE_1_IP" => "192.168.10.21",\
        "OTHERSUBNETS_2" => "10.240.20.0/24","OTHERNODE_2" => "minion2","OTHERNODE_2_IP" => "192.168.10.22"}
  end
end
