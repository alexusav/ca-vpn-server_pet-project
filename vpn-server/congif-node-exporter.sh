#!/bin/bash

SERVER_MON_IP="10.130.0.7"

# Проверяем наличие директории с настройками для экспортера
if test -d /opt/node_exporter
then
	echo "Директория /opt/node_exporter существует +++++++++++++"
else
	if mkdir /opt/node_exporter
	then
		echo "Директория /opt/node_exporter успешно создана +++++++++++++"
	else
		echo "Ошибка: не удалось создать директорию /opt/node_exporter.Возможно, такая учетная запись уже существует?"
    		exit 1
	fi
fi

# Записываем в файл настроек данные
cat > /opt/node_exporter/basic_auth.yml << 'EOF'
tls_server_config:
  cert_file: vpn.mycompany.ru.crt
  key_file: vpn.mycompany.ru.key

basic_auth_users:
  prometheus_user: $2y$10$riifNUIBJITdJjufmFeIAuqd0V87DqopG.TnLDnHPYQt5JBQ/dxaS
EOF

# Проверка, что файл создан успешно
if [ -f "/opt/node_exporter/basic_auth.yml" ]; then
    echo "Файл basic_auth.yml успешно создан"
else
    echo "Ошибка: файл basic_auth.yml не был создан"
    exit 1
fi

# Проверка наличия файла конфига экспортера и модернизация
if test -f "/etc/default/prometheus-node-exporter"
then
	sed -i 's/^ARGS=.*$/ARGS="--web.config=\/opt\/node_exporter\/basic_auth.yml"/' "/etc/default/prometheus-node-exporter"
	echo "Конфиг node-exporte изменен +++++++++"
	systemctl restart prometheus-node-exporter
else
	echo "Файл prometheus-node-exporte не существует -------------"
fi

# Добавление правила
iptables -I INPUT -p tcp -s ${SERVER_MON_IP} --dport 9100 -j ACCEPT -m comment --comment prometheus_node_exporter

#service iptables-persistent save
service netfilter-persistent save
