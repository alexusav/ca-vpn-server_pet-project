#!/bin/bash

# Скрипт настройки SSH доступа для пользователя yc-user
# Проверка прав суперпользователя
if [ "$EUID" -ne 0 ]; then
    echo "Этот скрипт должен запускаться с правами root"
    exit 1
fi

USERNAME="yc-user"
#USERNAME="administrator"
SSH_DIR="/home/$USERNAME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"
CONFIG_DIR="/etc/ssh/ssh_config.d"
CONFIG_FILE="$CONFIG_DIR/repo.conf"

# Функция для проверки ошибок
check_error() {
    if [ $? -ne 0 ]; then
        echo "Ошибка: $1"
        exit 1
    fi
}

echo "=== Настройка SSH доступа для пользователя $USERNAME ==="

# Генерируем SSH ключ если не существует
PRIVATE_KEY="/home/$USERNAME/.ssh/id_ed25519"
PUBLIC_KEY="/home/$USERNAME/.ssh/id_ed25519.pub"

if [ ! -f "$PRIVATE_KEY" ]; then
    echo "Генерируем новый SSH ключ Ed25519..."
    sudo -u "$USERNAME" ssh-keygen -t ed25519 -f "$PRIVATE_KEY" -N "" -q
    check_error "Не удалось сгенерировать SSH ключ"
else
    echo "SSH ключ уже существует, пропускаем генерацию"
fi

# Создаем конфигурационный файл для repo.mycompany.ru
echo "Создаем конфигурационный файл $CONFIG_FILE..."
cat > "$CONFIG_FILE" << 'EOF'
# Конфигурация для доступа к репозиторию mycompany
Host repo.mycompany.ru
    HostName repo.mycompany.ru
    User yc-user
    Port 2222
    IdentityFile ~/.ssh/id_ed25519
    SendEnv LANG LC_*
    HashKnownHosts yes
    GSSAPIAuthentication yes
EOF

check_error "Не удалось создать конфигурационный файл"

# Устанавливаем правильные права на конфигурационный файл
chmod 644 "$CONFIG_FILE"
chown root:root "$CONFIG_FILE"

# Выводим информацию о публичном ключе
echo ""
echo "=== Настройка завершена ==="
echo "Публичный ключ для пользователя $USERNAME:"
echo "----------------------------------------"
cat "$PUBLIC_KEY"
echo "----------------------------------------"
echo ""
echo "Конфигурационный файл создан: $CONFIG_FILE"
echo "Для подключения к серверу используйте: ssh repo.mycompany.ru"
echo ""

echo "Настройка завершена успешно!"
