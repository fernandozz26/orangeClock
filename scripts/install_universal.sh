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
    echo "ERROR: no se encontró ningún intérprete Python 3 en el sistema. Instala python3." | tee -a "$BACKEND_LOG"
    exit 1
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

# Determinar versión de Node requerida por package.json (engines.node). Si no está presente, usar 18
FRONT_PKG="$PROJECT_ROOT/scheduler-app/package.json"
REQ_NODE_SPEC=""
REQ_NODE_MAJOR=""
if [ -f "$FRONT_PKG" ]; then
    REQ_NODE_SPEC=$($PYTHON -c 'import json,sys
try:
    with open(sys.argv[1]) as f:
        j=json.load(f)
        engines=j.get("engines",{})
        print(engines.get("node",""))
except Exception:
    print("")' "$FRONT_PKG" 2>/dev/null || echo "")
fi

if [ -n "$REQ_NODE_SPEC" ]; then
    REQ_NODE_MAJOR=$(echo "$REQ_NODE_SPEC" | grep -oE '[0-9]+' | head -n1 || true)
fi
if [ -z "$REQ_NODE_MAJOR" ]; then
    REQ_NODE_MAJOR=18
fi
log "Especificación de Node en package.json: '$REQ_NODE_SPEC' -> requerimiento estimado: v$REQ_NODE_MAJOR"

# Comprobar Node instalado
INST_NODE_MAJOR=""
if command -v node >/dev/null 2>&1; then
    INST_NODE_MAJOR=$(node --version 2>/dev/null | grep -oE '[0-9]+' | head -n1 || true)
fi

if [ -n "$INST_NODE_MAJOR" ] && [ "$INST_NODE_MAJOR" -ge "$REQ_NODE_MAJOR" ]; then
    log "Node instalado (v$INST_NODE_MAJOR) satisface el requisito v$REQ_NODE_MAJOR. No se instalará otra versión."
else
    log "Node instalado (v${INST_NODE_MAJOR:-none}) no satisface requisito v$REQ_NODE_MAJOR. Instalando Node v$REQ_NODE_MAJOR via NodeSource"
    if ! install_node_version "$REQ_NODE_MAJOR"; then
        log "Falló la instalación de Node v$REQ_NODE_MAJOR via NodeSource. Intentando instalar v18 como fallback."
        if ! install_node_version 18; then
            echo "ERROR: no se pudo instalar una versión adecuada de Node (intentadas: $REQ_NODE_MAJOR, 18)" | tee -a "$BACKEND_LOG"
            exit 1
        fi
    fi
fi

# Asegurar npm en una versión moderna (intentar mantener equipo estable)
if command -v npm >/dev/null 2>&1; then
    log "Asegurando npm moderno: actualizando a npm@8 (si procede)"
    npm install -g npm@8 >>"$BACKEND_LOG" 2>&1 || log "Advertencia: no se pudo forzar npm@8, se continúa con la versión instalada"
fi

# Función para instalar Node.js
install_node_version() {
    local major=$1
    echo "Instalando Node.js v$major (intento via NodeSource)" | tee -a "$BACKEND_LOG"

    # Registrar arquitectura
    ARCH=$(uname -m)
    echo "Arquitectura detectada: $ARCH" | tee -a "$BACKEND_LOG"

    # Preparar output temporal
    TMP_OUT=$(mktemp)

    # Intentar NodeSource
    set +e
    curl -fsSL "https://deb.nodesource.com/setup_${major}.x" > "$TMP_OUT" 2>>"$BACKEND_LOG"
    if [ $? -eq 0 ]; then
        bash "$TMP_OUT" >>"$BACKEND_LOG" 2>&1
        if apt-get install -y nodejs >>"$BACKEND_LOG" 2>&1; then
            echo "Node v$major instalado via NodeSource" | tee -a "$BACKEND_LOG"
            rm -f "$TMP_OUT"
            set -e
            return 0
        else
            echo "Error: apt-get install nodejs falló al intentar NodeSource (v$major). Ver $BACKEND_LOG" | tee -a "$BACKEND_LOG"
        fi
    else
        echo "Error: curl fallo descargando NodeSource setup para v$major" | tee -a "$BACKEND_LOG"
    fi
    set -e

    # Si NodeSource falla, intentar tarball oficial por compatibilidad
    echo "Intentando fallback: descargar tarball oficial de nodejs.org para v${major}.x" | tee -a "$BACKEND_LOG"

    # Determinar arquitectura para el nombre del tarball
    UNAME_M=$(uname -m)
    case "$UNAME_M" in
        x86_64|amd64) NODE_ARCH="x64" ;;
        aarch64|arm64) NODE_ARCH="arm64" ;;
        i686|i386) NODE_ARCH="x86" ;;
        armv7l) NODE_ARCH="armv7l" ;;
        *) NODE_ARCH="x64" ;;
    esac
    echo "Arquitectura mapeada: $UNAME_M -> $NODE_ARCH" | tee -a "$BACKEND_LOG"

    # Obtener la versión exacta más reciente para el major consultando index.json
    IDX_JSON=$(mktemp)
    if curl -fsSL "https://nodejs.org/dist/index.json" -o "$IDX_JSON" >>"$BACKEND_LOG" 2>&1; then
        VERSION=$(grep -oE '"version":\s*"v[0-9]+\.[0-9]+\.[0-9]+"' "$IDX_JSON" | sed -E 's/"version":\s*"(v[0-9]+\.[0-9]+\.[0-9]+)"/\1/' | grep "^v${major}\." | head -n1 || true)
        rm -f "$IDX_JSON"
    else
        echo "Aviso: no se pudo descargar index.json para determinar versión exacta; se usará latest-v${major}.x" | tee -a "$BACKEND_LOG"
        VERSION=""
    fi

    if [ -z "$VERSION" ]; then
        # fallback a latest-v{major}.x
        VERSION="latest-v${major}.x"
        NODE_TARBALL_URL="https://nodejs.org/dist/${VERSION}/node-${VERSION}-linux-${NODE_ARCH}.tar.xz"
    else
        NODE_TARBALL_URL="https://nodejs.org/dist/${VERSION}/node-${VERSION}-linux-${NODE_ARCH}.tar.xz"
    fi

    TMPDIR=$(mktemp -d)
    TARFILE="$TMPDIR/node.tar.xz"

    echo "Descargando $NODE_TARBALL_URL" | tee -a "$BACKEND_LOG"
    if curl -fsSL -o "$TARFILE" "$NODE_TARBALL_URL" >>"$BACKEND_LOG" 2>&1; then
        echo "Descarga completada, extrayendo en /usr/local (requiere permisos)" | tee -a "$BACKEND_LOG"
        # Hacer backup de /usr/local/bin/node y /usr/local/bin/npm si existen
        if [ -x "/usr/local/bin/node" ]; then
            echo "Backup de /usr/local/bin/node existente en /usr/local/bin/node.bak" | tee -a "$BACKEND_LOG"
            mv /usr/local/bin/node /usr/local/bin/node.bak || true
        fi
        if [ -x "/usr/local/bin/npm" ]; then
            echo "Backup de /usr/local/bin/npm existente en /usr/local/bin/npm.bak" | tee -a "$BACKEND_LOG"
            mv /usr/local/bin/npm /usr/local/bin/npm.bak || true
        fi
        tar -C /usr/local --strip-components=1 -xJf "$TARFILE" >>"$BACKEND_LOG" 2>&1 || {
            echo "Error al extraer tarball en /usr/local" | tee -a "$BACKEND_LOG"
            rm -rf "$TMPDIR"
            return 1
        }
        echo "Node instalado desde tarball oficial (${VERSION})" | tee -a "$BACKEND_LOG"
        rm -rf "$TMPDIR"
        return 0
    else
        echo "ERROR: no se pudo descargar tarball oficial. URL intentada: $NODE_TARBALL_URL" | tee -a "$BACKEND_LOG"
        rm -rf "$TMPDIR"
        return 1
    fi
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
if [ ! -d "$BACKEND_DIR/venv" ]; then
    sudo $PYTHON -m venv "$BACKEND_DIR/venv" 2>>"$BACKEND_LOG" || { echo "ERROR: fallo al crear venv" | tee -a "$BACKEND_LOG"; exit 1; }
    log "Entorno virtual creado"
