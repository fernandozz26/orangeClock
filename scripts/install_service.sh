#!/bin/bash

echo "=== Instalando servicio Orange Clock ==="

# Verificar que estamos ejecutando como root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Este script debe ejecutarse como root (sudo)"
    exit 1
fi

# Copiar el archivo de servicio
echo "Copiando archivo de servicio..."
cp orangeclock.service /etc/systemd/system/

#sudo nano /etc/systemd/system/orangeclock.service
# Recargar systemd
echo "Recargando systemd..."
systemctl daemon-reload

# Habilitar el servicio para que se inicie automáticamente
echo "Habilitando servicio..."
systemctl enable orangeclock.service

# Verificar dependencias de audio
echo "Verificando dependencias de audio..."

# Instalar dependencias
echo "Instalando dependencias..."
apt-get update
apt-get install -y mpg123 alsa-utils python3-tk

# Verificar si X11 está disponible
if ! command -v xauth &> /dev/null; then
    echo "Instalando xauth para soporte GUI..."
    apt-get install -y xauth
fi

# Configurar permisos de audio para el usuario pi
echo "Configurando permisos de audio..."
usermod -a -G audio pi

# Crear directorio de trabajo si no existe
echo "Creando directorio de trabajo..."
mkdir -p /orangeClock/audios
chown -R pi:pi /orangeClock

# Iniciar el servicio
echo "Iniciando servicio..."
systemctl start orangeclock.service

# Mostrar estado
echo "Estado del servicio:"
systemctl status orangeclock.service --no-pager

echo ""
echo "=== Instalación completada ==="
echo "Para ver los logs: sudo journalctl -u orangeclock.service -f"
echo "Para reiniciar: sudo systemctl restart orangeclock.service"
echo "Para detener: sudo systemctl stop orangeclock.service"