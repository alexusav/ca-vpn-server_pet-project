#!/bin/bash

# Скрипт восстановления конфигурационных файлов и сертификатов из бэкапа
set -e

# Конфигурационные переменные
BACKUP_SERVER="repo.mycompany.ru"
BACKUP_USER="yc-user"
BACKUP_DIR="/var/backups/$(hostname)"
RESTORE_DIR="/tmp/restore_$(date +%Y%m%d_%H%M%S)"
DECRYPTION_PASSWORD="123456789" # Можно установить через переменную окружения

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
    deps=("tar" "gpg" "ssh" "scp")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Не найдена зависимость: $dep"
            exit 1
        fi
    done
    log_info "Все зависимости проверены"
}

# Функция вывода списка доступных бэкапов
list_backups() {
    log_info "Доступные бэкапы на сервере:"
    
    if ! ssh "$BACKUP_USER@$BACKUP_SERVER" "ls -la '$BACKUP_DIR'/backup_*.tar.gz.gpg 2>/dev/null" | head -10; then
        log_error "Не удалось получить список бэкапов или бэкапы не найдены"
        exit 1
    fi
    
    echo ""
    log_info "Полный список бэкапов:"
    ssh "$BACKUP_USER@$BACKUP_SERVER" "find '$BACKUP_DIR' -name 'backup_*.tar.gz.gpg' -type f -printf '%f\n' | sort"
}

# Функция загрузки бэкапа с сервера
download_backup() {
    local backup_file="$1"
    local local_path="/tmp/$backup_file"
    
    log_info "Загружаем бэкап: $backup_file"
    
    if ! scp "$BACKUP_USER@$BACKUP_SERVER:$BACKUP_DIR/$backup_file" "$local_path"; then
        log_error "Ошибка при загрузке бэкапа"
        exit 1
    fi
    
    log_info "Бэкап загружен: $local_path"
    echo "$local_path"
}

# Функция расшифровки бэкапа
decrypt_backup() {
    local encrypted_file="$1"
    local decrypted_file="${encrypted_file%.gpg}"
    
    if [ -z "$DECRYPTION_PASSWORD" ]; then
        log_warn "Пароль расшифровки не установлен, запрашиваем у пользователя"
        read -sp "Введите пароль для расшифровки бэкапа: " DECRYPTION_PASSWORD
        echo
        if [ -z "$DECRYPTION_PASSWORD" ]; then
            log_error "Пароль не может быть пустым"
            return 1
        fi
    fi

    log_info "Начинаем расшифровку бэкапа..."

    if ! gpg --batch --yes --passphrase "$DECRYPTION_PASSWORD" \
             -o "$decrypted_file" --decrypt "$encrypted_file"; then
        log_error "Ошибка при расшифровке архива. Проверьте пароль."
        return 1
    fi

    log_info "Бэкап расшифрован: $decrypted_file"
    echo "$decrypted_file"
}

# Функция распаковки бэкапа
extract_backup() {
    local backup_archive="$1"
    
    log_info "Распаковываем бэкап в: $RESTORE_DIR"
    
    mkdir -p "$RESTORE_DIR"
    
    if ! tar -xzf "$backup_archive" -C "$RESTORE_DIR"; then
        log_error "Ошибка при распаковке архива"
        return 1
    fi
    
    log_info "Бэкап распакован в: $RESTORE_DIR"
}

# Функция проверки содержимого бэкапа
inspect_backup() {
    log_info "Содержимое бэкапа:"
    find "$RESTORE_DIR" -type f -printf "%p\t%s bytes\n" | while read -r line; do
        log_info "  $line"
    done
    
    echo ""
    log_info "Структура директорий:"
    tree "$RESTORE_DIR" 2>/dev/null || find "$RESTORE_DIR" -type d | sed -e "s/[^-][^\/]*\//  |/g" -e "s/|\([^ ]\)/|-\1/"
}