else
    log "Entorno virtual ya existe"
fi

log "Instalando requirements (si existe)"
if [ -f "$BACKEND_DIR/requirements.txt" ]; then
    sudo "$VENV_PIP" install -r "$BACKEND_DIR/requirements.txt" >>"$BACKEND_LOG" 2>&1 || echo "WARNING: pip install devolvió error, revisar $BACKEND_LOG"
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
"$VENV_PY" --version 2>&1 | tee -a "$BACKEND_LOG"
echo "---- pip freeze (venv) ----" | tee -a "$BACKEND_LOG"
sudo "$VENV_PIP" freeze 2>>"$BACKEND_LOG" | tee -a "$BACKEND_LOG"

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
        local_engine_issue=0
        if grep -Eiq "Unsupported engine|engine " "$FRONT_BUILD_LOG"; then
            echo "Fallo probablemente debido a versión de Node/NPM (Unsupported engine)" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
            local_engine_issue=1
        fi
        if grep -Eiq "requires.*node|requires node|requires a Node" "$FRONT_BUILD_LOG"; then
            echo "Fallo probablemente debido a requerimientos de versión de Node detectados en logs" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
            local_engine_issue=1
        fi
        if grep -Eiq "ERR! .*node|node.*unsupported|EBADENGINE" "$FRONT_BUILD_LOG"; then
            echo "Error de engine/versión detectado en npm (EBADENGINE o similar)" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
            local_engine_issue=1
        fi
        # Añadir diagnóstico de versiones instaladas
        echo "Node instalado: $(node --version 2>/dev/null || echo 'no disponible')" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
        echo "npm instalado: $(npm --version 2>/dev/null || echo 'no disponible')" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"

        # Si se detectó problema de engine, reintentar instalando Node v18 y rehacer build una vez
        if [ "$local_engine_issue" -eq 1 ]; then
            echo "Intentando reinstalar Node v18 y reintentar build..." | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
            if install_node_version 18; then
                # forzar npm a versión estable moderna
                npm install -g npm@8 >>"$FRONT_BUILD_LOG" 2>&1 || true
                # limpiar node_modules y volver a instalar
                rm -rf node_modules package-lock.json || true
                echo "Reintentando instalación de dependencias y build con Node v18" | tee -a "$FRONT_BUILD_LOG"
                if $BUILD_CMD_INSTALL >>"$FRONT_BUILD_LOG" 2>&1 && npm run build >>"$FRONT_BUILD_LOG" 2>&1; then
                    echo "Build frontend completado correctamente tras actualizar Node a v18" | tee -a "$FRONT_BUILD_LOG"
                else
                    echo "ERROR: el build falló aun después de instalar Node v18. Revisa $FRONT_BUILD_LOG" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
                fi
            else
                echo "ERROR: no se pudo instalar Node v18 para reintentar build" | tee -a "$BACKEND_LOG" "$FRONT_BUILD_LOG"
            fi
        fi
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
