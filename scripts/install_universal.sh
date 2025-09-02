#!/bin/bash

# === Configuración Universal para Orange Clock ===

echo "Antes de continuar se debe tener instalado Node.js 20 y Python 3"

# Preguntar confirmación al usuario (si/no)
while true; do
    read -r -p "¿Deseas continuar con la instalación? (si/no): " RESP
    RESP_LOWER=$(echo "$RESP" | tr '[:upper:]' '[:lower:]')
    if [ "$RESP_LOWER" = "si" ]; then
        echo "Continuando con la instalación..."
        break
    elif [ "$RESP_LOWER" = "no" ]; then
        echo "Instalación cancelada por el usuario. Saliendo..."
        exit 0
    else
        echo "Respuesta no válida. Por favor responde 'si' o 'no'."
    fi
done

# Variables generales
# Este script debe ejecutarse con sudo
if [ "$EUID" -ne 0 ]; then
    echo "Este script debe ejecutarse con sudo. Ejecuta: sudo $0"
    exit 1
fi

# Priorizar node del usuario real (evita que sudo cambie el binario usado)
REAL_USER="${SUDO_USER:-$(whoami)}"
if [ "$REAL_USER" != "" ] && [ "$REAL_USER" != "root" ]; then
    USER_NODE=$(sudo -u "$REAL_USER" -H bash -lc 'command -v node 2>/dev/null || true')
    if [ -n "$USER_NODE" ]; then
        USER_NODE_RESOLVED=$(sudo -u "$REAL_USER" -H bash -lc 'readlink -f "$(command -v node)" 2>/dev/null || true')
        if [ -n "$USER_NODE_RESOLVED" ]; then
            NODE_DIR=$(dirname "$USER_NODE_RESOLVED")
            export PATH="$NODE_DIR:$PATH"
            log "Ajustado PATH para priorizar node de $REAL_USER: $USER_NODE_RESOLVED"
        else
            NODE_DIR=$(dirname "$USER_NODE")
            export PATH="$NODE_DIR:$PATH"
            log "Ajustado PATH para priorizar node de $REAL_USER: $USER_NODE"
        fi
    else
        log "No se encontró 'node' en el entorno del usuario $REAL_USER"
    fi
fi

# Registrar versiones para diagnóstico
log "node (según usuario $REAL_USER): $(sudo -u "$REAL_USER" -H bash -lc 'node --version 2>/dev/null || echo none')"
log "node (entorno del script): $(command -v node >/dev/null 2>&1 && node --version || echo none)"

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

# Detectar y usar Python 3 disponible (no sobrescribir sistema)
PYTHON_CANDIDATES=("python3.11" "python3.10" "python3.9" "python3.8" "python3")
PYTHON=""
for p in "${PYTHON_CANDIDATES[@]}"; do
    if command -v "$p" >/dev/null 2>&1; then
        if "$p" -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)'; then
            PYTHON="$p"
            break
        fi
    fi
done
if [ -z "$PYTHON" ]; then
    log "No se encontró Python3 en el sistema. Intentando instalar pyenv y una versión local de Python3 para el usuario actual..."

    # Determinar el usuario real cuando se ejecuta con sudo
    REAL_USER="${SUDO_USER:-$(whoami)}"
    REAL_HOME="$(eval echo ~${REAL_USER})"

    log "Usuario real: $REAL_USER, home: $REAL_HOME"

    # Instalar dependencias necesarias para compilar Python (si no están)
    apt-get update
    install_if_missing "git"
    install_if_missing "build-essential"
    install_if_missing "libssl-dev"
    install_if_missing "zlib1g-dev"
    install_if_missing "libbz2-dev"
    install_if_missing "libreadline-dev"
    install_if_missing "libsqlite3-dev"
    install_if_missing "llvm"
    install_if_missing "libncurses5-dev"
    install_if_missing "libncursesw5-dev"
    install_if_missing "xz-utils"
    install_if_missing "tk-dev"
    install_if_missing "libffi-dev"
    install_if_missing "liblzma-dev"

    # Clonar pyenv si no existe
    if [ ! -d "$REAL_HOME/.pyenv" ]; then
        log "Clonando pyenv en $REAL_HOME/.pyenv"
        sudo -u "$REAL_USER" -H git clone https://github.com/pyenv/pyenv.git "$REAL_HOME/.pyenv" || { echo "ERROR: fallo al clonar pyenv" | tee -a "$BACKEND_LOG"; exit 1; }
    else
        log "pyenv ya presente en $REAL_HOME/.pyenv"
    fi

    # Instalar una versión de Python (3.11.6) usando pyenv para el usuario real
    PYTHON_VERSION_TO_INSTALL="3.11.6"
    log "Instalando Python $PYTHON_VERSION_TO_INSTALL vía pyenv (usuario: $REAL_USER)"

    sudo -u "$REAL_USER" -H bash -lc '
        export PYENV_ROOT="$HOME/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init -)"
        if pyenv versions --bare | grep -q "^3.11.6$"; then
            echo "Python 3.11.6 ya instalado"
        else
            pyenv install 3.11.6 || { echo "ERROR: fallo al instalar Python 3.11.6" | tee -a "$BACKEND_LOG"; exit 1; }
        fi
        pyenv global 3.11.6
    ' || { echo "ERROR: fallo al configurar pyenv y Python 3.11.6" | tee -a "$BACKEND_LOG"; exit 1; }

    PYTHON="$REAL_HOME/.pyenv/shims/python3"
    log "Python configurado en: $PYTHON"
