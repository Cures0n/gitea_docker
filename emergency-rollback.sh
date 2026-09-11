#!/bin/bash
# Экстренный откат к старому сервису dos-gitea
# Используйте этот скрипт если новый Docker-сервис работает некорректно
#
# Использование: sudo ./emergency-rollback.sh

set -euo pipefail

OLD_SERVICE_NAME="dos-gitea"
NEW_COMPOSE_DIR="/opt/gitea"
GITEA_USER="dos-tech"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=============================================="
echo "  Emergency Rollback to Old Gitea Service"
echo "=============================================="
echo ""

# Проверка существования старого сервиса
if ! systemctl list-unit-files | grep -q "$OLD_SERVICE_NAME"; then
    log_error "Старый сервис $OLD_SERVICE_NAME не найден!"
    log_error "Откат невозможен - старый сервис был удалён."
    exit 1
fi

# Остановка нового Docker сервиса
log_info "Остановка нового Docker сервиса..."
if [ -d "$NEW_COMPOSE_DIR" ] && [ -f "$NEW_COMPOSE_DIR/docker-compose.yml" ]; then
    cd "$NEW_COMPOSE_DIR"
    if sudo -u "$GITEA_USER" docker-compose down 2>/dev/null; then
        log_info "Docker контейнеры остановлены"
    else
        log_warn "Не удалось остановить Docker контейнеры через docker-compose"
        # Попытка остановить напрямую
        docker stop gitea-server 2>/dev/null || true
        docker stop gitea-postgres 2>/dev/null || true
    fi
else
    log_warn "Директория $NEW_COMPOSE_DIR не найдена или docker-compose.yml отсутствует"
fi

# Запуск старого сервиса
log_info "Запуск старого сервиса $OLD_SERVICE_NAME..."
if systemctl start "$OLD_SERVICE_NAME"; then
    log_info "Старый сервис успешно запущен"
else
    log_error "Не удалось запустить старый сервис!"
    log_error "Проверьте логи: journalctl -u $OLD_SERVICE_NAME"
    exit 1
fi

# Проверка статуса
sleep 3
if systemctl is-active --quiet "$OLD_SERVICE_NAME"; then
    echo ""
    log_info "=============================================="
    log_info "  Откат успешно выполнен!"
    log_info "=============================================="
    log_info ""
    log_info "Старый сервис $OLD_SERVICE_NAME активен"
    log_info ""
    log_info "Следующие шаги:"
    log_info "1. Проверьте доступность Gitea"
    log_info "2. Изучите логи нового сервиса:"
    log_info "   cd $NEW_COMPOSE_DIR"
    log_info "   sudo -u $GITEA_USER docker-compose logs"
    log_info ""
    log_info "Для повторной попытки миграции исправьте проблемы"
    log_info "и запустите migrate-gitea.sh снова"
else
    log_error "Сервис не активен после запуска!"
    exit 1
fi
