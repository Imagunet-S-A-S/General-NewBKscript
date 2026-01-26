#!/bin/bash
set -euo pipefail

################################################################################
# BACKUP INFRAESTRUCTURA DE MONITOREO
#
# Base por aplicación:
#   /var/lib/<aplicacion>/
#
# Estructura:
#   newest/      → últimos 7 días
#   YYYYMMDD/    → semana cerrada (domingo)
#   logs/        → backup.log (único)
################################################################################

# ============================================================================
# PARÁMETROS GENERALES
# ============================================================================

RETENTION_DAYS=21
HOT_DAYS=7

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
WEEK_END_DATE="$(date -d 'last sunday' +%Y%m%d)"

# ============================================================================
# LOGGING
# ============================================================================

log() {
    echo "[$(date '+%F %T')] [$1] $2" | tee -a "$LOG_FILE"
}

# ============================================================================
# UTILIDADES
# ============================================================================

is_service_running() {
    systemctl is-active --quiet "$1" 2>/dev/null || pgrep -f "$1" >/dev/null 2>&1
}

compress_dir() {
    local src="$1"
    local dst="$2"
    tar -czf "${dst}.tar.gz" -C "$(dirname "$src")" "$(basename "$src")" >>"$LOG_FILE" 2>&1
}

# ============================================================================
# ROTACIÓN POR APLICACIÓN
# ============================================================================

rotate_app_backups() {
    local base="$1"

    find "$base" -maxdepth 1 -type d -name "20*" -mtime +"$RETENTION_DAYS" -exec rm -rf {} \;
}

# ============================================================================
# PREPARAR DIRECTORIOS POR APP
# ============================================================================

prepare_app_dirs() {
    APP_BASE="$1"

    NEWEST_DIR="${APP_BASE}/newest"
    WEEK_DIR="${APP_BASE}/${WEEK_END_DATE}"
    LOG_DIR="${APP_BASE}/logs"
    LOG_FILE="${LOG_DIR}/backup.log"

    mkdir -p "$NEWEST_DIR"/{configs,databases,applications}
    mkdir -p "$WEEK_DIR"/{configs,databases,applications}
    mkdir -p "$LOG_DIR"

    : > "$LOG_FILE"
}

# ============================================================================
# BACKUPS POR APLICACIÓN
# ============================================================================

backup_zabbix() {
    prepare_app_dirs "/var/lib/zabbix"

    [[ -d /etc/zabbix ]] && compress_dir /etc/zabbix "$NEWEST_DIR/configs/zabbix_$TIMESTAMP"
    [[ -d /var/lib/zabbix ]] && compress_dir /var/lib/zabbix "$NEWEST_DIR/applications/zabbix_data_$TIMESTAMP"

    rotate_app_backups "/var/lib/zabbix"
}

backup_grafana() {
    prepare_app_dirs "/var/lib/grafana"

    [[ -d /etc/grafana ]] && compress_dir /etc/grafana "$NEWEST_DIR/configs/grafana_$TIMESTAMP"
    [[ -d /var/lib/grafana ]] && compress_dir /var/lib/grafana "$NEWEST_DIR/applications/grafana_data_$TIMESTAMP"

    rotate_app_backups "/var/lib/grafana"
}

backup_glpi() {
    prepare_app_dirs "/var/lib/glpi"

    [[ -d /var/www/glpi ]] && compress_dir /var/www/glpi "$NEWEST_DIR/applications/glpi_$TIMESTAMP"

    rotate_app_backups "/var/lib/glpi"
}

backup_mariadb() {
    prepare_app_dirs "/var/lib/mariadb"

    # Configuración
    local cfg=()
    [[ -f /etc/my.cnf ]] && cfg+=("/etc/my.cnf")
    [[ -d /etc/my.cnf.d ]] && cfg+=("/etc/my.cnf.d")

    [[ ${#cfg[@]} -gt 0 ]] && \
        tar -czf "$NEWEST_DIR/configs/mariadb_cfg_$TIMESTAMP.tar.gz" "${cfg[@]}" >>"$LOG_FILE" 2>&1

    # Bases de datos por DB
    local dbs
    dbs=$(mysql -N -e "SHOW DATABASES;" 2>>"$LOG_FILE" | grep -Ev "^(mysql|sys|information_schema|performance_schema)$")

    for db in $dbs; do
        mysqldump --single-transaction --routines --triggers "$db" \
            > "$NEWEST_DIR/databases/${db}_${TIMESTAMP}.sql" 2>>"$LOG_FILE"

        tar -czf "$NEWEST_DIR/databases/${db}_${TIMESTAMP}.tar.gz" \
            -C "$NEWEST_DIR/databases" "${db}_${TIMESTAMP}.sql"

        rm -f "$NEWEST_DIR/databases/${db}_${TIMESTAMP}.sql"
    done

    rotate_app_backups "/var/lib/mariadb"
}

# ============================================================================
# MAIN
# ============================================================================

is_service_running zabbix-server && backup_zabbix
is_service_running grafana-server && backup_grafana
[[ -d /var/www/glpi ]] && backup_glpi
is_service_running mariadb && command -v mysqldump >/dev/null && backup_mariadb