fi
log "Usando intérprete Python: $PYTHON"

# Variables para el venv (se establecerán cuando exista o se cree)
VENV_PY="$BACKEND_DIR/venv/bin/python"
VENV_PIP="$BACKEND_DIR/venv/bin/pip"

# Actualizar e instalar dependencias básicas
sudo apt-get update
install_if_missing "curl"
install_if_missing "python3"
install_if_missing "python3-venv"
install_if_missing "python3-pip"

# Asegurar que Python3 esté instalado (si no, instalarlo)
if ! command -v python3 >/dev/null 2>&1; then
    log "python3 no encontrado. Instalando python3 y herramientas relacionadas..."
    apt-get update
    apt-get install -y python3 python3-venv python3-pip ca-certificates || { echo "ERROR: no se pudo instalar python3" | tee -a "$BACKEND_LOG"; exit 1; }
    log "python3 instalado"
else
    log "python3 ya instalado: $(python3 --version)"
fi

# Comprobar que 'node' está instalado (no validar la versión)
if command -v node >/dev/null 2>&1; then
    log "Node detectado: $(node --version 2>/dev/null || echo 'desconocida')"
else
    echo "ERROR: Node.js no está instalado. Por favor instala Node.js y vuelve a ejecutar este script." | tee -a "$BACKEND_LOG"
    exit 1
fi

# Asegurar npm en una versión moderna (intentar mantener equipo estable)
if command -v npm >/dev/null 2>&1; then
    log "npm disponible: $(npm --version 2>/dev/null || echo 'desconocida')"
else
    log "npm no encontrado en PATH; si tu instalación de Node incluye npm, asegúrate de que esté en PATH"
fi

# Función para instalar Node.js (DESACTIVADA: se delega instalación a usuario)
install_node_version() {
    echo "install_node_version: instalación automática de Node está deshabilitada por petición del usuario. Por favor instala la versión necesaria manualmente." | tee -a "$BACKEND_LOG"
    return 1
}

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
# Forzar creación del venv con el intérprete Python detectado ($PYTHON)
if [ -d "$BACKEND_DIR/venv" ]; then
    log "Entorno virtual ya existe en $BACKEND_DIR/venv. Se recreará para garantizar coherencia."
    rm -rf "$BACKEND_DIR/venv"
fi

# Crear venv usando el python3 detectado
if ! $PYTHON -m venv "$BACKEND_DIR/venv" 2>>"$BACKEND_LOG"; then
    echo "ERROR: fallo al crear el entorno virtual con $PYTHON" | tee -a "$BACKEND_LOG"
    exit 1
fi

# Definir rutas del venv
VENV_PY="$BACKEND_DIR/venv/bin/python"
VENV_PIP="$BACKEND_DIR/venv/bin/pip"

# Asegurar permisos y propiedad adecuados
chown -R root:root "$BACKEND_DIR/venv" 2>>"$BACKEND_LOG" || true
chmod -R u+rwX "$BACKEND_DIR/venv" 2>>"$BACKEND_LOG" || true

