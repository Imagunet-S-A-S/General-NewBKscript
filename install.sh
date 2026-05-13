#!/bin/bash
set -euo pipefail

###############################################################################
# INSTALL.SH – SISTEMA DE BACKUP DE INFRAESTRUCTURA
###############################################################################

INSTALL_DIR="/opt/backup-scripts"
CONF_DIR="/etc/backup-imagunet"
SCRIPT_NAME="backup_infrastructure.sh"
CONFIG_NAME="backup.conf"
CRON_SCHEDULE="0 2 * * *"

# ============================================================================
# LOG
# ============================================================================

log() { echo "[INSTALL] $1"; }

# ============================================================================
# ROOT
# ============================================================================

if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ejecutarse como root"
    exit 1
fi

# ============================================================================
# DEPENDENCIAS
# ============================================================================

log "Verificando dependencias básicas..."

missing=()
command -v tar  >/dev/null 2>&1 || missing+=("tar")
command -v curl >/dev/null 2>&1 || missing+=("curl")

if [[ ${#missing[@]} -gt 0 ]]; then
    log "Instalando dependencias: ${missing[*]}"
    if   command -v dnf     >/dev/null 2>&1; then dnf     install -y "${missing[@]}"
    elif command -v yum     >/dev/null 2>&1; then yum     install -y "${missing[@]}"
    elif command -v apt-get >/dev/null 2>&1; then apt-get install -y "${missing[@]}"
    else echo "No se pudo determinar el gestor de paquetes"; exit 1
    fi
fi

# ============================================================================
# ARCHIVOS FUENTE
# ============================================================================

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f "$SRC_DIR/$SCRIPT_NAME" ]] || { echo "Error: $SCRIPT_NAME no encontrado"; exit 1; }
[[ -f "$SRC_DIR/$CONFIG_NAME" ]] || { echo "Error: $CONFIG_NAME no encontrado"; exit 1; }

# ============================================================================
# SCRIPT DE BACKUP
# ============================================================================

log "Instalando script en $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
install -m 750 "$SRC_DIR/$SCRIPT_NAME" "$INSTALL_DIR/$SCRIPT_NAME"
sed -i 's/\r$//' "$INSTALL_DIR/$SCRIPT_NAME"

ln -sf "$INSTALL_DIR/$SCRIPT_NAME" /usr/local/bin/backup-now

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

mkdir -p "$CONF_DIR"

if [[ ! -f "$CONF_DIR/$CONFIG_NAME" ]]; then
    log "Instalando configuración en $CONF_DIR/$CONFIG_NAME..."
    install -m 640 "$SRC_DIR/$CONFIG_NAME" "$CONF_DIR/$CONFIG_NAME"
    sed -i 's/\r$//' "$CONF_DIR/$CONFIG_NAME"
else
    log "ATENCIÓN: $CONF_DIR/$CONFIG_NAME ya existe — no se sobreescribió."
    log "          Revisar manualmente si hay nuevas variables en $SRC_DIR/$CONFIG_NAME"
fi

# ============================================================================
# CRON (ÚNICO – 02:00 AM)
# ============================================================================

log "Configurando cron diario a las 02:00 AM..."

CRON_ENTRY="${CRON_SCHEDULE} . ${CONF_DIR}/${CONFIG_NAME} && ${INSTALL_DIR}/${SCRIPT_NAME} >/dev/null 2>&1"

(crontab -l 2>/dev/null | grep -vF "${INSTALL_DIR}/${SCRIPT_NAME}" || true; echo "$CRON_ENTRY") | crontab -

# ============================================================================
# RESUMEN
# ============================================================================

echo ""
echo "==============================================="
echo " Instalación completada"
echo "==============================================="
echo ""
echo " Script  : $INSTALL_DIR/$SCRIPT_NAME"
echo " Config  : $CONF_DIR/$CONFIG_NAME"
echo " Cron    : Diario a las 02:00 AM"
echo ""
echo " Ejecución manual:"
echo "   backup-now"
echo ""
