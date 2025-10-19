#!/bin/bash

# Скрипт бэкапа конфигурационных файлов и сертификатов
set -e

# Конфигурационные переменные
BACKUP_SERVER="repo.mycompany.ru"
BACKUP_USER="yc-user"
BACKUP_DIR="/var/backups/$(hostname)"
LOCAL_BACKUP_DIR="/tmp/backup_$(date +%Y%m%d_%H%M%S)"
ENCRYPTION_PASSWORD="123456789" # Можно установить через переменную окружения
RETENTION_DAYS=7
BACKUP_FILE=""

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функции для логирования
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Функция проверки зависимостей
check_dependencies() {
    deps=("tar" "gpg" "find")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Не найдена зависимость: $dep"
            exit 1
        fi
    done
    log_info "Все зависимости проверены"
}

# Функция создания временной директории
create_backup_dir() {
    mkdir -p "$LOCAL_BACKUP_DIR"
    log_info "Создана временная директория: $LOCAL_BACKUP_DIR"
}

# Функция бэкапа конфигурационных файлов
backup_configs() {
    config_dir="$LOCAL_BACKUP_DIR/configs"
    mkdir -p "$config_dir"

    log_info "Начинаем бэкап конфигурационных файлов"

    # Список конфигурационных директорий для бэкапа
    config_paths=(
        "/etc/ssh"
        "/etc/systemd"
        "/etc/cron.d"
        "/etc/iptables"
	"/etc/default/prometheus-node-exporter"
	"/etc/nginx"
	"/etc/prometheus"
	"/usr/share/prometheus"
	"/lib/systemd/system"
	"/etc/default"
    )

    for path in "${config_paths[@]}"; do
        if [ -e "$path" ]; then
            local base_name=$(basename "$path")
            tar -czf "$config_dir/${base_name}.tar.gz" -C "/etc" "$base_name" 2>/dev/null || true
            log_info "Создан бэкап: $path"
        fi
    done

    # Бэкап отдельных важных файлов
    important_files=(
        "/etc/passwd"
        "/etc/group"
        "/etc/shadow"
        "/etc/sudoers"
        "/etc/hosts"
        "/etc/resolv.conf"
        "/etc/fstab"
        "/etc/hostname"
    )

    for file in "${important_files[@]}"; do
        if [ -f "$file" ]; then
            cp "$file" "$config_dir/" 2>/dev/null || true
        fi
    done
}

# Функция шифрования бэкапа
encrypt_backup() {
    local backup_archive="/tmp/backup_$(date +%Y%m%d_%H%M%S).tar.gz.gpg"
    local temp_tar="/tmp/backup_temp_$(date +%s).tar.gz"

    if [ -z "$ENCRYPTION_PASSWORD" ]; then
        log_warn "Пароль шифрования не установлен, запрашиваем у пользователя"
        read -sp "Введите пароль для шифрования бэкапа: " ENCRYPTION_PASSWORD
        echo
        if [ -z "$ENCRYPTION_PASSWORD" ]; then
            log_error "Пароль не может быть пустым"
            return 1
        fi
    fi

    log_info "Начинаем шифрование бэкапа..."

    # Сначала создаем tar архив
    if ! tar -czf "$temp_tar" -C "$LOCAL_BACKUP_DIR" .; then
        log_error "Ошибка при создании tar архива"
        return 1
    fi

    # Затем шифруем его
    if ! gpg --batch --yes --passphrase "$ENCRYPTION_PASSWORD" \
             --symmetric --cipher-algo AES256 \
             -o "$backup_archive" "$temp_tar"; then
        log_error "Ошибка при шифровании архива"
        rm -f "$temp_tar"
        return 1
    fi

    # Очищаем временный файл
    rm -f "$temp_tar"

    log_info "Бэкап зашифрован: $backup_archive"
    BACKUP_FILE="$backup_archive"
}

# Функция передачи на сервер
transfer_to_server() {
    if [ ! -z $BACKUP_FILE ]; then
	    remote_path="$BACKUP_DIR/$(basename "$BACKUP_FILE")"
    else
	    log_error "Ошибка. Отсутствует файл для передачи на сервер"
	    exit 1
    fi

    log_info "Начинаем передачу бэкапа на сервер $BACKUP_SERVER"

    # Создаем директорию на сервере если не существует
    ssh "$BACKUP_USER@$BACKUP_SERVER" "mkdir -p '$BACKUP_DIR'"

    # Передаем файл
    echo "Передаем файл"
    if scp "$BACKUP_FILE" "$BACKUP_USER@$BACKUP_SERVER:$remote_path"; then
        log_info "Бэкап успешно передан: $remote_path"
        echo "$remote_path"
    else
        log_error "Ошибка при передаче бэкапа на сервер"
        exit 1
    fi
}

# Функция очистки старых бэкапов
cleanup_old_backups() {
    log_info "Очищаем старые бэкапы (старше $RETENTION_DAYS дней)"

    # Локальная очистка
    find /tmp -name "backup_*.tar.gz.gpg" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
    rm -rf /tmp/backup_* 2>/dev/null || true

    # Удаляем старые бэкапы на сервере
    ssh "$BACKUP_USER@$BACKUP_SERVER" \
        "find '$BACKUP_DIR' -name 'backup_*.tar.gz.gpg' -mtime +$RETENTION_DAYS -delete" 2>/dev/null || true

    log_info "Очистка старых бэкапов завершена"
}

# Функция проверки свободного места
check_disk_space() {
    required_space=$(du -s "$LOCAL_BACKUP_DIR" 2>/dev/null | cut -f1 ||echo 0)
    available_space=$(df /tmp | awk 'NR==2 {print $4}')

    if [ "$required_space" -gt "$available_space" ]; then
        log_error "Недостаточно свободного места для создания бэкапа"
        exit 1
    fi
}

# Функция проверки подключения к серверу
check_server_connection() {
    if ! ssh -o ConnectTimeout=10 "$BACKUP_USER@$BACKUP_SERVER" "echo 'Connection successful'" &> /dev/null; then
        log_error "Не удалось подключиться к серверу $BACKUP_SERVER"
        exit 1
    fi
    log_info "Подключение к серверу проверено"
}

# Основная функция
main() {
    log_info "Запуск процесса бэкапа"

    # Проверки
    check_dependencies
    check_server_connection

    # Создание бэкапа
    create_backup_dir
    backup_configs

    # Проверка места
    check_disk_space

    # Шифрование и передача
    encrypt_backup
    transfer_to_server

    # Очистка
    rm -f "$encrypted_file"
    rm -rf "$LOCAL_BACKUP_DIR"
    cleanup_old_backups

    log_info "Процесс бэкапа завершен успешно!"
    log_info "Файл бэкапа: $remote_path"
    log_info "Размер: $(du -h "$encrypted_file" 2>/dev/null | cut -f1 || echo "N/A")"
}

# Обработка сигналов
trap 'log_error "Скрипт прерван"; cleanup; exit 1' INT TERM

# Запуск скрипта
if [ "$1" = "--config" ]; then
    cat << EOF
Конфигурация бэкапа:
- Сервер: $BACKUP_SERVER
- Пользователь: $BACKUP_USER
- Директория на сервере: $BACKUP_DIR
- Хранение бэкапов: $RETENTION_DAYS дней
- Шифрование: AES256
EOF
else
    main
fi
