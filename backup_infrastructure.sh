#!/bin/bash
set -euo pipefail

################################################################################
# BACKUP INFRAESTRUCTURA DE MONITOREO - FINAL DEFINITIVO
################################################################################

# Cargar configuración: primero junto al script (desarrollo), luego ruta de instalación
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/backup.conf" ]]; then
    source "$SCRIPT_DIR/backup.conf"
elif [[ -f "/etc/backup-imagunet/backup.conf" ]]; then
    source "/etc/backup-imagunet/backup.conf"
fi

RETENTION_DAYS="${RETENTION_DAYS:-14}"
HOT_DAYS="${HOT_DAYS:-7}"

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
    local app_base="$1"

    # Comprimir al máximo las semanas que salen del hot zone y aún no están comprimidas
    find "$app_base" -maxdepth 1 -type d -name "20*" -mtime +"$HOT_DAYS" | while read -r week_dir; do
        if [[ -f "${week_dir}.tar.gz" ]]; then
            rm -rf "$week_dir"
        else
            GZIP=-9 tar -czf "${week_dir}.tar.gz" -C "$app_base" "$(basename "$week_dir")" >>"$LOG_FILE" 2>&1 \
                && rm -rf "$week_dir"
        fi
    done

    # Eliminar archivos comprimidos y directorios fuera del periodo de retención
    find "$app_base" -maxdepth 1 -type f -name "20*.tar.gz" -mtime +"$RETENTION_DAYS" -delete
    find "$app_base" -maxdepth 1 -type d  -name "20*"       -mtime +"$RETENTION_DAYS" -exec rm -rf {} \;
}

# Verifica que la partición de $dir no supere el umbral de uso configurado.
# Si lo supera, intenta liberar espacio ejecutando rotate_app.
# Si tras la rotación el uso sigue por encima, devuelve 1 (el backup debe cancelarse).
# Requiere que LOG_FILE esté definido (llamar después de prepare_app_dirs).
check_disk_space() {
    local dir="$1"
    local label="$2"
    local threshold="${DISK_THRESHOLD_PCT:-85}"

    local usage
    usage=$(df --output=pcent "$dir" 2>/dev/null | tail -1 | tr -d ' %')

    if [[ -z "$usage" ]]; then
        log "WARN" "[$label] No se pudo leer el uso de disco en $dir — se continúa de todos modos"
        return 0
    fi

    if (( usage < threshold )); then
        return 0
    fi

    log "WARN" "[$label] Partición al ${usage}% (límite ${threshold}%) — ejecutando rotación para liberar espacio"
    rotate_app "$dir"

    usage=$(df --output=pcent "$dir" 2>/dev/null | tail -1 | tr -d ' %')
    if (( usage >= threshold )); then
        log "ERROR" "[$label] Partición aún al ${usage}% tras rotación — backup CANCELADO"
        return 1
    fi

    log "INFO" "[$label] Espacio liberado (ahora ${usage}%) — continuando backup"
}

# Respalda rutas extra definidas en una variable "SERVICIO_EXTRA_DIRS".
# Las rutas se separan con ":" (igual que $PATH).
# Uso: backup_extra_dirs "GLPI_EXTRA_DIRS" "glpi" "applications"
backup_extra_dirs() {
    local var_name="$1"   # nombre de la variable, ej: GLPI_EXTRA_DIRS
    local label="$2"      # prefijo del archivo de salida
    local category="$3"   # configs | applications

    local dirs="${!var_name:-}"
    [[ -z "$dirs" ]] && return 0

    local IFS=':'
    for dir in $dirs; do
        [[ -d "$dir" ]] && compress_dir "$dir" \
            "$NEWEST_DIR/${category}/${label}_extra_$(basename "$dir")_$TIMESTAMP"
    done
}

