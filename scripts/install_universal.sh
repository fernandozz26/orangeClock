#!/bin/bash

# === Configuración Universal para Orange Clock ===

# Variables generales
# Este script debe ejecutarse con sudo
if [ "$EUID" -ne 0 ]; then
    echo "Este script debe ejecutarse con sudo. Ejecuta: sudo $0"
    exit 1
fi

# Rutas basadas en la ubicación del script
SCRIPT_DIR=$(dirname "$(realpath "$0")")
PROJECT_ROOT=$(realpath "$SCRIPT_DIR/..")
BACKEND_SRC="$PROJECT_ROOT/backend"
FRONT_BUILD_SRC_DEFAULT="$PROJECT_ROOT/scheduler-app/build"

# Directorios de despliegue como root
USER=$(whoami)
HOME_DIR=$(eval echo ~$USER)
FRONTEND_DIR="$HOME_DIR/clock_frontend"
BACKEND_DIR="/root/clock_api"

# Validar que las fuentes existan
if [ ! -d "$BACKEND_SRC" ]; then
    echo "ERROR: no se encontró el directorio de backend en $BACKEND_SRC" >&2
    exit 1
fi

# Función para instalar paquetes si no están presentes
install_if_missing() {
    if ! dpkg -l | grep -q "$1"; then
        echo "Instalando $1..."
        sudo apt-get install -y "$1"
    else
        echo "$1 ya está instalado."
    fi
}

# Función para limpiar servicios existentes
clean_service() {
    local service_name=$1
    if systemctl list-units --full -all | grep -q "$service_name"; then
        echo "Eliminando servicio existente: $service_name"
        sudo systemctl stop "$service_name"
        sudo systemctl disable "$service_name"
        sudo rm -f "/etc/systemd/system/$service_name"
    fi
}

# Validar si los servicios fueron creados e iniciados correctamente
validate_service() {
    local service_name=$1
    if systemctl is-active --quiet "$service_name"; then
        echo "El servicio $service_name está activo."
    else
        echo "ERROR: El servicio $service_name no está activo. Verifica los logs con: sudo journalctl -u $service_name"
    fi
}

# Función de logging
log() {
    echo "[install_universal] $1"
}

# Archivo de log para backend
BACKEND_LOG="/var/log/clock_backend_install.log"
sudo rm -f "$BACKEND_LOG" || true
sudo touch "$BACKEND_LOG"
sudo chown $(whoami):$(whoami) "$BACKEND_LOG"

# Actualizar e instalar dependencias básicas
sudo apt-get update
install_if_missing "curl"
install_if_missing "python3"
install_if_missing "python3-venv"
install_if_missing "python3-pip"
install_if_missing "nodejs"
install_if_missing "npm"

# Configuración del Backend con validaciones y logs
log "Iniciando configuración del backend (root)..."
clean_service "clock_backend.service"

if [ ! -d "$BACKEND_DIR" ]; then
    log "Creando $BACKEND_DIR"
    sudo mkdir -p "$BACKEND_DIR"
fi

