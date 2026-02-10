#!/bin/bash
set -euo pipefail

###############################################################################
# INSTALL.SH – SISTEMA DE BACKUP DE INFRAESTRUCTURA
###############################################################################

INSTALL_DIR="/opt/backup-scripts"
SCRIPT_NAME="backup_infrastructure.sh"
CONFIG_NAME="backup.conf"

CRON_SCHEDULE="0 2 * * *"

# ============================================================================
# LOG
# ============================================================================

log() {
    echo "[INSTALL] $1"
}

# ============================================================================
# ROOT
# ============================================================================

if [[ $EUID -ne 0 ]]; then
    echo "Este script debe ejecutarse como root"
    exit 1
fi

# ============================================================================
# DEPENDENCIAS SEGURAS
# ============================================================================

log "Verificando dependencias básicas..."

missing=()

command -v tar >/dev/null 2>&1 || missing+=("tar")
command -v curl >/dev/null 2>&1 || missing+=("curl")

if [[ ${#missing[@]} -gt 0 ]]; then
    log "Instalando dependencias básicas: ${missing[*]}"

    if command -v dnf >/dev/null 2>&1; then
        dnf install -y tar curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y tar curl
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y tar curl
    else
        echo "No se pudo determinar el gestor de paquetes"
        exit 1
    fi
fi

# ============================================================================
# DIRECTORIO DE INSTALACIÓN
# ============================================================================

log "Creando directorio de instalación..."

mkdir -p "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

# ============================================================================
# COPIA DE ARCHIVOS
# ============================================================================

log "Copiando scripts..."

cp "$SCRIPT_NAME" "$INSTALL_DIR/"
cp "$CONFIG_NAME" "$INSTALL_DIR/"

chmod 750 "$INSTALL_DIR/$SCRIPT_NAME"
chmod 600 "$INSTALL_DIR/$CONFIG_NAME"

# Normalizar CRLF si viniera de Windows
sed -i 's/\r$//' "$INSTALL_DIR/$CONFIG_NAME"
sed -i 's/\r$//' "$INSTALL_DIR/$SCRIPT_NAME"

# ============================================================================
# SYMLINK
# ============================================================================

log "Creando acceso rápido /usr/local/bin/backup-now"

ln -sf "$INSTALL_DIR/$SCRIPT_NAME" /usr/local/bin/backup-now

# ============================================================================
# CRON (ÚNICO – 02:00 AM)
# ============================================================================

log "Configurando cron diario a las 02:00 AM"

CRON_ENTRY="${CRON_SCHEDULE} source ${INSTALL_DIR}/${CONFIG_NAME} && ${INSTALL_DIR}/${SCRIPT_NAME} >/dev/null 2>&1"

(crontab -l 2>/dev/null | grep -v backup_infrastructure || true; echo "$CRON_ENTRY") | crontab -

# ============================================================================
# FINAL
# ============================================================================

echo ""
echo "==============================================="
echo " Instalación completada correctamente"
echo "==============================================="
echo ""
echo " Script : $INSTALL_DIR/$SCRIPT_NAME"
echo " Config : $INSTALL_DIR/$CONFIG_NAME"
echo " Cron   : Diario a las 02:00 AM"
echo ""
echo " Ejecución manual:"
echo "   backup-now"
echo ""
