#!/bin/bash

# Script de desinstalación para Orange Clock
# Debe ejecutarse con sudo
if [ "$EUID" -ne 0 ]; then
    echo "Este script debe ejecutarse con sudo: sudo $0"
    exit 1
fi

set -euo pipefail

log() { echo "[uninstall] $1"; }

# Servicios a eliminar
SERVICES=(clock_backend.service clock_frontend.service)

# Parar, deshabilitar y eliminar servicios y symlinks
for svc in "${SERVICES[@]}"; do
    if systemctl list-units --all | grep -q "$svc"; then
        log "Deteniendo $svc"
        systemctl stop "$svc" || true
        log "Deshabilitando $svc"
        systemctl disable "$svc" || true
    else
        log "Servicio $svc no activo o no registrado, aún intentando limpiar archivos"
    fi

    # Eliminar unit file en /etc/systemd/system
    if [ -f "/etc/systemd/system/$svc" ]; then
        log "Eliminando unit file /etc/systemd/system/$svc"
        rm -f "/etc/systemd/system/$svc"
    fi

    # Eliminar symlink en multi-user.target.wants si existe
    if [ -L "/etc/systemd/system/multi-user.target.wants/$svc" ]; then
        log "Eliminando symlink /etc/systemd/system/multi-user.target.wants/$svc"
        rm -f "/etc/systemd/system/multi-user.target.wants/$svc" || true
    fi

    # En caso de que exista en /lib/systemd/system (no creado por nosotros), solo reportar
    if [ -f "/lib/systemd/system/$svc" ]; then
        log "Advertencia: existe /lib/systemd/system/$svc pero no será eliminado por este script"
    fi

done

log "Resetear fallos y recargar systemd"
systemctl reset-failed || true
systemctl daemon-reload || true

# Backups y eliminación de Caddyfile si fue creado por el instalador
CADDYFILE="/etc/caddy/Caddyfile"
CADDYBAK="/etc/caddy/Caddyfile.orangeclock.bak"
if [ -f "$CADDYFILE" ]; then
    if grep -q "/var/www/clock_frontend" "$CADDYFILE" || grep -q "clock_frontend" "$CADDYFILE"; then
        log "Haciendo backup de $CADDYFILE en $CADDYBAK"
        cp "$CADDYFILE" "$CADDYBAK"
        log "Eliminando Caddyfile creado por Orange Clock"
        rm -f "$CADDYFILE"
        log "Recargando/reiniciando caddy"
        systemctl restart caddy || true
    else
        log "Caddyfile no parece estar gestionado por Orange Clock; se deja intacto"
    fi
else
    log "No existe $CADDYFILE"
fi

# Rutas desplegadas a eliminar
PATHS=(/root/clock_api /root/clock_frontend /var/www/clock_frontend /var/log/clock_backend_install.log /var/log/clock_backend_runtime.log /usr/local/bin/clock_backend_start.sh)

for p in "${PATHS[@]}"; do
    if [ -e "$p" ]; then
        log "Eliminando $p"
        rm -rf "$p" || true
    else
        log "No existe $p, omitiendo"
    fi
done

# Recargar systemd de nuevo y mostrar estado
log "Recargando daemon de systemd (final)"
systemctl daemon-reload || true

log "Resumen final: estado de servicios relevantes:"
for svc in "${SERVICES[@]}"; do
    if systemctl list-units --all | grep -q "$svc"; then
        systemctl status -l "$svc" --no-pager || true
    else
        log "$svc eliminado"
    fi
done

log "Comprobando Caddy"
if systemctl is-active --quiet caddy; then
    log "Caddy activo"
else
    log "Caddy no activo"
fi

log "Desinstalación completada. Si quieres reinstalar, ejecuta el script de instalación."