# ============================ ZABBIX ==========================================
backup_zabbix() {
    local zabbix_data="${ZABBIX_DATA_DIR:-/var/lib/zabbix}"
    prepare_app_dirs "$zabbix_data"
    check_disk_space "$zabbix_data" "ZABBIX" || return 0

    [[ -n "${ZABBIX_CFG_DIR:-}"  && -d "$ZABBIX_CFG_DIR"  ]] && \
        compress_dir "$ZABBIX_CFG_DIR"  "$NEWEST_DIR/configs/zabbix_cfg_$TIMESTAMP"
    [[ -n "${ZABBIX_DATA_DIR:-}" && -d "$ZABBIX_DATA_DIR" ]] && \
        compress_dir "$ZABBIX_DATA_DIR" "$NEWEST_DIR/applications/zabbix_data_$TIMESTAMP"

    # Base de datos: solo si ZABBIX_DB_TYPE está definido
    case "${ZABBIX_DB_TYPE:-}" in
        postgresql)
            if command -v pg_dump >/dev/null 2>&1; then
                log "INFO" "[ZABBIX] Dumpeando base de datos PostgreSQL ${ZABBIX_DB_NAME:-zabbix}..."
                PGPASSWORD="${ZABBIX_DB_PASSWORD:-}" pg_dump \
                    -h "${ZABBIX_DB_HOST:-localhost}" \
                    -p "${ZABBIX_DB_PORT:-5432}" \
                    -U "${ZABBIX_DB_USER:-zabbix}" \
                    -F c \
                    "${ZABBIX_DB_NAME:-zabbix}" \
                    > "$NEWEST_DIR/databases/zabbix_pg_$TIMESTAMP.dump" 2>>"$LOG_FILE"
            else
                log "WARN" "[ZABBIX] pg_dump no encontrado — se omite el backup de base de datos"
            fi
            ;;
        mariadb)
            if command -v mysqldump >/dev/null 2>&1; then
                log "INFO" "[ZABBIX] Dumpeando base de datos MariaDB ${ZABBIX_DB_NAME:-zabbix}..."
                local z_opts=(-h "${ZABBIX_DB_HOST:-localhost}" -P "${ZABBIX_DB_PORT:-3306}" -u "${ZABBIX_DB_USER:-zabbix}")
                [[ -n "${ZABBIX_DB_PASSWORD:-}" ]] && z_opts+=("-p${ZABBIX_DB_PASSWORD}")
                mysqldump "${z_opts[@]}" --single-transaction --routines --triggers "${ZABBIX_DB_NAME:-zabbix}" \
                    > "$NEWEST_DIR/databases/zabbix_$TIMESTAMP.sql" 2>>"$LOG_FILE"
                tar -czf "$NEWEST_DIR/databases/zabbix_$TIMESTAMP.tar.gz" \
                    -C "$NEWEST_DIR/databases" "zabbix_$TIMESTAMP.sql"
                rm -f "$NEWEST_DIR/databases/zabbix_$TIMESTAMP.sql"
            else
                log "WARN" "[ZABBIX] mysqldump no encontrado — se omite el backup de base de datos"
            fi
            ;;
        "")
            # No configurado: la DB se maneja por backup_mariadb si aplica
            ;;
        *)
            log "WARN" "[ZABBIX] ZABBIX_DB_TYPE='${ZABBIX_DB_TYPE}' no reconocido (use: mariadb | postgresql)"
            ;;
    esac

    backup_extra_dirs "ZABBIX_EXTRA_DIRS" "zabbix" "applications"
    rotate_app "$zabbix_data"
}

# ============================ GRAFANA =========================================
backup_grafana() {
    local grafana_data="${GRAFANA_DATA_DIR:-/var/lib/grafana}"
    prepare_app_dirs "$grafana_data"
    check_disk_space "$grafana_data" "GRAFANA" || return 0

    [[ -n "${GRAFANA_CFG_DIR:-}"  && -d "$GRAFANA_CFG_DIR"  ]] && \
        compress_dir "$GRAFANA_CFG_DIR"  "$NEWEST_DIR/configs/grafana_cfg_$TIMESTAMP"
    [[ -n "${GRAFANA_DATA_DIR:-}" && -d "$GRAFANA_DATA_DIR" ]] && \
        compress_dir "$GRAFANA_DATA_DIR" "$NEWEST_DIR/applications/grafana_data_$TIMESTAMP"

    backup_extra_dirs "GRAFANA_EXTRA_DIRS" "grafana" "applications"
    rotate_app "$grafana_data"
}

# ============================ GLPI ============================================
backup_glpi() {
    local glpi_base="${GLPI_BACKUP_BASE:-/var/backups/glpi}"
    prepare_app_dirs "$glpi_base"
    check_disk_space "$glpi_base" "GLPI" || return 0

    [[ -n "${GLPI_CFG_DIR:-}"  && -d "$GLPI_CFG_DIR"  ]] && \
        compress_dir "$GLPI_CFG_DIR"  "$NEWEST_DIR/configs/glpi_cfg_$TIMESTAMP"

    [[ -n "${GLPI_APP_DIR:-}"  && -d "$GLPI_APP_DIR"  ]] && \
        compress_dir "$GLPI_APP_DIR"  "$NEWEST_DIR/applications/glpi_app_$TIMESTAMP"

    if [[ -n "${GLPI_DATA_DIR:-}" && -d "$GLPI_DATA_DIR" ]]; then
        tar -czf "$NEWEST_DIR/applications/glpi_data_$TIMESTAMP.tar.gz" \
            --exclude="$glpi_base" \
            -C "$(dirname "$GLPI_DATA_DIR")" \
            "$(basename "$GLPI_DATA_DIR")" >>"$LOG_FILE" 2>&1
    fi

    backup_extra_dirs "GLPI_EXTRA_DIRS" "glpi" "applications"
    rotate_app "$glpi_base"
}

