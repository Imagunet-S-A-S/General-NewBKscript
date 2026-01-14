#!/bin/bash
set -euo pipefail

################################################################################
# BACKUP INFRAESTRUCTURA DE MONITOREO
# Versión final (sin restore)
################################################################################

# ---------------------------------------------------------------------
# LOCK
# ---------------------------------------------------------------------
exec 9>/var/run/backup_infrastructure.lock || exit 1
flock -n 9 || exit 0

# ---------------------------------------------------------------------
# VARIABLES
# ---------------------------------------------------------------------
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/backups}"
LOG_DIR="${BACKUP_BASE_DIR}/logs"
CONFIG_BACKUP_DIR="${BACKUP_BASE_DIR}/configs"
DB_BACKUP_DIR="${BACKUP_BASE_DIR}/databases"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/backup_${TIMESTAMP}.log"

mkdir -p "$LOG_DIR" "$CONFIG_BACKUP_DIR" "$DB_BACKUP_DIR"
touch "$LOG_FILE"

# ---------------------------------------------------------------------
# LOG
# ---------------------------------------------------------------------
log() {
    echo "[$(date '+%F %T')] [$1] $2" | tee -a "$LOG_FILE"
}

# ---------------------------------------------------------------------
# UTILIDADES
# ---------------------------------------------------------------------
is_service_running() {
    systemctl is-active --quiet "$1" 2>/dev/null || pgrep -f "$1" >/dev/null 2>&1
}

compress_backup() {
    tar -czf "$2.tar.gz" -C "$(dirname "$1")" "$(basename "$1")" >>"$LOG_FILE" 2>&1
}

# ---------------------------------------------------------------------
# BACKUPS CONFIG
# ---------------------------------------------------------------------
backup_grafana() {
    [[ -d /etc/grafana ]] && compress_backup /etc/grafana "$CONFIG_BACKUP_DIR/grafana_config_$TIMESTAMP"
    [[ -d /var/lib/grafana ]] && compress_backup /var/lib/grafana "$CONFIG_BACKUP_DIR/grafana_data_$TIMESTAMP"
}

backup_zabbix() {
    [[ -d /etc/zabbix ]] && compress_backup /etc/zabbix "$CONFIG_BACKUP_DIR/zabbix_config_$TIMESTAMP"
    [[ -d /var/lib/zabbix ]] && compress_backup /var/lib/zabbix "$CONFIG_BACKUP_DIR/zabbix_data_$TIMESTAMP"
}

backup_glpi() {
    [[ -d /var/www/glpi ]] && compress_backup /var/www/glpi "$CONFIG_BACKUP_DIR/glpi_$TIMESTAMP"
}

backup_airflow_files() {
    [[ -d "$AIRFLOW_HOME" ]] && compress_backup "$AIRFLOW_HOME" "$CONFIG_BACKUP_DIR/airflow_files_$TIMESTAMP"
}

# ---------------------------------------------------------------------
# BASES DE DATOS
# ---------------------------------------------------------------------
backup_mariadb() {
    log INFO "Backup MariaDB"
    mysqldump --all-databases --single-transaction --routines --triggers \
        > "$DB_BACKUP_DIR/mariadb_$TIMESTAMP.sql" 2>>"$LOG_FILE"
    compress_backup "$DB_BACKUP_DIR/mariadb_$TIMESTAMP.sql" "$DB_BACKUP_DIR/mariadb_$TIMESTAMP"
    rm -f "$DB_BACKUP_DIR/mariadb_$TIMESTAMP.sql"
}

backup_airflow_postgres() {
    log INFO "Backup PostgreSQL Airflow"
    export PGPASSWORD="${AIRFLOW_PG_PASSWORD:-}"
    pg_dump -h "$AIRFLOW_PG_HOST" -p "$AIRFLOW_PG_PORT" \
        -U "$AIRFLOW_PG_USER" -F c \
        -f "$DB_BACKUP_DIR/airflow_pg_$TIMESTAMP.dump" \
        "$AIRFLOW_PG_DB" >>"$LOG_FILE" 2>&1
    unset PGPASSWORD
}

backup_opensearch() {
    log INFO "Snapshot OpenSearch"
    curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_snapshot/backup_repo" \
        -H 'Content-Type: application/json' \
        -d "{\"type\":\"fs\",\"settings\":{\"location\":\"$OPENSEARCH_SNAPSHOT_PATH\"}}" \
        >>"$LOG_FILE" 2>&1 || true

    curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_snapshot/backup_repo/backup_$TIMESTAMP" \
        -H 'Content-Type: application/json' \
        -d '{"indices":"*"}' >>"$LOG_FILE" 2>&1
}

# ---------------------------------------------------------------------
# LIMPIEZA
# ---------------------------------------------------------------------
cleanup() {
    find "$BACKUP_BASE_DIR" -type f -mtime +"$RETENTION_DAYS" -delete
}

# ---------------------------------------------------------------------
# MAIN
# ---------------------------------------------------------------------
log INFO "Inicio de backup"

is_service_running grafana-server && backup_grafana
is_service_running zabbix-server && backup_zabbix
[[ -d /var/www/glpi ]] && backup_glpi
is_service_running airflow-webserver && backup_airflow_files && backup_airflow_postgres
is_service_running opensearch && backup_opensearch
is_service_running mariadb && backup_mariadb

cleanup

log INFO "Backup finalizado correctamente"
