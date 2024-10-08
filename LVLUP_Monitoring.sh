#!/bin/bash
# Функция для вывода текста оранжевым цветом
show() {
    echo -e "\033[33m$1\033[0m"
}

# Display ASCII Art "LEVEL UP"
show ".-----------------------------------------------."
show "| _     _______     _______ _       _   _ ____  |"
show "|| |   | ____\ \   / / ____| |     | | | |  _ \ |"
show "|| |   |  _|  \ \ / /|  _| | |     | | | | |_) ||"
show "|| |___| |___  \ V / | |___| |___  | |_| |  __/ |"
show "||_____|_____|  \_/  |_____|_____|  \___/|_|    |"
show "| _   _  ___  ____  _____ ____                  |"
show "|| \ | |/ _ \|  _ \| ____/ ___|                 |"
show "||  \| | | | | | | |  _| \___ \                 |"
show "|| |\  | |_| | |_| | |___ ___) |                |"
show "||_| \_|\___/|____/|_____|____/                 |"
show "'-----------------------------------------------'"

# Директория для конфигурации
CONFIG_DIR="/etc/node_exporter_configs"
MAIN_CONFIG_FILE="$CONFIG_DIR/main.conf"
NAMES_CONFIG_FILE="$CONFIG_DIR/names.conf"
SCRIPT_PATH="/usr/local/bin/pushmetrics.sh"

# Создание папки для конфигурации, если она не существует
sudo mkdir -p "$CONFIG_DIR"

# Создание основного конфигурационного файла, если он не существует
if [[ ! -f $MAIN_CONFIG_FILE ]]; then
    echo "Создание основного конфигурационного файла $MAIN_CONFIG_FILE..."
    echo 'PUSHGATEWAY_URL="http://84.247.173.180:9091"' | sudo tee "$MAIN_CONFIG_FILE" > /dev/null
    echo 'METRICS_INTERVAL=15' | sudo tee -a "$MAIN_CONFIG_FILE" > /dev/null
    echo 'NODE_EXPORTER_PORT=9100' | sudo tee -a "$MAIN_CONFIG_FILE" > /dev/null
else
    echo "Основной конфигурационный файл уже существует: $MAIN_CONFIG_FILE"
fi

# Запрос данных у пользователя с проверкой
while true; do
    read -p "Введите ник: " user_nick
    if [[ -z "$user_nick" || "$user_nick" =~ [^a-zA-Z0-9_] ]]; then
        echo "Ник должен содержать только буквы, цифры и символ '_'. Попробуйте еще раз."
    else
        break
    fi
done

while true; do
    read -p "Введите имя ноды: " node_name
    if [[ -z "$node_name" || "$node_name" =~ [^a-zA-Z0-9_] ]]; then
        echo "Имя ноды должно содержать только буквы, цифры и символ '_'. Попробуйте еще раз."
    else
        break
    fi
done

# Получение адреса сервера
server_address=$(hostname -I | awk '{print $1}')

# Создание файла конфигурации с именем ноды и ником
echo "Создание конфигурационного файла $NAMES_CONFIG_FILE..."
echo "user_nick=\"$user_nick\"" | sudo tee "$NAMES_CONFIG_FILE" > /dev/null
echo "node_name=\"$node_name\"" | sudo tee -a "$NAMES_CONFIG_FILE" > /dev/null

# Удаление предыдущей установки Node Exporter
echo "Удаление предыдущей установки Node Exporter, если она есть..."
sudo systemctl stop node_exporter 2>/dev/null
sudo systemctl disable node_exporter 2>/dev/null
sudo rm -f /etc/systemd/system/node_exporter.service
sudo rm -f /usr/local/bin/node_exporter
sudo userdel node_exporter 2>/dev/null
sudo systemctl daemon-reload

# Удаление предыдущего сервиса push_metrics, если он существует
echo "Удаление предыдущего сервиса push_metrics, если он есть..."
sudo systemctl stop push_metrics 2>/dev/null
sudo systemctl disable push_metrics 2>/dev/null
sudo rm -f /etc/systemd/system/push_metrics.service

# Создание пользователя для Node Exporter
sudo useradd -rs /bin/false node_exporter

# Установка Node Exporter
curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar xvfz node_exporter-1.8.2.linux-amd64.tar.gz
sudo mv node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/

# Создание systemd unit файла для Node Exporter
cat <<EOL | sudo tee /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter --web.listen-address=":9100"
Restart=always

[Install]
WantedBy=default.target
EOL

# Перезагрузка systemd и запуск Node Exporter
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

# Создание скрипта для отправки метрик в Pushgateway
cat << EOF | sudo tee "$SCRIPT_PATH" > /dev/null
#!/bin/bash

# Чтение основного конфигурационного файла
MAIN_CONFIG_FILE="/etc/node_exporter_configs/main.conf"
if [[ -f \$MAIN_CONFIG_FILE ]]; then
    source "\$MAIN_CONFIG_FILE"
else
    echo "Основной конфигурационный файл не найден: \$MAIN_CONFIG_FILE"
    exit 1
fi

# Чтение файла с именем ноды и ником
NAMES_CONFIG_FILE="/etc/node_exporter_configs/names.conf"
if [[ -f \$NAMES_CONFIG_FILE ]]; then
    source "\$NAMES_CONFIG_FILE"
else
    echo "Конфигурационный файл не найден: \$NAMES_CONFIG_FILE"
    exit 1
fi

server_address=\$(hostname -I | awk '{print \$1}')

# Бесконечный цикл отправки метрик
while true; do
    # Получение метрик из Node Exporter
    metrics=\$(curl -s http://localhost:\$NODE_EXPORTER_PORT/metrics)

    # Отправка метрик в Pushgateway
    echo "\$metrics" | curl --data-binary @- "\$PUSHGATEWAY_URL/metrics/job/\$server_address"

    # Отправка метрики node_metrics с нужными метками
    echo "node_metrics{instance=\"\", job=\"\$server_address\", node_name=\"\$node_name\", user_nick=\"\$user_nick\"} 1" | curl --data-binary @- "\$PUSHGATEWAY_URL/metrics/job/\$server_address"
    
    sleep \$METRICS_INTERVAL
done
EOF

# Сделать скрипт исполняемым
sudo chmod +x "$SCRIPT_PATH"

# Создание пользователя для Push Metrics
sudo useradd -rs /bin/false push_metrics

# Создание systemd unit файла для отправки метрик
SERVICE_FILE="/etc/systemd/system/push_metrics.service"
cat << EOF | sudo tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=Push Node Exporter Metrics to Pushgateway
After=network.target

[Service]
ExecStart=$SCRIPT_PATH
Restart=always
User=push_metrics

[Install]
WantedBy=multi-user.target
EOF

# Перезагрузка systemd и запуск сервиса
sudo systemctl daemon-reload
sudo systemctl enable push_metrics.service
sudo systemctl start push_metrics.service

show "Установка завершена! Node Exporter и сервис отправки метрик запущены."
