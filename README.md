# Деплой Gitea + PostgreSQL в Docker (rootless)

## Обзор

Этот проект предоставляет Ansible playbook и скрипты для деплоя Gitea с PostgreSQL на виртуальной машине. 
Оба сервиса запускаются в Docker контейнерах, при этом Gitea работает в rootless режиме под пользователем `dos-tech` (UID: 7777, GID: 1004).

## Структура проекта

```
/workspace/
├── deploy-gitea.yml              # Ansible playbook для деплоя
├── migrate-gitea.sh              # Скрипт миграции SQLite → PostgreSQL
├── emergency-rollback.sh         # Скрипт экстренного отката
├── README.md                     # Эта документация
├── inventory.ini.example         # Пример инвентаря Ansible
├── group_vars_all.yml.example    # Пример переменных
└── templates/
    ├── docker-compose.yml.j2     # Шаблон docker-compose (генерирует docker-compose.yml)
    ├── .env.j2                   # Переменные окружения (генерирует .env)
    └── app.ini.j2                # Конфигурация Gitea (генерирует app.ini)
```

## Как это работает

### 1. Ansible Playbook (`deploy-gitea.yml`)

Playbook выполняет следующие шаги:

1. **Установка пакетов**: docker.io, docker-compose-v2, uidmap, fuse-overlayfs
2. **Создание пользователя**: `dos-tech` с UID 7777 и GID 1004
3. **Подготовка директорий**: `/opt/gitea` и `/opt/docker-images`
4. **Загрузка Docker образов**: из tar-архивов (оффлайн режим)
5. **Настройка rootless Docker**: конфигурация subuid/subgid
6. **Генерация конфигов**: 
   - `docker-compose.yml` из шаблона `templates/docker-compose.yml.j2`
   - `.env` из шаблона `templates/.env.j2`
   - `app.ini` из шаблона `templates/app.ini.j2`
7. **Запуск контейнеров**: через `docker compose up -d`

### 2. Конфигурационные файлы (генерируются автоматически)

#### docker-compose.yml
Генерируется из `templates/docker-compose.yml.j2` с использованием переменных Ansible.
Определяет два сервиса:
- **postgres**: PostgreSQL 15 Alpine
- **gitea**: Gitea rootless образ

#### app.ini
Генерируется из `templates/app.ini.j2`. Содержит полную конфигурацию Gitea:
- Настройки сервера (порт, домен, SSH)
- Подключение к PostgreSQL
- Настройки безопасности
- Сервисные настройки (регистрация, уведомления и т.д.)

#### .env
Генерируется из `templates/.env.j2`. Содержит переменные окружения:
- Учетные данные PostgreSQL
- UID/GID пользователя
- Домен Gitea

## Требования

### На машине с интернетом (для подготовки образов):
```bash
# Сохранить образ Gitea rootless
docker pull gitea/gitea:latest-rootless
docker save gitea/gitea:latest-rootless -o gitea-rootless.tar

# Сохранить образ PostgreSQL
docker pull postgres:15-alpine
docker save postgres:15-alpine -o postgres.tar
```

### На целевой ВМ:
- Ubuntu/Debian Linux
- Доступ по SSH для Ansible
- Минимум 2GB RAM, 2 CPU, 20GB disk

## Быстрый старт

### 1. Подготовка файлов образов

Поместите файлы образов в директорию проекта:
```
gitea-rootless.tar
postgres.tar
```

### 2. Настройка инвентаря

Скопируйте пример инвентаря и отредактируйте его:
```bash
cp inventory.ini.example inventory.ini
```

Пример содержимого `inventory.ini`:
```ini
[gitea_servers]
gitea-server ansible_host=192.168.1.100 ansible_user=ubuntu
```

### 3. Настройка переменных

Создайте файл переменных:
```bash
mkdir -p group_vars
cp group_vars_all.yml.example group_vars/all.yml
```

Отредактируйте `group_vars/all.yml`:
```yaml
---
# Пароль PostgreSQL
postgres_password: "YourSecurePassword123!"

# Домен Gitea
gitea_domain: "gitea.yourdomain.com"

# Секретные ключи (сгенерируйте уникальные)
secret_key: "$(openssl rand -hex 32)"
internal_token: "$(openssl rand -hex 64)"

# Порты (опционально)
http_port: "3000"
ssh_port: "2222"
```

### 4. Запуск деплоя

```bash
ansible-playbook -i inventory.ini deploy-gitea.yml
```

Или с указанием конкретных тегов:
```bash
# Только установка пакетов
ansible-playbook -i inventory.ini deploy-gitea.yml --tags packages

# Только загрузка образов
ansible-playbook -i inventory.ini deploy-gitea.yml --tags images

# Полный деплой
ansible-playbook -i inventory.ini deploy-gitea.yml
```

