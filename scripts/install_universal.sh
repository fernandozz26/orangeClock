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

# Forzar instalación de Node.js v12.22.9 y npm 8.5.1
log "Asegurando Node.js v12.22.9 y npm 8.5.1"
NODE_VERSION="12.22.9"
NPM_VERSION="8.5.1"

# Eliminar paquetes previos que puedan interferir
if dpkg -l | grep -q nodejs || dpkg -l | grep -q npm; then
    log "Eliminando paquetes nodejs/npm instalados por apt (si existen)"
    apt-get remove -y nodejs npm || true
fi

TMPDIR=$(mktemp -d)
NODE_TARBALL="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz"
log "Descargando $NODE_TARBALL"
if curl -fsSL -o "$TMPDIR/node.tar.xz" "$NODE_TARBALL"; then
    log "Descargado correctamente"
else
    echo "ERROR: fallo al descargar Node.js v$NODE_VERSION" | tee -a "$BACKEND_LOG"
    rm -rf "$TMPDIR"
    exit 1
fi

log "Instalando Node.js en /usr/local"
# Extraer sobre /usr/local, sobrescribiendo binarios
tar -C /usr/local --strip-components=1 -xJf "$TMPDIR/node.tar.xz" || { echo "ERROR: fallo al extraer Node.js" | tee -a "$BACKEND_LOG"; rm -rf "$TMPDIR"; exit 1; }
rm -rf "$TMPDIR"

# Forzar que /usr/local/bin esté primero en PATH para este script
export PATH="/usr/local/bin:$PATH"

# Instalar npm requerido
if command -v npm >/dev/null 2>&1; then
    log "Instalando npm@$NPM_VERSION globalmente"
    npm install -g "npm@${NPM_VERSION}" >>"$BACKEND_LOG" 2>&1 || echo "WARNING: fallo al instalar npm@${NPM_VERSION}" | tee -a "$BACKEND_LOG"
else
    echo "ERROR: npm no está disponible tras instalar Node.js" | tee -a "$BACKEND_LOG"
fi

# Validar versiones exactas
INST_NODE_VER=$(node --version 2>/dev/null || echo "")
INST_NPM_VER=$(npm --version 2>/dev/null || echo "")
log "Node instalado: $INST_NODE_VER, npm instalado: $INST_NPM_VER"
if [ "$INST_NODE_VER" != "v${NODE_VERSION}" ]; then
    echo "ERROR: Node.js no es v${NODE_VERSION} (instalado: $INST_NODE_VER)" | tee -a "$BACKEND_LOG"
fi
if [ "$INST_NPM_VER" != "${NPM_VERSION}" ]; then
    echo "ERROR: npm no es ${NPM_VERSION} (instalado: $INST_NPM_VER)" | tee -a "$BACKEND_LOG"
fi

# Mostrar versiones
log "Versiones instaladas: $(node --version 2>/dev/null || echo 'node no instalado') $(npm --version 2>/dev/null || echo 'npm no instalado')"

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

# Configuración del Frontend (compilación y despliegue)
log "Configurando frontend: se intentará compilar el build desde el código fuente"
clean_service "clock_frontend.service"

FRONT_SRC="$PROJECT_ROOT/scheduler-app"
FRONT_BUILD_SRC="$FRONT_SRC/build"
FRONT_DEST="/var/www/clock_frontend"
FRONT_BUILD_LOG="/var/log/clock_frontend_build.log"

# Preparar log de build
sudo rm -f "$FRONT_BUILD_LOG" || true
sudo touch "$FRONT_BUILD_LOG"
sudo chown $(whoami):$(whoami) "$FRONT_BUILD_LOG"

# Comprobar que FRONT_SRC existe
if [ ! -d "$FRONT_SRC" ]; then
    echo "ERROR: no se encontró el frontend en $FRONT_SRC" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
else
    # Intentar instalar dependencias y construir
    log "Usando Node: $(/usr/local/bin/node --version 2>/dev/null || node --version 2>/dev/null || echo 'node no disponible')"
    log "Usando npm: $(/usr/local/bin/npm --version 2>/dev/null || npm --version 2>/dev/null || echo 'npm no disponible')"

    cd "$FRONT_SRC"

    # Instalar dependencias (npm ci si package-lock existe, sino npm install)
    if [ -f "package-lock.json" ]; then
        BUILD_CMD_INSTALL="npm ci --no-audit --no-fund"
    else
        BUILD_CMD_INSTALL="npm install --no-audit --no-fund"
    fi

    echo "=== Iniciando instalación de dependencias del frontend ===" | tee -a "$FRONT_BUILD_LOG"
    if $BUILD_CMD_INSTALL >>"$FRONT_BUILD_LOG" 2>&1; then
        echo "Dependencias instaladas correctamente" | tee -a "$FRONT_BUILD_LOG"
    else
        echo "ERROR: fallo al instalar dependencias del frontend. Revisa $FRONT_BUILD_LOG" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
    fi

    echo "=== Iniciando build del frontend (npm run build) ===" | tee -a "$FRONT_BUILD_LOG"
    if npm run build >>"$FRONT_BUILD_LOG" 2>&1; then
        echo "Build frontend completado correctamente" | tee -a "$FRONT_BUILD_LOG"
    else
        echo "ERROR: fallo en npm run build. Revisando causas comunes..." | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
        # Detectar problemas de engine / versión de node
        if grep -Eiq "Unsupported engine|engine " "$FRONT_BUILD_LOG"; then
            echo "Fallo probablemente debido a versión de Node/NPM (Unsupported engine)" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
        fi
        if grep -Eiq "requires.*node|requires node|requires a Node" "$FRONT_BUILD_LOG"; then
            echo "Fallo probablemente debido a requerimientos de versión de Node detectados en logs" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
        fi
        if grep -Eiq "ERR! .*node|node.*unsupported|EBADENGINE" "$FRONT_BUILD_LOG"; then
            echo "Error de engine/versión detectado en npm (EBADENGINE o similar)" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
        fi
        # Añadir diagnóstico de versiones instaladas
        echo "Node instalado: $(node --version 2>/dev/null || echo 'no disponible')" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
        echo "npm instalado: $(npm --version 2>/dev/null || echo 'no disponible')" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
    fi

    # Si build existe, copiarlo a destino; si no, informar
    if [ -d "$FRONT_BUILD_SRC" ]; then
        sudo mkdir -p "$FRONT_DEST"
        sudo rm -rf "$FRONT_DEST"/* || true
        if sudo cp -r "$FRONT_BUILD_SRC"/* "$FRONT_DEST/"; then
            sudo chown -R caddy:caddy "$FRONT_DEST"
            sudo chmod -R a+rX "$FRONT_DEST"
            log "Build del frontend copiado a $FRONT_DEST y permisos asignados a caddy"
        else
            echo "ERROR: fallo al copiar build del frontend a $FRONT_DEST" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
        fi
    else
        echo "WARNING: no se encontró build en $FRONT_BUILD_SRC tras intentar compilar. Revisa $FRONT_BUILD_LOG" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
    fi
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
