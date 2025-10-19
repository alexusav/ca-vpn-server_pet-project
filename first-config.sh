#!/bin/bash

#UNINSTALL=(firewalld)
#prometheus prometheus-alertmanager
INSTALL=(iptables iptables-persistent prometheus-node-exporter)
#INSTALL=(firewalld)

#Checking the run from root
if [[ "$EUID" -ne 0 ]]; then
    echo "I need root privileges."
    exit 1
fi


#Uninstall firewall
if apt-get remove -y firewalld
then
	echo "========= Remove firewalld pakage ============"
fi


#apt-get update
echo "============= Update pakage ============="

#installed pakages
for pakage in ${INSTALL[@]}
do
	#checking installed pakage
	if dpkg -l $pakage 2>&1 | grep ii &>/dev/null
	then
		echo "Pakage $pakage is installed ++++++++++++"
	else
		if apt-get install -y $pakage
		then
			echo "Install SUCCESS $pakage ========="
		else
			echo "Install $pakage FAILED! ============"
			exit 1
		fi
	fi
done

#configure ssh /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*$/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#*Port.*$/Port 2222/' /etc/ssh/sshd_config
sed -i 's/^#*PubkeyAuthentication.*$/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo service ssh restart


#enable iptables
if systemctl status iptables
then
	systemctl enable iptables
	systemctl start iptables
fi

#configure iptables
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT -m comment --comment dns
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT -m comment --comment dns
iptables -A OUTPUT -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p tcp --dport 2222 -j ACCEPT -m comment --comment ssh
iptables -I OUTPUT -p tcp --dport 2222 -j ACCEPT -m comment --comment ssh_to_lan
iptables -A OUTPUT -p tcp -m multiport --dports 443,80 -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -m state --state INVALID -j DROP
iptables -A INPUT -m state --state INVALID -j DROP
iptables -P OUTPUT DROP
iptables -P INPUT DROP
iptables -P FORWARD DROP

service iptables-persistent save
service netfilter-persistent save



