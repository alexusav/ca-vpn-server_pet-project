#!/bin/bash

INSTALL=(prometheus prometheus-alertmanager nginx apache2-utils prometheus-nginx-exporter)

#Checking the run from root
if [[ "$EUID" -ne 0 ]]; then
    echo "I need root privileges."
    exit 1
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


#Config iptables from prometheus

iptables -I INPUT -p tcp --dport 9090 -j ACCEPT -m comment --comment prometheus
iptables -I INPUT -p tcp -m multiport --dports 80,8080 -j ACCEPT -m comment --comment http
iptables -I INPUT -p tcp --dport 443 -j ACCEPT -m comment --comment https
iptables -I INPUT -p tcp -s 10.130.0.7 --dport 9100 -j ACCEPT -m comment --comment prometheus_node_exporter
iptables -I OUTPUT -p tcp -d 10.130.0.0/24 --dport 9100 -j ACCEPT -m comment --comment Prometheus_node_exporter
iptables -I OUTPUT -p tcp -d 10.130.0.0/24 --dport 9176 -j ACCEPT -m comment --comment prometheus_openvpn_exporter
iptables -I OUTPUT -p tcp -d 10.130.0.0/24 --dport 9113 -j ACCEPT -m comment --comment prometheus_nginx_exporter
iptables -A INPUT -p tcp --dport 9093 -j ACCEPT -m comment --comment prometheus_alertmanager
iptables -A OUTPUT -p tcp --dport 587 -j ACCEPT -m comment --comment smtp


service netfilter-persistent save


 