# Actualizar pip/setuptools/wheel dentro del venv
log "Actualizando pip/setuptools/wheel dentro del venv"
if ! "$VENV_PY" -m pip install --upgrade pip setuptools wheel >>"$BACKEND_LOG" 2>&1; then
    echo "ERROR: no se pudo actualizar pip/setuptools/wheel en el venv" | tee -a "$BACKEND_LOG"
    exit 1
fi

# Instalar requirements dentro del venv si existe requirements.txt
if [ -f "$BACKEND_DIR/requirements.txt" ]; then
    log "Instalando dependencias en el venv desde requirements.txt"
    if ! "$VENV_PIP" install -r "$BACKEND_DIR/requirements.txt" >>"$BACKEND_LOG" 2>&1; then
        echo "ERROR: fallo al instalar requirements en el venv. Revisa $BACKEND_LOG" | tee -a "$BACKEND_LOG"
        echo "Salida de pip freeze parcial:" >>"$BACKEND_LOG"
        "$VENV_PIP" freeze >>"$BACKEND_LOG" 2>&1 || true
        exit 1
    fi
else
    log "No se encontró requirements.txt en $BACKEND_DIR; se omite instalación de dependencias" | tee -a "$BACKEND_LOG"
fi

# Verificar que Flask (ejemplo) está instalado en el venv para diagnóstico
if ! "$VENV_PY" -c "import pkgutil,sys
if pkgutil.find_loader('flask') is None:
    sys.exit(1)
" 2>/dev/null; then
    echo "WARNING: Flask no parece estar instalado dentro del venv. Revisa $BACKEND_LOG" | tee -a "$BACKEND_LOG"
    echo "Listado pip freeze:" >>"$BACKEND_LOG"
    "$VENV_PIP" freeze >>"$BACKEND_LOG" 2>&1 || true
    # No abortamos aquí porque puede que el backend no necesite flask exactamente, solo avisamos
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
# Usar el intérprete del virtualenv para garantizar uso de Python3 y dependencias instaladas
Environment=PATH=$BACKEND_DIR/venv/bin:/usr/local/bin:/usr/bin:/bin
Environment=PYTHONUNBUFFERED=1
ExecStart=$BACKEND_DIR/venv/bin/python $BACKEND_DIR/schedule-controller.py
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
"$VENV_PY" --version 2>&1 | tee -a "$BACKEND_LOG"
echo "---- pip freeze (venv) ----" | tee -a "$BACKEND_LOG"
sudo "$VENV_PIP" freeze 2>>"$BACKEND_LOG" | tee -a "$BACKEND_LOG"

# Mostrar tail del log al usuario
log "Mostrando últimas líneas del log de backend:"
tail -n 50 "$BACKEND_LOG" || true

# Configuración del Frontend: compilación simple y despliegue
log "Compilando frontend: npm install && npm run build"

FRONT_SRC="$PROJECT_ROOT/scheduler-app"
FRONT_BUILD_SRC="$FRONT_SRC/build"
FRONT_DEST="/var/www/clock_frontend"
FRONT_BUILD_LOG="/var/log/clock_frontend_build.log"

# Preparar log de build
sudo rm -f "$FRONT_BUILD_LOG" || true
sudo touch "$FRONT_BUILD_LOG"
sudo chown $(whoami):$(whoami) "$FRONT_BUILD_LOG"

if [ ! -d "$FRONT_SRC" ]; then
    echo "ERROR: no se encontró el frontend en $FRONT_SRC" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
else
    cd "$FRONT_SRC"

    echo "=== Ejecutando: npm install ===" | tee -a "$FRONT_BUILD_LOG"
    if npm install --no-audit --no-fund >>"$FRONT_BUILD_LOG" 2>&1; then
        echo "npm install completado" | tee -a "$FRONT_BUILD_LOG"
    else
        echo "ERROR: npm install falló. Revisa $FRONT_BUILD_LOG" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
    fi

    echo "=== Ejecutando: npm run build ===" | tee -a "$FRONT_BUILD_LOG"
    if npm run build >>"$FRONT_BUILD_LOG" 2>&1; then
        echo "npm run build completado" | tee -a "$FRONT_BUILD_LOG"
    else
        echo "ERROR: npm run build falló. Revisa $FRONT_BUILD_LOG" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
    fi

    # Copiar build si existe
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
