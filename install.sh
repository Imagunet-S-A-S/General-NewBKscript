#!/bin/bash

################################################################################
# SCRIPT DE INSTALACIÓN DEL SISTEMA DE BACKUP
# ============================================================================
# Propósito : Instalar y configurar el sistema de backup de monitoreo
# Ejecución : Backup diario a las 02:00 AM vía cron
# Versión   : FINAL (detección segura de dependencias)
# Uso       : sudo bash install.sh
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

INSTALL_DIR="${INSTALL_DIR:-/opt/backup-scripts}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"

# ============================================================================
# COLORES
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# LOG
# ============================================================================

log() {
    local level="$1"; shift
    local msg="$*"

    case "$level" in
        INFO)    echo -e "${BLUE}[INFO]${NC} $msg" ;;
        SUCCESS) echo -e "${GREEN}[SUCCESS]${NC} $msg" ;;
        WARN)    echo -e "${YELLOW}[WARN]${NC} $msg" ;;
        ERROR)   echo -e "${RED}[ERROR]${NC} $msg" ;;
    esac
}

# ============================================================================
# VALIDACIONES
# ============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "Este script debe ejecutarse como root"
        exit 1
    fi
}

# ============================================================================
# VERIFICACIÓN DE DEPENDENCIAS (MODO SEGURO)
# ============================================================================

check_requirements() {
    log INFO "Verificando dependencias del sistema (modo seguro)..."

    # ----------------------------
    # Dependencias básicas (seguras)
    # ----------------------------
    local basic_missing=()

    command -v tar  >/dev/null 2>&1 || basic_missing+=("tar")
    command -v curl >/dev/null 2>&1 || basic_missing+=("curl")

    if [[ ${#basic_missing[@]} -gt 0 ]]; then
        log INFO "Instalando dependencias básicas: ${basic_missing[*]}"

        if command -v apt-get &>/dev/null; then
            apt-get update
            apt-get install -y tar curl
        elif command -v yum &>/dev/null; then
            yum install -y tar curl
        else
            log ERROR "No se pudo determinar el gestor de paquetes"
            exit 1
        fi
    fi

    # ----------------------------
    # MariaDB / MySQL (detección)
    # ----------------------------
    if command -v mysqldump >/dev/null 2>&1; then
        log SUCCESS "mysqldump detectado (MariaDB/MySQL disponible)"
    else
        if command -v rpm >/dev/null 2>&1 && rpm -qa | grep -qiE 'mariadb|mysql'; then
            log WARN "MariaDB/MySQL detectado, pero mysqldump no está disponible"
            log WARN "El backup de MariaDB/MySQL será omitido"
        else
            log INFO "MariaDB/MySQL no instalado (no se realizará backup)"
        fi
    fi

    # ----------------------------
    # PostgreSQL (detección)
    # ----------------------------
    if command -v pg_dump >/dev/null 2>&1; then
        log SUCCESS "pg_dump detectado (PostgreSQL disponible)"
    else
        if command -v rpm >/dev/null 2>&1 && rpm -qa | grep -qi postgresql; then
            log WARN "PostgreSQL detectado, pero pg_dump no está disponible"
            log WARN "El backup de Airflow PostgreSQL será omitido"
        else
            log INFO "PostgreSQL no instalado (no se realizará backup Airflow)"
        fi
    fi

    log SUCCESS "Verificación de dependencias completada"
}

# ============================================================================
# DIRECTORIOS
# ============================================================================

create_directories() {
    log INFO "Creando estructura de directorios..."

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$BACKUP_DIR"/{logs,configs,databases,applications}

    chmod 755 "$BACKUP_DIR"
    chmod 755 "$BACKUP_DIR"/{logs,configs,databases,applications}

    # Directorio snapshots OpenSearch (debe existir en path.repo)
    mkdir -p /var/lib/opensearch/snapshots
    chown -R opensearch:opensearch /var/lib/opensearch/snapshots 2>/dev/null || true
    chmod 750 /var/lib/opensearch/snapshots

    log SUCCESS "Directorios creados correctamente"
}

# ============================================================================
# COPIA DE ARCHIVOS
# ============================================================================

copy_scripts() {
    log INFO "Copiando script de backup..."

    if [[ -f "backup_infrastructure.sh" ]]; then
        cp backup_infrastructure.sh "$INSTALL_DIR/"
        chmod 750 "$INSTALL_DIR/backup_infrastructure.sh"
        log SUCCESS "backup_infrastructure.sh copiado"
    else
        log ERROR "backup_infrastructure.sh no encontrado"
        exit 1
    fi
}

copy_config() {
    log INFO "Copiando archivo de configuración..."

    if [[ -f "backup.conf" ]]; then
        cp backup.conf "$INSTALL_DIR/"
        chmod 600 "$INSTALL_DIR/backup.conf"
        log SUCCESS "backup.conf copiado con permisos 600"
    else
        log ERROR "backup.conf no encontrado"
        exit 1
    fi
}

# ============================================================================
# CRON (ÚNICO HORARIO 02:00 AM)
# ============================================================================

configure_cron() {
    echo ""
    read -p "¿Configurar backup automático diario a las 02:00 AM vía cron? (s/n): " -r response
    [[ ! "$response" =~ ^[Ss]$ ]] && return

    local cron_schedule="0 2 * * *"
    local cron_entry="${cron_schedule} source ${INSTALL_DIR}/backup.conf && ${INSTALL_DIR}/backup_infrastructure.sh >> ${BACKUP_DIR}/logs/cron.log 2>&1"

    (crontab -l 2>/dev/null | grep -v backup_infrastructure || true; echo "$cron_entry") | crontab -

    log SUCCESS "Cron configurado correctamente: Diario a las 02:00 AM"
}

# ============================================================================
# SYMLINK
# ============================================================================

create_symlink() {
    log INFO "Creando acceso rápido..."

    ln -sf "$INSTALL_DIR/backup_infrastructure.sh" /usr/local/bin/backup-now

    log SUCCESS "Comando disponible: backup-now"
}

# ============================================================================
# BACKUP DE PRUEBA
# ============================================================================

create_test_backup() {
    echo ""
    read -p "¿Ejecutar backup de prueba ahora? (s/n): " -r response
    [[ ! "$response" =~ ^[Ss]$ ]] && return

    log INFO "Ejecutando backup de prueba..."

    if bash -c "source ${INSTALL_DIR}/backup.conf && ${INSTALL_DIR}/backup_infrastructure.sh"; then
        log SUCCESS "Backup de prueba completado"
        du -sh "$BACKUP_DIR"/*
    else
        log ERROR "Backup de prueba falló, revisa logs"
    fi
}

# ============================================================================
# RESUMEN
# ============================================================================

show_summary() {
    echo ""
    echo -e "${GREEN}Instalación completada correctamente${NC}"
    echo ""
    echo "Scripts instalados en : $INSTALL_DIR"
    echo "Backups almacenados en: $BACKUP_DIR"
    echo ""
    echo "Ejecución automática:"
    echo "  - Diario a las 02:00 AM (cron)"
    echo ""
    echo "Comando manual:"
    echo "  backup-now"
    echo ""
    echo "Logs:"
    echo "  $BACKUP_DIR/logs/"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    check_root
    check_requirements
    create_directories
    copy_scripts
    copy_config
    configure_cron
    create_symlink
    create_test_backup
    show_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