# Функция восстановления конфигурационных файлов
restore_configs() {
    local config_dir="$RESTORE_DIR/configs"
    
    if [ ! -d "$config_dir" ]; then
        log_warn "Директория конфигов не найдена в бэкапе"
        return 0
    fi
    
    log_info "Начинаем восстановление конфигурационных файлов"
    
    # Восстановление из tar архивов
    for tar_file in "$config_dir"/*.tar.gz; do
        if [ -f "$tar_file" ]; then
            local base_name=$(basename "$tar_file" .tar.gz)
            log_info "Восстанавливаем: $base_name"
            
            # Создаем бекап существующих файлов
            if [ -d "/etc/$base_name" ]; then
                local backup_name="/tmp/${base_name}_backup_$(date +%Y%m%d_%H%M%S)"
                cp -r "/etc/$base_name" "$backup_name" 2>/dev/null || true
                log_info "Создана резервная копия существующей конфигурации: $backup_name"
            fi
            
            # Распаковываем новые файлы
            tar -xzf "$tar_file" -C "/etc/" || log_warn "Ошибка при распаковке $tar_file"
        fi
    done
    
    # Восстановление отдельных файлов
    for config_file in "$config_dir"/*; do
        if [ -f "$config_file" ] && [[ "$config_file" != *.tar.gz ]]; then
            local file_name=$(basename "$config_file")
            log_info "Восстанавливаем файл: /etc/$file_name"
            
            # Создаем бекап существующего файла
            if [ -f "/etc/$file_name" ]; then
                cp "/etc/$file_name" "/etc/${file_name}.backup_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            fi
            
            cp "$config_file" "/etc/$file_name" 2>/dev/null || log_warn "Не удалось восстановить /etc/$file_name"
        fi
    done
}

# Функция восстановления сертификатов
restore_certificates() {
    local cert_dir="$RESTORE_DIR/certificates"
    
    if [ ! -d "$cert_dir" ]; then
        log_warn "Директория сертификатов не найдена в бэкапе"
        return 0
    fi
    
    log_info "Начинаем восстановление сертификатов"
    
    # Восстановление easy-rsa
    if [ -f "$cert_dir/easy-rsa.tar.gz" ]; then
        log_info "Восстанавливаем easy-rsa сертификаты"
        
        # Создаем бекап существующих сертификатов
        if [ -d "/var/easy-rsa" ]; then
            local backup_name="/var/easy-rsa_backup_$(date +%Y%m%d_%H%M%S)"
            cp -r "/var/easy-rsa" "$backup_name" 2>/dev/null || true
            log_info "Создана резервная копия существующих сертификатов: $backup_name"
        fi
        
        tar -xzf "$cert_dir/easy-rsa.tar.gz" -C "/var/" || log_warn "Ошибка при распаковке easy-rsa"
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

# Функция интерактивного выбора бэкапа
select_backup() {
    log_info "Получаем список бэкапов..."
    
    local backups=($(ssh "$BACKUP_USER@$BACKUP_SERVER" "find '$BACKUP_DIR' -name 'backup_*.tar.gz.gpg' -type f -printf '%f\n' | sort -r"))
    
    if [ ${#backups[@]} -eq 0 ]; then
        log_error "Бэкапы не найдены на сервере"
        exit 1
    fi
    
    echo ""
    log_info "Доступные бэкапы:"
    for i in "${!backups[@]}"; do
        echo "  $((i+1)). ${backups[$i]}"
    done
    
    echo ""
    read -p "Выберите номер бэкапа для восстановления (1-${#backups[@]}): " selection
    
    if [[ ! "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#backups[@]} ]; then
        log_error "Неверный выбор"
        exit 1
    fi
    
    local selected_backup="${backups[$((selection-1))]}"
    log_info "Выбран бэкап: $selected_backup"
    echo "$selected_backup"
}

# Функция подтверждения действий
confirm_restore() {
    echo ""
    log_warn "ВНИМАНИЕ: Это перезапишет существующие конфигурационные файлы!"
    log_warn "Рекомендуется создать резервные копии перед продолжением."
    echo ""
    
    read -p "Вы уверены, что хотите продолжить восстановление? (y/N): " confirmation
    
    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        log_info "Восстановление отменено"
        exit 0
    fi
}

# Функция очистки временных файлов
cleanup() {
    log_info "Очищаем временные файлы"
    rm -f "/tmp/backup_*.tar.gz" 2>/dev/null || true
    rm -f "/tmp/backup_*.tar.gz.gpg" 2>/dev/null || true
    rm -rf "$RESTORE_DIR" 2>/dev/null || true
}

# Основная функция восстановления
restore_backup() {
    local backup_file="$1"
    
    log_info "Запуск процесса восстановления из бэкапа: $backup_file"
    
    # Проверки
    check_dependencies
    check_server_connection
    
    # Загрузка бэкапа
    local encrypted_file=$(download_backup "$backup_file")
    
    # Расшифровка
    local decrypted_file=$(decrypt_backup "$encrypted_file")
    
    # Распаковка
    extract_backup "$decrypted_file"
    
    # Проверка содержимого
    inspect_backup
    
    # Подтверждение
    confirm_restore
    
    # Восстановление
    restore_configs
    restore_certificates
    
    # Очистка
    cleanup
    
    log_info "Процесс восстановления завершен успешно!"
    log_info "Рекомендуется перезагрузить сервисы для применения новых конфигураций"
}

# Функция восстановления конкретного файла
restore_single_file() {
    local backup_file="$1"
    local target_file="$2"
    
    log_info "Восстановление отдельного файла: $target_file"
    
    # Загрузка и подготовка бэкапа
    check_dependencies
    check_server_connection
    
    local encrypted_file=$(download_backup "$backup_file")
    local decrypted_file=$(decrypt_backup "$encrypted_file")
    extract_backup "$decrypted_file"
    
    # Поиск и восстановление файла
    local restored_file=$(find "$RESTORE_DIR" -name "$(basename "$target_file")" -type f | head -1)
    
    if [ -n "$restored_file" ]; then
        log_info "Найден файл в бэкапе: $restored_file"
        
        # Создаем бекап существующего файла
        if [ -f "$target_file" ]; then
            cp "$target_file" "${target_file}.backup_$(date +%Y%m%d_%H%M%S)"
        fi
        
        # Восстанавливаем файл
        cp "$restored_file" "$target_file"
        log_info "Файл восстановлен: $target_file"
    else
        log_error "Файл $target_file не найден в бэкапе"
    fi
    
    cleanup
}

# Основная функция
main() {
    case "${1:-}" in
        "--list"|"-l")
            list_backups
            ;;
        "--inspect")
            if [ -z "$2" ]; then
                log_error "Укажите имя файла бэкапа для проверки"
                exit 1
            fi
            check_dependencies
            check_server_connection
            encrypted_file=$(download_backup "$2")
            decrypted_file=$(decrypt_backup "$encrypted_file")
            extract_backup "$decrypted_file")
            inspect_backup
            cleanup
            ;;
        "--file")
            if [ -z "$2" ] || [ -z "$3" ]; then
                log_error "Использование: $0 --file <бэкап> <путь_к_файлу>"
                exit 1
            fi
            restore_single_file "$2" "$3"
            ;;
        "--help"|"-h")
            cat << EOF
Использование: $0 [ОПЦИИ]

Опции:
  -l, --list              Показать список доступных бэкапов
  --inspect <файл>        Проверить содержимое бэкапа без восстановления
  --file <бэкап> <файл>   Восстановить отдельный файл из бэкапа
  --help, -h              Показать эту справку

Если опции не указаны, запускается интерактивное восстановление.

Примеры:
  $0 --list
  $0 --inspect backup_20231201_120000.tar.gz.gpg
  $0 --file backup_20231201_120000.tar.gz.gpg /etc/ssh/sshd_config
  $0
EOF
            ;;
        *)
            backup_file=$(select_backup)
            restore_backup "$backup_file"
            ;;
    esac
}

# Обработка сигналов
trap 'log_error "Скрипт прерван"; cleanup; exit 1' INT TERM

# Запуск скрипта
main "$@"
