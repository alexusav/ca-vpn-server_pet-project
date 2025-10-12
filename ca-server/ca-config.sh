#!/bin/bash


#Checking the run from root
if [[ "$EUID" -ne 0 ]]; then
    echo "I need root privileges."
    exit 1
fi

apt-get update
#Install easyrsa
if sudo dpkg -l easy-rsa 2>&1 | grep ii &>/dev/null
then
        echo "Pakage easy-rsa is installed ++++++++++++"
else
	if sudo apt-get install -y easy-rsa
        then
                echo "Install SUCCESS easy-rsa ========="
        else
                echo "Install easy-rsa FAILED! ============"
                exit 1
        fi
fi


#set -x
#Create directory easyrsa
if ! test -e /var/easy-rsa
then
	mkdir /var/easy-rsa
	chmod +rw /var/easy-rsa
	echo "Create directory /var/easy-rsa ============"
	ln -s /usr/share/easy-rsa/* /var/easy-rsa/
	echo "Create links files /var/easy-rsa ============"
else
	echo "The directory /var/easy-rsa exist ============"
fi


#Start init easyrsa
if test -f /var/easy-rsa/easyrsa
then
	cd /var/easy-rsa
	if bash /var/easy-rsa/easyrsa init-pki 
	then
		echo "/var/easy-rsa/pki"
		if test -d "/var/easy-rsa/pki"
		then
			rm "/var/easy-rsa/pki/vars.example"
			cp "/var/easy-rsa/vars.example" "/var/easy-rsa/pki/vars"
			echo "EASYRSA init was SUCCESSFUL ============"
		else
			echo "ERROR init easyrsa =============="
		fi
	else
		echo "ERROR creation easyrsa ==========="
		exit 1
	fi
else
	echo "File /var/easy-rsa/easyrsa not found "
	exit 1
fi


#Edit vars
if test -f "/var/easy-rsa/pki/vars"
then
	sed -i 's/^#*set_var EASYRSA_REQ_COUNTRY.*$/set_var EASYRSA_REQ_COUNTRY     "RUS"/' "/var/easy-rsa/pki/vars"
	sed -i 's/^#*set_var EASYRSA_REQ_PROVINCE.*$/set_var EASYRSA_REQ_PROVINCE    "Astrakhan region"/' "/var/easy-rsa/pki/vars"
	sed -i 's/^#*set_var EASYRSA_REQ_CITY.*$/set_var EASYRSA_REQ_CITY        "Astrakhan"/' "/var/easy-rsa/pki/vars"
	sed -i 's/^#*set_var EASYRSA_REQ_ORG.*$/set_var EASYRSA_REQ_ORG         "MyCompany"/' "/var/easy-rsa/pki/vars"
	sed -i 's/^#*set_var EASYRSA_REQ_EMAIL.*$/set_var EASYRSA_REQ_EMAIL       "support@mycompany.ru"/' "/var/easy-rsa/pki/vars"
	sed -i 's/^#*set_var EASYRSA_REQ_OU.*$/set_var EASYRSA_REQ_OU          "DevOps"/' "/var/easy-rsa/pki/vars"
	sed -i 's/^#*set_var EASYRSA_ALGO.*$/set_var EASYRSA_ALGO            ec/' "/var/easy-rsa/pki/vars"
	sed -i 's/^#*set_var EASYRSA_DIGEST.*$/set_var EASYRSA_DIGEST          "sha512"/' "/var/easy-rsa/pki/vars"
	echo "File VARS edit SUCCESFUL ================"
else
	echo "ERROR File vars.example not fount"
	exit 1
fi



#Start create build-ca
if ! test -f "/var/easy-rsa/pki/ca.crt"
then
	if bash /var/easy-rsa/easyrsa build-ca
	then
		echo "CA creation SUCCESSFUL! ============="
	else
		echo "ERROR creation CA ============"
		exit 1
	fi
else
	echo "The CA.crt file exists ++++++++++"
fi

#Start create servers crt
if test -d "/var/easy-rsa/pki"
then
	#if bash /var/easy-rsa/easyrsa gen-req MyCompany nopass
	if bash /var/easy-rsa/easyrsa --subject-alt-name="DNS:ca.mycompany.ru,DNS:ca.mycompany.ru,DNS:localhost,IP:10.130.0.8,IP:127.0.0.1" build-server-full ca.mycompany.ru nopass
	then 
		echo "Creation req SUCCESSFUL +++++++++++"
		
		if bash /var/easy-rsa/easyrsa sign-req server MyCompany
		then
			echo "Creation sign SUCCESSFUL ++++++++"
		else
			echo "ERROR no sign sert ============"
			exit 1
		fi
	else
		echo "ERROR no creation req ============="
		exit 1
	fi
else
	echo "ERROR Directory /var/easy-rsa/pki not found =========="
fi

#Start creatinon client crt
if test -d "/var/easy-rsa/pki"
then
        if bash /var/easy-rsa/easyrsa gen-req iamclient nopass
        then
                echo "Creation req SUCCESSFUL +++++++++++"

                if bash /var/easy-rsa/easyrsa sign-req client iamclient
                then
                        echo "Creation sign SUCCESSFUL ++++++++"
                else
                        echo "ERROR no sign sert ============"
                        exit 1
                fi
        else
                echo "ERROR no creation req ============="
                exit 1
        fi
else
        echo "ERROR Directory /var/easy-rsa/pki not found =========="
fi



