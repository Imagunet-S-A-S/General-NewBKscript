#!/bin/bash
set -euo pipefail

###############################################################################
# UNINSTALL.SH – SISTEMA DE BACKUP DE INFRAESTRUCTURA
###############################################################################

INSTALL_DIR="/opt/backup-scripts"
CONF_DIR="/etc/backup-imagunet"
SYSTEMD_DIR="/etc/systemd/system"
SCRIPT_NAME="backup_infrastructure.sh"
SERVICE_NAME="backup-imagunet"

log()  { echo "[UNINSTALL] $1"; }
warn() { echo "[UNINSTALL] ATENCIÓN: $1"; }

# ============================================================================
# ROOT
# ============================================================================

if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ejecutarse como root"
    exit 1
fi

# ============================================================================
# CRON
# ============================================================================

if crontab -l 2>/dev/null | grep -qF "$INSTALL_DIR/$SCRIPT_NAME"; then
    log "Eliminando entrada de cron..."
    (crontab -l 2>/dev/null | grep -vF "$INSTALL_DIR/$SCRIPT_NAME") | crontab -
else
    log "No se encontró entrada de cron — omitiendo"
fi

# ============================================================================
# SYSTEMD (si fue instalado como servicio en algún momento)
# ============================================================================

for unit in "${SERVICE_NAME}.timer" "${SERVICE_NAME}.service"; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${unit}"; then
        log "Deteniendo y deshabilitando ${unit}..."
        systemctl stop    "$unit" 2>/dev/null || true
        systemctl disable "$unit" 2>/dev/null || true
    fi
done

for unit_file in "${SYSTEMD_DIR}/${SERVICE_NAME}.service" "${SYSTEMD_DIR}/${SERVICE_NAME}.timer"; do
    if [[ -f "$unit_file" ]]; then
        log "Eliminando $unit_file..."
        rm -f "$unit_file"
    fi
done

systemctl daemon-reload 2>/dev/null || true

# ============================================================================
# SYMLINK
# ============================================================================

if [[ -L /usr/local/bin/backup-now ]]; then
    log "Eliminando symlink /usr/local/bin/backup-now..."
    rm -f /usr/local/bin/backup-now
fi

# ============================================================================
# SCRIPT DE BACKUP
# ============================================================================

if [[ -d "$INSTALL_DIR" ]]; then
    log "Eliminando $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
fi

# ============================================================================
# CONFIGURACIÓN – pregunta antes de borrar
# ============================================================================

if [[ -d "$CONF_DIR" ]]; then
    echo ""
    read -r -p "[UNINSTALL] ¿Eliminar la configuración en $CONF_DIR? [s/N] " resp
    if [[ "${resp,,}" == "s" ]]; then
        log "Eliminando $CONF_DIR..."
        rm -rf "$CONF_DIR"
    else
        warn "$CONF_DIR conservado — bórralo manualmente si ya no lo necesitas"
    fi
fi

# ============================================================================
# RESUMEN
# ============================================================================

echo ""
echo "==============================================="
echo " Desinstalación completada"
echo "==============================================="
echo ""
echo " Eliminado : $INSTALL_DIR"
echo " Eliminado : /usr/local/bin/backup-now"
echo " Eliminado : cron entry"
echo ""
