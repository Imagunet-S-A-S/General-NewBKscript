#!/bin/bash
set -euo pipefail

################################################################################
# BACKUP INFRAESTRUCTURA DE MONITOREO - FINAL DEFINITIVO
################################################################################

RETENTION_DAYS=21
HOT_DAYS=7

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
WEEK_END_DATE="$(date -d 'last sunday' +%Y%m%d)"

log() {
    echo "[$(date '+%F %T')] [$1] $2" | tee -a "$LOG_FILE"
}

is_service_running() {
    systemctl is-active --quiet "$1" 2>/dev/null || pgrep -f "$1" >/dev/null 2>&1
}

compress_dir() {
    tar -czf "${2}.tar.gz" -C "$(dirname "$1")" "$(basename "$1")" >>"$LOG_FILE" 2>&1
}

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

rotate_app() {
    find "$1" -maxdepth 1 -type d -name "20*" -mtime +"$RETENTION_DAYS" -exec rm -rf {} \;
}

# ============================ ZABBIX ==========================================
backup_zabbix() {
    prepare_app_dirs /var/lib/zabbix
    [[ -d /etc/zabbix ]] && compress_dir /etc/zabbix "$NEWEST_DIR/configs/zabbix_cfg_$TIMESTAMP"
    [[ -d /var/lib/zabbix ]] && compress_dir /var/lib/zabbix "$NEWEST_DIR/applications/zabbix_data_$TIMESTAMP"
    rotate_app /var/lib/zabbix
}

# ============================ GRAFANA =========================================
backup_grafana() {
    prepare_app_dirs /var/lib/grafana
    [[ -d /etc/grafana ]] && compress_dir /etc/grafana "$NEWEST_DIR/configs/grafana_cfg_$TIMESTAMP"
    [[ -d /var/lib/grafana ]] && compress_dir /var/lib/grafana "$NEWEST_DIR/applications/grafana_data_$TIMESTAMP"
    rotate_app /var/lib/grafana
}

# ============================ GLPI ============================================
backup_glpi() {
    prepare_app_dirs /var/lib/glpi
    [[ -d /var/www/glpi ]] && compress_dir /var/www/glpi "$NEWEST_DIR/applications/glpi_$TIMESTAMP"
    rotate_app /var/lib/glpi
}

# ============================ MARIADB =========================================
backup_mariadb() {
    prepare_app_dirs /var/lib/mariadb

    local cfg=()
    [[ -f /etc/my.cnf ]] && cfg+=("/etc/my.cnf")
    [[ -d /etc/my.cnf.d ]] && cfg+=("/etc/my.cnf.d")

    [[ ${#cfg[@]} -gt 0 ]] && tar -czf "$NEWEST_DIR/configs/mariadb_cfg_$TIMESTAMP.tar.gz" "${cfg[@]}" >>"$LOG_FILE" 2>&1

    local dbs
    dbs=$(mysql -N -e "SHOW DATABASES;" 2>>"$LOG_FILE" | grep -Ev "^(mysql|sys|information_schema|performance_schema)$")

    for db in $dbs; do
        mysqldump --single-transaction --routines --triggers "$db" > "$NEWEST_DIR/databases/${db}_$TIMESTAMP.sql" 2>>"$LOG_FILE"
        tar -czf "$NEWEST_DIR/databases/${db}_$TIMESTAMP.tar.gz" -C "$NEWEST_DIR/databases" "${db}_$TIMESTAMP.sql"
        rm -f "$NEWEST_DIR/databases/${db}_$TIMESTAMP.sql"
    done

    rotate_app /var/lib/mariadb
}

# ============================ AIRFLOW =========================================
backup_airflow() {
    prepare_app_dirs /var/lib/airflow

    [[ -d "${AIRFLOW_HOME:-/opt/airflow}" ]] && \
        compress_dir "${AIRFLOW_HOME:-/opt/airflow}" "$NEWEST_DIR/applications/airflow_files_$TIMESTAMP"

    if command -v pg_dump >/dev/null && [[ -n "${AIRFLOW_PG_DB:-}" ]]; then
        PGPASSWORD="${AIRFLOW_PG_PASSWORD:-}" pg_dump \
            -h "${AIRFLOW_PG_HOST:-localhost}" \
            -U "${AIRFLOW_PG_USER:-airflow}" \
            -F c \
            "${AIRFLOW_PG_DB}" \
            > "$NEWEST_DIR/databases/airflow_pg_$TIMESTAMP.dump" 2>>"$LOG_FILE"
    fi

    rotate_app /var/lib/airflow
}

# ============================ OPENSEARCH (INCLUYE JAEGER) =====================
backup_opensearch() {
    prepare_app_dirs /var/lib/opensearch

    curl -s -X PUT "http://${OPENSEARCH_HOST:-localhost}:${OPENSEARCH_PORT:-9200}/_snapshot/backup_repo" \
        -H 'Content-Type: application/json' \
        -d "{\"type\":\"fs\",\"settings\":{\"location\":\"${OPENSEARCH_SNAPSHOT_PATH}\"}}" >>"$LOG_FILE" 2>&1 || true

    curl -s -X PUT "http://${OPENSEARCH_HOST:-localhost}:${OPENSEARCH_PORT:-9200}/_snapshot/backup_repo/backup_${TIMESTAMP}" \
        -H 'Content-Type: application/json' \
        -d '{"indices":"*"}' >>"$LOG_FILE" 2>&1

    rotate_app /var/lib/opensearch
}

# ============================ MAIN ============================================
is_service_running zabbix-server && backup_zabbix
is_service_running grafana-server && backup_grafana
[[ -d /var/www/glpi ]] && backup_glpi
is_service_running mariadb && command -v mysqldump >/dev/null && backup_mariadb
is_service_running airflow-webserver && backup_airflow
is_service_running opensearch && backup_opensearch
