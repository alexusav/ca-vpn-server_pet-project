#!/bin/bash

# Checking the run from root
if [[ "$EUID" -ne 0 ]]; then
    echo "I need root privileges."
    exit 1
fi

if [[ $# -gt 0 ]]
then

	KEY_DIR=/etc/openvpn/server
	OUTPUT_DIR=/etc/openvpn/client
	BASE_CONFIG=/etc/openvpn/client/base.conf

cat ${BASE_CONFIG} \
    <(echo -e '<ca>') \
    ${KEY_DIR}/ca.crt \
    <(echo -e '</ca>\n<cert>') \
    ${OUTPUT_DIR}/${1}.crt \
    <(echo -e '</cert>\n<key>') \
    ${OUTPUT_DIR}/${1}.key \
    <(echo -e '</key>\n<tls-crypt>') \
    ${KEY_DIR}/ta.key \
    <(echo -e '</tls-crypt>') \
    > ${OUTPUT_DIR}/${1}.ovpn
else
	echo "I need one parameter - name client."
	exit 1
fi
