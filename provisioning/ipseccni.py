#!/usr/bin/python

import os
import sys
import netaddr
from netaddr import *
import json
from pyroute2 import *

cni_command=""
cni_netns=""
cni_container=""
cni_ifname=""

bridgename=""
subnet=""
subnet_gw=""

alloc_ips_file="/var/cni/alloc_ips"
alloc_ips=[]
allips=[]
finalip=[]
finalip_str=""



def load_env_variable():
        global cni_command
        global cni_netns
        global cni_container
        global cni_ifname
	if os.environ.has_key('CNI_COMMAND') and os.environ.has_key("CNI_NETNS") \
	   and os.environ.has_key("CNI_CONTAINERID") and os.environ.has_key("CNI_IFNAME"): 
		cni_command=os.environ['CNI_COMMAND']
		cni_netns=os.environ['CNI_NETNS']
		cni_container=os.environ['CNI_CONTAINERID']
		cni_ifname=os.environ['CNI_IFNAME']
	else:
		exit(1)

def load_stdin_conf():
        global bridgename
        global subnet
        global subnet_gw
	data=json.load(sys.stdin)
	bridgename=data['bridge']
	subnet=data['subnet']
	subnet_gw=data['subnet_gw']

def load_and_check_alloc_ips():
        global alloc_ips
	if not os.path.exists(alloc_ips_file):
		alloc_ips=[]
	else:
		with open(alloc_ips_file) as handle:
			alloc_ips = handle.read().splitlines()

def find_next_ip():
        global subnet
        global alloc_ips
        global finalip
        global finalip_str
	#Get all ips in subnet
	ipn = IPNetwork(subnet)
	ip_list = list(ipn)
	ip_list_str = [ str(ip) for ip in ip_list ]
    	finalip = [ip for ip in ip_list_str+alloc_ips if ip not in ip_list_str or ip not in alloc_ips]
    	finalip_str=finalip[3]

def assign_ip_to_container():
        global cni_container
        global cni_ifname
        global cni_netns
        global finalip_str
        global alloc_ips_file
	ipr = IPRoute()
	host_iname="veth" + cni_container[:4]
	ipr.link('add', ifname=host_iname, kind='veth', peer=cni_ifname)
	idx = ipr.link_lookup(ifname=cni_ifname)[0]
	ipr.link('set', index=idx, net_ns_fd=cni_netns)
	ipr.close()

	ipdb_namespace = IPDB(nl=NetNS(cni_netns))
	with ipdb_namespace.interfaces[cni_ifname] as veth:
    		veth.add_ip(finalip_str+"/24")
    		veth.up()
    	ipdb_namespace.release()
    	with open(alloc_ips_file,'a') as fileh:
    		fileh.write(finalip_str+"\n")
    
def delete_assignment():
        global cni_container
        global cni_ifname
        global cni_netns
        global finalip_str
        global alloc_ips_file
	ipdb_namespace = IPDB(nl=NetNS(cni_netns))
        myip=ipdb_namespace.interfaces[cni_ifname].ipaddr
        myip_str=myip[0]['address']
	ipdb_namespace.interfaces[cni_ifname].remove().commit()
	with open(alloc_ips_file) as fileh:
    		alloc_ips=fileh.read().splitlines()
    	num=alloc_ips.index(myip_str)
    	del alloc_ips[num]
    	with open(alloc_ips_file,"r+") as nfileh:
                line=nfileh.read()
                nfileh.seek(0)
                nfileh.truncate()
    		for ip in alloc_ips:
    			nfileh.write("%s\n" % ip)



load_env_variable()
load_stdin_conf()
load_and_check_alloc_ips()
if os.environ['CNI_COMMAND'] in ["ADD"]:
	find_next_ip()
	assign_ip_to_container()
else:
	delete_assignment()