# ============================ MARIADB =========================================
backup_mariadb() {
    prepare_app_dirs /var/lib/mariadb
    check_disk_space /var/lib/mariadb "MARIADB" || return 0

    # Parámetros de conexión (locales o remotos según backup.conf)
    local mysql_host="${MYSQL_HOST:-localhost}"
    local mysql_port="${MYSQL_PORT:-3306}"
    local mysql_user="${MYSQL_USER:-root}"
    local mysql_pass="${MYSQL_PASSWORD:-}"

    local mysql_opts=(-h "$mysql_host" -P "$mysql_port" -u "$mysql_user")
    [[ -n "$mysql_pass" ]] && mysql_opts+=("-p${mysql_pass}")

    local cfg=()
    [[ -f /etc/my.cnf ]] && cfg+=("/etc/my.cnf")
    [[ -d /etc/my.cnf.d ]] && cfg+=("/etc/my.cnf.d")

    [[ ${#cfg[@]} -gt 0 ]] && tar -czf "$NEWEST_DIR/configs/mariadb_cfg_$TIMESTAMP.tar.gz" "${cfg[@]}" >>"$LOG_FILE" 2>&1

    # Mapeo de schema → carpeta base de la aplicación dueña
    local glpi_base="${GLPI_BACKUP_BASE:-/var/backups/glpi}"
    declare -A DB_APP_MAP=(
        ["glpi"]="$glpi_base"
        ["zabbix"]="/var/lib/zabbix"
        ["grafana"]="/var/lib/grafana"
    )

    local dbs
    # grep -Ev puede retornar exit 1 si no hay coincidencias; || true evita abortar con pipefail
    dbs=$(mysql "${mysql_opts[@]}" -N -e "SHOW DATABASES;" 2>>"$LOG_FILE" \
        | grep -Ev "^(mysql|sys|information_schema|performance_schema)$" || true)

    if [[ -z "$dbs" ]]; then
        log "WARN" "No se encontraron bases de datos de usuario para respaldar"
        return 0
    fi

    # Schemas que tienen su propio backup configurado en otra función.
    # Si ZABBIX_DB_TYPE está definido, backup_zabbix() ya lo maneja — evitar duplicado.
    declare -A skip_dbs=()
    [[ -n "${ZABBIX_DB_TYPE:-}" ]] && \
        skip_dbs["${ZABBIX_DB_NAME:-zabbix}"]="backup_zabbix (${ZABBIX_DB_TYPE})"

    for db in $dbs; do
        if [[ -n "${skip_dbs[$db]:-}" ]]; then
            log "INFO" "[MARIADB] Saltando '$db' — gestionado por ${skip_dbs[$db]}"
            continue
        fi

        local target_dir
        if [[ -n "${DB_APP_MAP[$db]:-}" ]]; then
            target_dir="${DB_APP_MAP[$db]}/newest/databases"
            mkdir -p "$target_dir"
        else
            target_dir="$NEWEST_DIR/databases"
        fi
        mysqldump "${mysql_opts[@]}" --single-transaction --routines --triggers "$db" \
            > "$target_dir/${db}_$TIMESTAMP.sql" 2>>"$LOG_FILE"
        tar -czf "$target_dir/${db}_$TIMESTAMP.tar.gz" -C "$target_dir" "${db}_$TIMESTAMP.sql"
        rm -f "$target_dir/${db}_$TIMESTAMP.sql"
    done

    rotate_app /var/lib/mariadb
}

# ============================ AIRFLOW =========================================
backup_airflow() {
    prepare_app_dirs /var/lib/airflow
    check_disk_space /var/lib/airflow "AIRFLOW" || return 0

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
    check_disk_space /var/lib/opensearch "OPENSEARCH" || return 0

    curl -s -X PUT "http://${OPENSEARCH_HOST:-localhost}:${OPENSEARCH_PORT:-9200}/_snapshot/backup_repo" \
        -H 'Content-Type: application/json' \
        -d "{\"type\":\"fs\",\"settings\":{\"location\":\"${OPENSEARCH_SNAPSHOT_PATH}\"}}" >>"$LOG_FILE" 2>&1 || true

    curl -s -X PUT "http://${OPENSEARCH_HOST:-localhost}:${OPENSEARCH_PORT:-9200}/_snapshot/backup_repo/backup_${TIMESTAMP}" \
        -H 'Content-Type: application/json' \
        -d '{"indices":"*"}' >>"$LOG_FILE" 2>&1

    rotate_app /var/lib/opensearch
}

# ============================ MAIN ============================================
[[ "${BACKUP_ENABLE_ZABBIX:-true}"     == "true" ]] && is_service_running zabbix-server     && backup_zabbix
[[ "${BACKUP_ENABLE_GRAFANA:-true}"    == "true" ]] && is_service_running grafana-server    && backup_grafana
[[ "${BACKUP_ENABLE_GLPI:-true}"       == "true" ]] && \
    { [[ -d "${GLPI_APP_DIR:-}" ]] || [[ -d "${GLPI_DATA_DIR:-}" ]] || [[ -d "${GLPI_CFG_DIR:-}" ]]; } && backup_glpi
[[ "${BACKUP_ENABLE_MARIADB:-true}"    == "true" ]] && is_service_running mariadb           && command -v mysqldump >/dev/null && backup_mariadb
[[ "${BACKUP_ENABLE_AIRFLOW:-true}"    == "true" ]] && is_service_running airflow-webserver && backup_airflow
[[ "${BACKUP_ENABLE_OPENSEARCH:-true}" == "true" ]] && is_service_running opensearch        && backup_opensearch
