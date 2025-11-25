#!/bin/bash

# Настройки
LOG_DIR="/home/hacoc/IdeaProjects/configs/auto-update/logs"
TEMP_DIR="/home/hacoc/IdeaProjects/configs/auto-update/tmp"
mkdir -p "$LOG_DIR" "$TEMP_DIR"

# Используем английские названия месяцев
export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
export LC_ALL=en_US.UTF-8

# Имя файла: update-november-2025.log
CURRENT_MONTH=$(date +"%B-%Y" | tr '[:upper:]' '[:lower:]')
LOG_FILE="$LOG_DIR/update-$CURRENT_MONTH.log"

# Временные файлы (в пользовательской директории, без проблем с правами)
TEMP_UPDATE_LOG="$TEMP_DIR/apt-update.log"
TEMP_UPGRADE_LOG="$TEMP_DIR/apt-upgrade.log"
PACKAGES_LOG="$TEMP_DIR/updated-packages.log"

# Очистка старых временных файлов (опционально)
> "$TEMP_UPDATE_LOG"
> "$TEMP_UPGRADE_LOG"
> "$PACKAGES_LOG"

# Перенаправляем весь вывод в текущий лог-файл
exec >> "$LOG_FILE" 2>&1

echo "$(date): 🔄 Запуск автоматического обновления системы..."

# === Ротация логов: удаляем файлы старше 3 месяцев ===
cd "$LOG_DIR" || exit 1
for logfile in update-*.log; do
    if [[ -f "$logfile" && "$logfile" != "update-$CURRENT_MONTH.log" ]]; then
        # Извлекаем месяц и год: например, november-2025
        file_month=$(echo "$logfile" | sed -E 's/update-([a-z]+)-([0-9]{4})\.log/\1 \2/')
        file_date=$(date -d "$file_month" 2>/dev/null +%s)
        current_date=$(date +%s)
        # Если файл старше 3 месяцев — удаляем
        if [[ -n "$file_date" ]] && [[ $(( (current_date - file_date) / 86400 )) -gt 90 ]]; then
            rm -f "$logfile"
            echo "$(date): 🗑️ Удалён старый лог-файл: $logfile"
        fi
    fi
done

# === Шаг 1: Обновляем список пакетов ===
echo "$(date): 1/3: Выполняем apt update..."
apt update -y > "$TEMP_UPDATE_LOG" 2>&1

if [ $? -ne 0 ]; then
    echo "$(date): ❌ Ошибка при выполнении 'apt update'"
    tail -n 20 "$TEMP_UPDATE_LOG"
    exit 1
fi

# === Шаг 2: Проверяем, какие пакеты можно обновить ===
echo "$(date): Проверка доступных обновлений..."
UPGRADEABLE_LIST=$(apt list --upgradable 2>/dev/null | tail -n +2 | grep -E '^.+/.+ .+ .+')

if [ -z "$UPGRADEABLE_LIST" ]; then
    echo "$(date): ✅ Нет доступных обновлений. Система актуальна."
    exit 0
else
    UPGRADEABLE_COUNT=$(echo "$UPGRADEABLE_LIST" | wc -l)
    echo "$(date): ⚠ Найдено $UPGRADEABLE_COUNT пакетов для обновления:"
    echo "$UPGRADEABLE_LIST" | sed 's/^/   /'
fi

# === Шаг 3: Устанавливаем обновления ===
echo "$(date): 2/3: Устанавливаем обновления..."
apt upgrade -y > "$TEMP_UPGRADE_LOG" 2>&1

if [ $? -ne 0 ]; then
    echo "$(date): ❌ Ошибка при выполнении 'apt upgrade'"
    tail -n 20 "$TEMP_UPGRADE_LOG"
    exit 1
fi

# === Извлекаем обновлённые пакеты ===
UPDATED_PACKAGES=$(grep "Setting up" "$TEMP_UPGRADE_LOG" | awk '{print $3}' | sed 's/:.*$//')
UPDATED_COUNT=$(echo "$UPDATED_PACKAGES" | grep -v '^$' | wc -l)

if [ $UPDATED_COUNT -gt 0 ]; then
    echo "$(date): ✅ Успешно обновлено $UPDATED_COUNT пакетов:"
    echo "$UPDATED_PACKAGES" | sed 's/^/   /'
else
    echo "$(date): ✅ Обновлений не было — перезагрузка не требуется."
    exit 0
fi

# === Диагностика: Проверка оставшихся обновляемых пакетов (например, фазовые) ===
echo "$(date): Диагностика: Проверка состояния обновлений после upgrade..."
UPGRADABLE_AFTER=$(apt list --upgradable 2>/dev/null | tail -n +2 | grep -E '^.+/.+ .+ .+')
if [ -n "$UPGRADABLE_AFTER" ]; then
    echo "$(date): ⚠ Эти пакеты всё ещё отложены (возможно, фазовые):"
    echo "$UPGRADABLE_AFTER" | sed 's/^/   /'
    echo "$(date): 💡 Совет: используйте APT::Get::Always-Include-Phased-Updates=true, чтобы установить их."
else
    echo "$(date): ✅ Все обновления установлены. Нет отложенных пакетов."
fi

# === Шаг 4: Перезагрузка ===
if [ -f /var/run/reboot-required ]; then
    echo "$(date): 3/3: Требуется перезагрузка — перезагружаем систему..."
    shutdown -r +1 "Система перезагружается (требуется по /var/run/reboot-required)"
    echo "$(date): 🎉 Система будет перезагружена через 1 минуту!"
else
    echo "$(date): ✅ Перезагрузка не требуется."
fi