log "Copiando archivos desde workspace backend..."
if sudo cp -r "$BACKEND_SRC"/* "$BACKEND_DIR/"; then
    log "Archivos del backend copiados a $BACKEND_DIR"
else
    echo "ERROR: fallo al copiar archivos del backend desde $BACKEND_SRC" | tee -a "$BACKEND_LOG"
    ls -la "$BACKEND_SRC" | tee -a "$BACKEND_LOG"
    exit 1
fi

# Asegurar permisos
sudo chown -R root:root "$BACKEND_DIR"

# Verificaciones básicas
if [ ! -f "$BACKEND_DIR/schedule-controller.py" ]; then
    echo "ERROR: $BACKEND_DIR/schedule-controller.py no existe" | tee -a "$BACKEND_LOG"
    echo "Contenido de $BACKEND_DIR:" | tee -a "$BACKEND_LOG"
    ls -la "$BACKEND_DIR" | tee -a "$BACKEND_LOG"
    exit 1
fi

log "Creando/validando entorno virtual"
if [ ! -d "$BACKEND_DIR/venv" ]; then
    sudo python3 -m venv "$BACKEND_DIR/venv" 2>>"$BACKEND_LOG" || { echo "ERROR: fallo al crear venv" | tee -a "$BACKEND_LOG"; exit 1; }
    log "Entorno virtual creado"
else
    log "Entorno virtual ya existe"
fi

log "Instalando requirements (si existe)"
if [ -f "$BACKEND_DIR/requirements.txt" ]; then
    sudo "$BACKEND_DIR/venv/bin/pip" install -r "$BACKEND_DIR/requirements.txt" >>"$BACKEND_LOG" 2>&1 || echo "WARNING: pip install devolvió error, revisar $BACKEND_LOG"
else
    echo "WARNING: No existe requirements.txt en $BACKEND_DIR" | tee -a "$BACKEND_LOG"
fi

# Crear/recrear servicio del backend
if [ -f "/etc/systemd/system/clock_backend.service" ]; then
    log "Eliminando servicio /etc/systemd/system/clock_backend.service existente"
    sudo systemctl stop clock_backend.service || true
    sudo systemctl disable clock_backend.service || true
    sudo rm -f /etc/systemd/system/clock_backend.service
fi

log "Creando archivo de servicio /etc/systemd/system/clock_backend.service"
sudo tee /etc/systemd/system/clock_backend.service > /dev/null <<EOF
[Unit]
Description=Orange Clock Backend
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$BACKEND_DIR
ExecStart=$BACKEND_DIR/venv/bin/python3 $BACKEND_DIR/schedule-controller.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

log "Recargando daemon y arrancando servicio backend"
sudo systemctl daemon-reload
sudo systemctl enable --now clock_backend.service || true

# Esperar y capturar logs
sleep 2
log "Guardando logs recientes del servicio en $BACKEND_LOG"
sudo journalctl -u clock_backend.service -n 200 --no-pager >>"$BACKEND_LOG" 2>&1 || true

log "Resumen rápido de diagnóstico (backend):"
echo "---- $BACKEND_DIR content ----" | tee -a "$BACKEND_LOG"
ls -la "$BACKEND_DIR" | tee -a "$BACKEND_LOG"
echo "---- python version ----" | tee -a "$BACKEND_LOG"
"$BACKEND_DIR/venv/bin/python3" --version 2>&1 | tee -a "$BACKEND_LOG"
echo "---- pip freeze (venv) ----" | tee -a "$BACKEND_LOG"
sudo "$BACKEND_DIR/venv/bin/pip" freeze 2>>"$BACKEND_LOG" | tee -a "$BACKEND_LOG"

# Mostrar tail del log al usuario
log "Mostrando últimas líneas del log de backend:"
tail -n 50 "$BACKEND_LOG" || true

# Configuración del Frontend (OMITIENDO instalación de dependencias Node por ahora)
log "Configurando frontend: no se instalarán dependencias Node.js en esta ejecución (se omite npm install)"
clean_service "clock_frontend.service"

FRONT_BUILD_SRC="$FRONT_BUILD_SRC_DEFAULT"
FRONT_DEST="/var/www/clock_frontend"

# Asegurar directorio de despliegue y permisos
sudo mkdir -p "$FRONT_DEST"
sudo rm -rf "$FRONT_DEST"/* || true

if [ -d "$FRONT_BUILD_SRC" ]; then
    log "Copiando build del frontend a $FRONT_DEST"
    if sudo cp -r "$FRONT_BUILD_SRC"/* "$FRONT_DEST/"; then
        sudo chown -R caddy:caddy "$FRONT_DEST"
        sudo chmod -R a+rX "$FRONT_DEST"
        log "Build del frontend copiado a $FRONT_DEST y permisos asignados a caddy"
    else
        echo "ERROR: fallo al copiar build del frontend" | tee -a "$BACKEND_LOG"
    fi
else
    echo "WARNING: No existe build del frontend en $FRONT_BUILD_SRC. Frontend no desplegado." | tee -a "$BACKEND_LOG"
fi

# Eliminar cualquier servicio systemd del frontend (no lo recreamos ahora)
if systemctl list-units --full -all | grep -q "clock_frontend.service"; then
    log "Se eliminará cualquier service clock_frontend.service existente (no se recreará)."
    sudo systemctl stop clock_frontend.service || true
    sudo systemctl disable clock_frontend.service || true
    sudo rm -f /etc/systemd/system/clock_frontend.service || true
    sudo systemctl daemon-reload
fi

# Asegurar que Caddy esté instalado antes de configurar el Caddyfile
if ! command -v caddy >/dev/null 2>&1; then
    log "Caddy no encontrado. Instalando Caddy..."
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https ca-certificates gnupg >/dev/null 2>&1 || true
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/caddy-stable-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" > /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
    apt-get install -y caddy
    if command -v caddy >/dev/null 2>&1; then
        log "Caddy instalado correctamente"
    else
        echo "ERROR: Falló la instalación de Caddy" | tee -a "$BACKEND_LOG"
    fi
else
    log "caddy ya está instalado."
fi

# Actualizar Caddyfile para servir desde /var/www/clock_frontend
if [ -d "$FRONT_DEST" ]; then
    log "Configurando Caddy para servir $FRONT_DEST"
    sudo tee /etc/caddy/Caddyfile > /dev/null <<CADDY_EOF
:80 {
    root * $FRONT_DEST

    handle /api/* {
        reverse_proxy 127.0.0.1:5000
    }

    handle {
        try_files {path} /index.html
        file_server
    }
}
CADDY_EOF
    sudo systemctl restart caddy || true
    log "Caddy recargado"
else
    log "No se configuró Caddy porque no existe frontend build en $FRONT_DEST"
fi

# Validaciones finales
log "Validaciones finales:"
if systemctl is-active --quiet clock_backend.service; then
    echo "OK: clock_backend.service está activo" | tee -a "$BACKEND_LOG"
else
    echo "ERROR: clock_backend.service NO está activo. Revisa $BACKEND_LOG y journalctl -u clock_backend.service" | tee -a "$BACKEND_LOG"
fi

if systemctl list-units --full -all | grep -q "clock_frontend.service"; then
    echo "Advertencia: existe clock_frontend.service, pero no fue creado por este script" | tee -a "$BACKEND_LOG"
else
    echo "OK: no existe clock_frontend.service (frontend gestionado por Caddy si fue desplegado)" | tee -a "$BACKEND_LOG"
fi

if systemctl is-active --quiet caddy; then
    echo "OK: caddy está activo" | tee -a "$BACKEND_LOG"
else
    echo "ERROR: caddy no está activo" | tee -a "$BACKEND_LOG"
fi

log "Instalación/diagnóstico completado. Logs en: $BACKEND_LOG"

# Mensaje final
echo "=== Configuración completada ==="
echo "Servicios configurados:"
echo "- Backend: clock_backend.service"
echo "- Frontend: clock_frontend.service"
echo "- Caddy configurado para servir el frontend en producción."
echo "Para iniciar manualmente: sudo systemctl start clock_backend.service y clock_frontend.service"

# Recargar el daemon para asegurar que todos los servicios estén actualizados
sudo systemctl daemon-reload