### 5. Миграция данных (если есть старый сервис)

Если у вас уже работает Gitea с SQLite:

```bash
# Сделать миграцию
sudo ./migrate-gitea.sh migrate

# Или откатиться назад
sudo ./migrate-gitea.sh rollback
```

### 6. Экстренный откат

В случае проблем с новым сервисом:
```bash
sudo ./emergency-rollback.sh
```

## Проверка работы

После деплоя проверьте:

1. **Контейнеры запущены**:
```bash
sudo -u dos-tech docker ps
```

2. **Gitea отвечает**:
```bash
curl http://localhost:3000
```

3. **Логи Gitea**:
```bash
sudo -u dos-tech docker logs gitea-server
```

4. **Логи PostgreSQL**:
```bash
sudo -u dos-tech docker logs gitea-postgres
```

## Архитектура

### Пользователи и права

- **Хост пользователь**: `dos-tech` (UID: 7777, GID: 1004)
- **Владелец томов**: `dos-tech`
- **Rootless Docker**: запускается от имени `dos-tech`

### Сетевая конфигурация

- **HTTP порт**: 3000 (настраиваемый)
- **SSH порт**: 2222 (настраиваемый)
- **Docker сеть**: gitea-net (bridge)

### Тома (Volumes)

```
/opt/gitea/
├── docker-compose.yml    # Конфиг Docker Compose
├── .env                  # Переменные окружения
├── gitea/                # Данные Gitea
│   ├── git/repositories  # Git репозитории
│   ├── gitea/conf/       # Конфигурация (app.ini)
│   └── ...               # Другие данные
└── postgres/             # Данные PostgreSQL
```

## Миграция с SQLite на PostgreSQL

Скрипт `migrate-gitea.sh` выполняет миграцию с минимальным простоем:

1. Создает резервную копию старого сервиса
2. Останавливает старый сервис (короткий простой)
3. Копирует репозитории и данные
4. Переносит базу данных
5. Запускает новый сервис
6. Проверяет работоспособность

### Переменные окружения для скрипта миграции

```bash
export OLD_SQLITE_DB_PATH=/var/lib/gitea/data/gitea.db
export OLD_APP_INI_PATH=/var/lib/gitea/conf/app.ini
export OLD_REPOS_PATH=/var/lib/gitea/data/gitea-repositories
export OLD_DATA_PATH=/var/lib/gitea/data
```

## Откат изменений

### Встроенный откат в скрипте миграции

```bash
sudo ./migrate-gitea.sh rollback
```

### Экстренный откат

Скрипт `emergency-rollback.sh`:
1. Останавливает новые Docker контейнеры
2. Запускает старый systemd сервис `dos-gitea`
3. Восстанавливает оригинальные конфиги

## Настройка Gitea

После первого входа администратора:

1. Зайдите на `http://your-server:3000`
2. Создайте первую учетную запись (она станет админом)
3. Настройте параметры в веб-интерфейсе или через `app.ini`

### Изменение app.ini

Отредактируйте шаблон `templates/app.ini.j2` и перезапустите:
```bash
ansible-playbook -i inventory.ini deploy-gitea.yml --tags config,deploy
```

## Troubleshooting

### Контейнер не запускается

Проверьте логи:
```bash
sudo -u dos-tech docker logs gitea-server
sudo -u dos-tech docker logs gitea-postgres
```

### Проблемы с правами доступа

```bash
# Проверить владельца директорий
ls -la /opt/gitea/

# Исправить права
sudo chown -R dos-tech:dos-tech /opt/gitea/
```

### Rootless Docker не работает

```bash
# Проверить конфигурацию subuid/subgid
cat /etc/subuid | grep dos-tech
cat /etc/subgid | grep dos-tech

# Перезапустить user namespace
sudo systemctl stop user@$(id -u dos-tech).service
sudo systemctl start user@$(id -u dos-tech).service
```

### Проверка здоровья PostgreSQL

```bash
sudo -u dos-tech docker exec gitea-postgres pg_isready -U gitea -d gitea
```

## Безопасность

- Измените пароль PostgreSQL по умолчанию
- Сгенерируйте уникальные `SECRET_KEY` и `INTERNAL_TOKEN`
- Настройте firewall для ограничения доступа к портам
- Рассмотрите использование HTTPS через reverse proxy

## Обновление

Для обновления версий образов:

1. Подготовьте новые tar-файлы образов
2. Замените старые файлы
3. Перезапустите сервис:
```bash
sudo -u dos-tech docker compose -f /opt/gitea/docker-compose.yml down
sudo -u dos-tech docker compose -f /opt/gitea/docker-compose.yml up -d
```

## Лицензия

MIT License
