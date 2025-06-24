#!/bin/bash

echo "=== Actualizando servicio Orange Clock ==="

# Instalar tkinter para GUI
echo "Instalando python3-tk..."
sudo apt-get update
sudo apt-get install -y python3-tk mpg123 alsa-utils

# Verificar y crear entorno virtual si no existe
echo "Verificando entorno virtual..."
if [ ! -d "/home/orangepi/clock_api_env" ]; then
    echo "Creando entorno virtual..."
    python3 -m venv /home/orangepi/clock_api_env
else
    echo "Entorno virtual ya existe"
fi

# Activar entorno virtual e instalar dependencias
echo "Activando entorno virtual e instalando paquetes..."
source /home/orangepi/clock_api_env/bin/activate
pip install flask flask-cors apscheduler pygame waitress

# Actualizar archivo de servicio
echo "Actualizando archivo de servicio..."
sudo tee /etc/systemd/system/clock_api.service > /dev/null <<EOF
[Unit]
Description=Orange Clock Alarm System
After=network.target sound.target
Wants=network.target

[Service]
Type=simple
User=orangepi
Group=orangepi
WorkingDirectory=/home/orangepi/clock_api
ExecStart=/home/orangepi/clock_api_env/bin/python3 /home/orangepi/clock_api/schedule-controller.py
Restart=always
RestartSec=3s
Environment="PATH=/home/orangepi/clock_api_env/bin:/usr/bin"
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/orangepi/.Xauthority
Environment=PULSE_RUNTIME_PATH=/run/user/1000/pulse
Environment=XDG_RUNTIME_DIR=/run/user/1000
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Habilitar y reiniciar servicio
echo "Configurando servicio..."
sudo systemctl daemon-reload
sudo systemctl enable clock_api.service
sudo systemctl restart clock_api.service

echo "Estado del servicio:"
sudo systemctl status clock_api.service --no-pager

echo ""
echo "=== Actualización completada ==="
echo "Los mensajes flotantes ahora aparecerán cuando se ejecuten las alarmas"