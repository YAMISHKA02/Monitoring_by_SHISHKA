#!/bin/bash

# Функция для вывода текста оранжевым цветом
show() {
    echo -e "\033[33m$1\033[0m"
}

# Остановка и отключение сервиса Node Exporter
show "Остановка и отключение сервиса Node Exporter..."
sudo systemctl stop node_exporter
sudo systemctl disable node_exporter

# Удаление системного юнита Node Exporter
show "Удаление системного юнита Node Exporter..."
sudo rm -f /etc/systemd/system/node_exporter.service

# Удаление файлов Node Exporter
show "Удаление файлов Node Exporter..."
sudo rm -f /usr/local/bin/node_exporter

# Удаление пользователя Node Exporter
show "Удаление пользователя Node Exporter..."
sudo userdel node_exporter 2>/dev/null

# Удаление сервиса отправки метрик
show "Остановка и отключение сервиса push_metrics..."
sudo systemctl stop push_metrics
sudo systemctl disable push_metrics

# Удаление системного юнита для сервиса отправки метрик
show "Удаление системного юнита для сервиса push_metrics..."
sudo rm -f /etc/systemd/system/push_metrics.service

# Удаление скрипта для отправки метрик
show "Удаление скрипта для отправки метрик..."
sudo rm -f /usr/local/bin/pushmetrics.sh

# Удаление конфигурационных файлов
CONFIG_DIR="/etc/node_exporter_configs"
show "Удаление конфигурационных файлов..."
sudo rm -rf "$CONFIG_DIR"

# Перезагрузка systemd
show "Перезагрузка systemd..."
sudo systemctl daemon-reload

show "Удаление завершено! Все файлы и зависимости успешно удалены."
