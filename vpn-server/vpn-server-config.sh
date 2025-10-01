#!/bin/bash


# Checking the run from root
if [[ "$EUID" -ne 0 ]]; then
    echo "I need root privileges."
    exit 1
fi

#TODO
# Install openvpn
if sudo dpkg -l openvpn 2>&1 | grep ii &>/dev/null
then
        echo "Pakage openvpn is installed ++++++++++++"
else
        apt-get update
	if sudo apt-get install -y openvpn
        then
                echo "Install SUCCESS openvpn ========="
        else
                echo "Install openvpn FAILED! ============"
                exit 1
        fi
fi


#Copy example config file
if test -f "/usr/share/doc/openvpn/examples/sample-config-files/server.conf"
then
	if cp "/usr/share/doc/openvpn/examples/sample-config-files/server.conf" "/etc/openvpn/server/"
	then
		sed -i 's/^#*;*dh .*$/dh none/' "/etc/openvpn/server/server.conf"
		sed -i '/^;*tls-auth .*$/s/^/;/; /^;*tls-auth .*$/a tls-crypt ta.key' "/etc/openvpn/server/server.conf"
		sed -i -e '/^;data-ciphers AES-256-GCM.*$/a cipher AES-256-GCM\nauth SHA256' -e 's/^cipher AES-256-.*$/cipher AES-256-GCM\nauth SHA256/' "/etc/openvpn/server/server.conf"
		sed -i 's/^#*;*user .*$/user nobody/' "/etc/openvpn/server/server.conf"
		sed -i 's/^#*;*group .*$/group nogroup/' "/etc/openvpn/server/server.conf"
		
	else
		echo "ERROR copy configure file ---------------"
		exit 1
	fi
else
	echo "ERROR file example server.conf not found ----------------"
	exit 1
fi


# Insert parameter for routes
if test -f "/etc/sysctl.conf"
then
	sed -i 's/^[;#]*\s*net\.ipv4\.ip_forward=.*$/net.ipv4.ip_forward=1/' "/etc/sysctl.conf"
	echo "File sysctl.conf rewrite +++++++++++++"
else
	echo "net.ipv4.ip_forward=1" | sudo tee "/etc/sysctl.conf" > /dev/null
	echo "Create file /etc/sysctl.conf and insert parameter +++++++++++"
fi

# Restart sysctl
sysctl -p

# Enable and start openvpn-server
systemctl -f enable openvpn-server@server.service
sudo systemctl -f enable openvpn-server@server.service

# Create client configure
if ! test -f /etc/openvpn/client/base.conf
then 
	if test -f /usr/share/doc/openvpn/examples/sample-config-files/client.conf
	then
		cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf /etc/openvpn/client/base.conf
		echo "File base.conf copied ++++++++++++"
		remote_ip=$(curl icanhazip.com)
		echo "Get wite IP address $remote_ip ++++++++++++"

		if [[ "$remote_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
	       	then
			sed -i "s/^remote .*$/remote $remote_ip 1194/"     "/etc/openvpn/client/base.conf"
		else
			echo "Get IP incorrect -------"
			read -p "Введите IP-адрес: " remote_ip
			sed -i "s/^remote .*$/remote $remote_ip 1194/"  "/etc/openvpn/client/base.conf"
		fi
		sed -i 's/^#*;*user .*$/user nobody/' "/etc/openvpn/client/base.conf"
                sed -i 's/^#*;*group .*$/group nogroup/' "/etc/openvpn/client/base.conf"
		sed -i '/^ca ca.crt$/s/^/;/' "/etc/openvpn/client/base.conf"
		sed -i '/^cert client.crt$/s/^/;/' "/etc/openvpn/client/base.conf"
		sed -i '/^key client.key$/s/^/;/' "/etc/openvpn/client/base.conf"
		sed -i '/^;*tls-auth .*$/s/^/;/; /^;*tls-auth .*$/a tls-crypt ta.key 1' "/etc/openvpn/client/base.conf"
                sed -i -e '/^;data-ciphers AES-256-GCM.*$/a cipher AES-256-GCM\nauth SHA256' -e 's/^cipher AES-256-.*$/cipher AES-256-GCM\nauth SHA256/' "/etc/openvpn/client/base.conf"
		sed -i '/^key-direction 1$/d; $a key-direction 1' "/etc/openvpn/client/base.conf"
		echo "File configure client create SUCCEESS ++++++++"
	else
		echo "File examples/sample-config-files/client.conf not found -----------"
	fi
else
	echo "File /etc/openvpn/client/base.conf existing +++++++"
fi


# Create iptables for VPN
# OpenVPN
# TODO name interface
iptables -A INPUT -i eth0 -m state --state NEW -p udp --dport 1194 -j ACCEPT -m comment --comment openvpn
# Allow TUN interfaces connections to OpenVPN server
iptables -A INPUT -i tun+ -j ACCEPT -m comment --comment openvpn
# Allow TUN interfaces connections to be forwarded through interfaces
iptables -A FORWARD -i tun+ -j ACCEPT -m comment --comment openvpn
iptables -A FORWARD -i tun+ -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT -m comment --comment openvpn
iptables -A FORWARD -i eth0 -o tun+ -m state --state RELATED,ESTABLISHED -j ACCEPT -m comment --comment openvpn
# NAT the VPN client traffic to the interface
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE -m comment --comment openvpn

# Restart openvpn-server
sudo systemctl restart openvpn-server@server.service
sudo systemctl enable openvpn-server@server.service



if test -f /etc/openvpn/server/ca.crt
then
        if test -f /etc/openvpn/server/server.crt && test -f /etc/openvpn/server/server.key
        then
                cd /etc/openvpn/server/
                openvpn --genkey --secret ta.key
                echo "Generate ta.key SUCCESS ++++++++"
        else
                echo "File server.crt not found -----------"
		echo "You need copy server.crt and server.key cert to directory /etc/openvpn/server"
                exit 1
        fi
else
        echo "File ca.crt not found --------------"
	echo "You need copy ca.crt cert to directory /etc/openvpn/server"
fi

