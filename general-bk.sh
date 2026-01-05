#!/bin/bash

################################################################################
# SCRIPT DE BACKUP INTEGRAL PARA INFRAESTRUCTURA DE MONITOREO
# ============================================================================
# Propósito: Realizar backup automatizado de aplicaciones y bases de datos
# Versión: 2.0
# Autor: Imagunet S.A.S. - Sistemas de Monitoreo
# Descripción: Detecta aplicaciones corriendo (Zabbix, GLPI, Grafana, MariaDB,
#              OpenSearch, Jaeger, Airflow) y realiza backups inteligentes
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURACIÓN GLOBAL
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/backups}"
LOG_DIR="${BACKUP_BASE_DIR}/logs"
CONFIG_BACKUP_DIR="${BACKUP_BASE_DIR}/configs"
DB_BACKUP_DIR="${BACKUP_BASE_DIR}/databases"
APP_BACKUP_DIR="${BACKUP_BASE_DIR}/applications"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/backup_${TIMESTAMP}.log"
RETENTION_DAYS="${RETENTION_DAYS:-21}"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# INICIALIZACIÓN
# ============================================================================

init_directories() {
    mkdir -p "${BACKUP_BASE_DIR}" "${LOG_DIR}" "${CONFIG_BACKUP_DIR}" \
             "${DB_BACKUP_DIR}" "${APP_BACKUP_DIR}"
    touch "${LOG_FILE}"
}

# ============================================================================
# FUNCIONES DE LOGGING Y UTILIDAD
# ============================================================================

log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${BLUE}[${timestamp}] [INFO]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
        SUCCESS)
            echo -e "${GREEN}[${timestamp}] [SUCCESS]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
        WARN)
            echo -e "${YELLOW}[${timestamp}] [WARN]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
        ERROR)
            echo -e "${RED}[${timestamp}] [ERROR]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
    esac
}

# Verificar si un servicio está corriendo
is_service_running() {
    local service=$1
    
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        return 0
    fi
    
    # Intentar con ps como fallback
    if pgrep -f "$service" > /dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Obtener PID del servicio
get_service_pid() {
    local service=$1
    systemctl show -p MainPID --value "$service" 2>/dev/null || pgrep -f "$service" | head -1
}

# Compresión eficiente
compress_backup() {
    local source=$1
    local destination=$2
    
    if [[ -d "$source" ]] || [[ -f "$source" ]]; then
        log INFO "Comprimiendo: $source -> $destination.tar.gz"
        tar --exclude='*.log' --exclude='temp' -czf "${destination}.tar.gz" -C "$(dirname "$source")" "$(basename "$source")" 2>/dev/null
        
        if [[ -f "${destination}.tar.gz" ]]; then
            local size=$(du -h "${destination}.tar.gz" | cut -f1)
            log SUCCESS "Compresión completada: $size"
            return 0
        fi
    fi
    return 1
}

# ============================================================================
# LIMPIEZA DE BACKUPS ANTIGUOS
# ============================================================================

cleanup_old_backups() {
    log INFO "Limpiando backups más antiguos de ${RETENTION_DAYS} días"
    
    find "${BACKUP_BASE_DIR}" -type f -name "*.tar.gz" -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true
    find "${BACKUP_BASE_DIR}" -type f -name "*.sql" -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true
    find "${BACKUP_BASE_DIR}" -type d -empty -delete 2>/dev/null || true
    
    log SUCCESS "Limpieza completada"
}

# ============================================================================
# DETECCIÓN DE APLICACIONES
# ============================================================================

detect_zabbix() {
    log INFO "Detectando Zabbix..."
    
    if is_service_running "zabbix-server" || is_service_running "zabbix-agent"; then
        log SUCCESS "Zabbix detectado"
        return 0
    fi
    
    if pgrep -f "/opt/zabbix" > /dev/null 2>&1; then
        log SUCCESS "Zabbix detectado (proceso encontrado)"
        return 0
    fi
    
    return 1
}

detect_glpi() {
    log INFO "Detectando GLPI..."
    
    if [[ -d "/var/www/glpi" ]] || [[ -d "/usr/share/glpi" ]] || [[ -d "/opt/glpi" ]]; then
        log SUCCESS "GLPI detectado"
        return 0
    fi
    
    return 1
}

detect_grafana() {
    log INFO "Detectando Grafana..."
    
    if is_service_running "grafana-server"; then
        log SUCCESS "Grafana detectado"
        return 0
    fi
    
    if pgrep -f "grafana" > /dev/null 2>&1; then
        log SUCCESS "Grafana detectado (proceso encontrado)"
        return 0
    fi
    
    return 1
}

detect_mariadb() {
    log INFO "Detectando MariaDB..."
    
    if is_service_running "mariadb" || is_service_running "mysql"; then
        log SUCCESS "MariaDB detectado"
        return 0
    fi
    
    if pgrep -f "mysqld" > /dev/null 2>&1; then
        log SUCCESS "MariaDB detectado (proceso encontrado)"
        return 0
    fi
    
    return 1
}

detect_opensearch() {
    log INFO "Detectando OpenSearch..."
    
    if is_service_running "opensearch"; then
        log SUCCESS "OpenSearch detectado"
        return 0
    fi
    
    if pgrep -f "opensearch" > /dev/null 2>&1; then
        log SUCCESS "OpenSearch detectado (proceso encontrado)"
        return 0
    fi
    
    return 1
}

detect_jaeger() {
    log INFO "Detectando Jaeger..."
    
    if is_service_running "jaeger"; then
        log SUCCESS "Jaeger detectado"
        return 0
    fi
    
    if pgrep -f "jaeger" > /dev/null 2>&1; then
        log SUCCESS "Jaeger detectado (proceso encontrado)"
        return 0
    fi
    
    return 1
}

detect_airflow() {
    log INFO "Detectando Apache Airflow..."
    
    if is_service_running "airflow" || is_service_running "airflow-scheduler" || is_service_running "airflow-webserver"; then
        log SUCCESS "Apache Airflow detectado"
        return 0
    fi
    
    if pgrep -f "airflow" > /dev/null 2>&1; then
        log SUCCESS "Apache Airflow detectado (proceso encontrado)"
        return 0
    fi
    
    return 1
}

# ============================================================================
# BACKUPS DE CONFIGURACIÓN
# ============================================================================

backup_zabbix_config() {
    log INFO "Realizando backup de configuración de Zabbix..."
    
    local zabbix_config_dirs=(
        "/etc/zabbix"
        "/opt/zabbix/etc"
        "/usr/local/etc/zabbix"
    )
    
    for dir in "${zabbix_config_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log INFO "Encontrado directorio de configuración: $dir"
            compress_backup "$dir" "${CONFIG_BACKUP_DIR}/zabbix_config_${TIMESTAMP}"
            break
        fi
    done
    
    # Backup de /var/lib/zabbix si existe
    if [[ -d "/var/lib/zabbix" ]]; then
        log INFO "Realizando backup de /var/lib/zabbix..."
        compress_backup "/var/lib/zabbix" "${CONFIG_BACKUP_DIR}/zabbix_lib_${TIMESTAMP}" || true
    fi
}

backup_glpi_config() {
    log INFO "Realizando backup de configuración de GLPI..."
    
    local glpi_dirs=(
        "/var/www/glpi"
        "/usr/share/glpi"
        "/opt/glpi"
    )
    
    for dir in "${glpi_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log INFO "Encontrado directorio de GLPI: $dir"
            compress_backup "$dir" "${CONFIG_BACKUP_DIR}/glpi_full_${TIMESTAMP}"
            break
        fi
    done
    
    # Backup de /var/lib/glpi si existe
    if [[ -d "/var/lib/glpi" ]]; then
        log INFO "Realizando backup de /var/lib/glpi..."
        compress_backup "/var/lib/glpi" "${CONFIG_BACKUP_DIR}/glpi_lib_${TIMESTAMP}" || true
    fi
}

backup_grafana_config() {
    log INFO "Realizando backup de configuración de Grafana..."
    
    local grafana_config_dirs=(
        "/etc/grafana"
        "/opt/grafana/etc"
        "/var/lib/grafana"
    )
    
    for dir in "${grafana_config_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log INFO "Encontrado directorio de configuración: $dir"
            compress_backup "$dir" "${CONFIG_BACKUP_DIR}/grafana_config_${TIMESTAMP}"
        fi
    done
    
    # Asegurar que /var/lib/grafana se respalda si no se capturo arriba
    if [[ -d "/var/lib/grafana" ]]; then
        log INFO "Asegurando backup de /var/lib/grafana..."
        compress_backup "/var/lib/grafana" "${CONFIG_BACKUP_DIR}/grafana_lib_${TIMESTAMP}" || true
    fi
}

backup_opensearch_config() {
    log INFO "Realizando backup de configuración de OpenSearch..."
    
    local opensearch_config_dirs=(
        "/etc/opensearch"
        "/opt/opensearch/config"
    )
    
    for dir in "${opensearch_config_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log INFO "Encontrado directorio de configuración: $dir"
            compress_backup "$dir" "${CONFIG_BACKUP_DIR}/opensearch_config_${TIMESTAMP}"
            break
        fi
    done
    
    # Backup de /var/lib/opensearch si existe
    if [[ -d "/var/lib/opensearch" ]]; then
        log INFO "Realizando backup de /var/lib/opensearch..."
        compress_backup "/var/lib/opensearch" "${CONFIG_BACKUP_DIR}/opensearch_lib_${TIMESTAMP}" || true
    fi
}

backup_jaeger_config() {
    log INFO "Realizando backup de configuración de Jaeger..."
    
    local jaeger_config_dirs=(
        "/etc/jaeger"
        "/opt/jaeger/etc"
    )
    
    for dir in "${jaeger_config_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log INFO "Encontrado directorio de configuración: $dir"
            compress_backup "$dir" "${CONFIG_BACKUP_DIR}/jaeger_config_${TIMESTAMP}"
            break
        fi
    done
    
    # Backup de /var/lib/jaeger si existe
    if [[ -d "/var/lib/jaeger" ]]; then
        log INFO "Realizando backup de /var/lib/jaeger..."
        compress_backup "/var/lib/jaeger" "${CONFIG_BACKUP_DIR}/jaeger_lib_${TIMESTAMP}" || true
    fi
}

backup_airflow_config() {
    log INFO "Realizando backup de configuración de Airflow..."
    
    local airflow_config_dirs=(
        "${AIRFLOW_HOME:-$HOME/airflow}"
        "/opt/airflow"
    )
    
    for dir in "${airflow_config_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log INFO "Encontrado directorio de Airflow: $dir"
            compress_backup "$dir" "${CONFIG_BACKUP_DIR}/airflow_config_${TIMESTAMP}"
            break
        fi
    done
}

# ============================================================================
# BACKUPS DE BASE DE DATOS
# ============================================================================

backup_mariadb() {
    log INFO "Realizando backup de MariaDB..."
    
    # Detectar credenciales
    local mysql_user="${MYSQL_USER:-root}"
    local mysql_password="${MYSQL_PASSWORD:-}"
    local mysql_host="${MYSQL_HOST:-localhost}"
    
    # Intentar usar .my.cnf si existe
    if [[ -f "$HOME/.my.cnf" ]]; then
        log INFO "Usando credenciales de .my.cnf"
        if mysqldump --all-databases --single-transaction --quick --lock-tables=false --triggers \
            > "${DB_BACKUP_DIR}/mariadb_full_${TIMESTAMP}.sql" 2>/dev/null; then
            
            compress_backup "${DB_BACKUP_DIR}/mariadb_full_${TIMESTAMP}.sql" \
                            "${DB_BACKUP_DIR}/mariadb_full_${TIMESTAMP}"
            rm -f "${DB_BACKUP_DIR}/mariadb_full_${TIMESTAMP}.sql"
            log SUCCESS "Backup de MariaDB completado"
            
            # Backup de archivos de configuracion de MariaDB
            if [[ -d "/etc/mysql" ]]; then
                log INFO "Realizando backup de configuracion de MariaDB..."
                compress_backup "/etc/mysql" "${CONFIG_BACKUP_DIR}/mariadb_config_${TIMESTAMP}" || true
            fi
            
            return 0
        fi
    fi
    
    # Intentar conexión con credenciales
    if [[ -n "$mysql_password" ]]; then
        if mysqldump -u "$mysql_user" -p"$mysql_password" -h "$mysql_host" \
            --all-databases --single-transaction --quick --lock-tables=false --triggers \
            > "${DB_BACKUP_DIR}/mariadb_full_${TIMESTAMP}.sql" 2>/dev/null; then
            
            compress_backup "${DB_BACKUP_DIR}/mariadb_full_${TIMESTAMP}.sql" \
                            "${DB_BACKUP_DIR}/mariadb_full_${TIMESTAMP}"
            rm -f "${DB_BACKUP_DIR}/mariadb_full_${TIMESTAMP}.sql"
            log SUCCESS "Backup de MariaDB completado"
            
            # Backup de archivos de configuracion
            if [[ -d "/etc/mysql" ]]; then
                log INFO "Realizando backup de configuracion de MariaDB..."
                compress_backup "/etc/mysql" "${CONFIG_BACKUP_DIR}/mariadb_config_${TIMESTAMP}" || true
            fi
            
            return 0
        fi
    fi
    
    # Intentar sin contraseña (socket unix)
    if mysqldump --single-transaction --quick --lock-tables=false --triggers \
        --all-databases > "${DB_BACKUP_DIR}/mariadb_full_${TIMESTAMP}.sql" 2>/dev/null; then
        
        compress_backup "${DB_BACKUP_DIR}/mariadb_full_${TIMESTAMP}.sql" \
                        "${DB_BACKUP_DIR}/mariadb_full_${TIMESTAMP}"
        rm -f "${DB_BACKUP_DIR}/mariadb_full_${TIMESTAMP}.sql"
        log SUCCESS "Backup de MariaDB completado"
        
        # Backup de archivos de configuracion
        if [[ -d "/etc/mysql" ]]; then
            log INFO "Realizando backup de configuracion de MariaDB..."
            compress_backup "/etc/mysql" "${CONFIG_BACKUP_DIR}/mariadb_config_${TIMESTAMP}" || true
        fi
        
        return 0
    fi
    
    log WARN "No se pudo conectar a MariaDB. Verifica credenciales"
    return 1
}

backup_opensearch_data() {
    log INFO "Realizando backup de datos de OpenSearch..."
    
    local opensearch_host="${OPENSEARCH_HOST:-localhost}"
    local opensearch_port="${OPENSEARCH_PORT:-9200}"
    
    # Crear snapshot del cluster
    local snapshot_name="backup_${TIMESTAMP}"
    
    # Primero, registrar repositorio si no existe
    curl -s -X PUT "http://${opensearch_host}:${opensearch_port}/_snapshot/backup_repo" \
        -H 'Content-Type: application/json' \
        -d "{
            \"type\": \"fs\",
            \"settings\": {
                \"location\": \"${DB_BACKUP_DIR}/opensearch_snapshots\"
            }
        }" > /dev/null 2>&1 || true
    
    # Crear snapshot
    if curl -s -X PUT "http://${opensearch_host}:${opensearch_port}/_snapshot/backup_repo/${snapshot_name}" \
        -H 'Content-Type: application/json' \
        -d '{"indices": "*"}' > /dev/null 2>&1; then
        
        log SUCCESS "Snapshot de OpenSearch creado: $snapshot_name"
        return 0
    fi
    
    log WARN "No se pudo crear snapshot de OpenSearch"
    return 1
}

backup_jaeger_data() {
    log INFO "Realizando backup de datos de Jaeger..."
    
    # Jaeger típicamente usa Elasticsearch/OpenSearch como backend
    # Si no está disponible, intentar hacer dump del home directory
    local jaeger_data_dir="${JAEGER_HOME:-/opt/jaeger}/data"
    
    if [[ -d "$jaeger_data_dir" ]]; then
        compress_backup "$jaeger_data_dir" "${DB_BACKUP_DIR}/jaeger_data_${TIMESTAMP}"
        log SUCCESS "Backup de datos de Jaeger completado"
        return 0
    fi
    
    log WARN "Directorio de datos de Jaeger no encontrado"
    return 1
}

# ============================================================================
# LIMPIEZA Y FINALIZACIÓN
# ============================================================================

# ============================================================================
# ORQUESTACIÓN PRINCIPAL
# ============================================================================

main() {
    log INFO "============================================"
    log INFO "Iniciando Backup de Infraestructura"
    log INFO "============================================"
    log INFO "Timestamp: ${TIMESTAMP}"
    log INFO "Usuario: $(whoami)"
    log INFO "Host: $(hostname)"
    
    init_directories
    
    # Arreglo para rastrear aplicaciones detectadas
    declare -a detected_apps=()
    
    # Detección
    log INFO "--- FASE 1: DETECCIÓN DE APLICACIONES ---"
    
    if detect_zabbix; then
        detected_apps+=("Zabbix")
    fi
    
    if detect_glpi; then
        detected_apps+=("GLPI")
    fi
    
    if detect_grafana; then
        detected_apps+=("Grafana")
    fi
    
    if detect_mariadb; then
        detected_apps+=("MariaDB")
    fi
    
    if detect_opensearch; then
        detected_apps+=("OpenSearch")
    fi
    
    if detect_jaeger; then
        detected_apps+=("Jaeger")
    fi
    
    if detect_airflow; then
        detected_apps+=("Airflow")
    fi
    
    if [[ ${#detected_apps[@]} -eq 0 ]]; then
        log WARN "No se detectaron aplicaciones monitorizadas"
    else
        log SUCCESS "Aplicaciones detectadas: ${detected_apps[*]}"
    fi
    
    # Backups de configuración
    log INFO "--- FASE 2: BACKUP DE CONFIGURACIONES ---"
    
    for app in "${detected_apps[@]}"; do
        case $app in
            Zabbix)
                backup_zabbix_config || true
                ;;
            GLPI)
                backup_glpi_config || true
                ;;
            Grafana)
                backup_grafana_config || true
                ;;
            OpenSearch)
                backup_opensearch_config || true
                ;;
            Jaeger)
                backup_jaeger_config || true
                ;;
            Airflow)
                backup_airflow_config || true
                ;;
        esac
    done
    
    # Backups de bases de datos
    log INFO "--- FASE 3: BACKUP DE BASES DE DATOS ---"
    
    if [[ " ${detected_apps[*]} " =~ " MariaDB " ]]; then
        backup_mariadb || true
    fi
    
    if [[ " ${detected_apps[*]} " =~ " OpenSearch " ]]; then
        backup_opensearch_data || true
    fi
    
    if [[ " ${detected_apps[*]} " =~ " Jaeger " ]]; then
        backup_jaeger_data || true
    fi
    
    # Limpieza
    log INFO "--- FASE 4: MANTENIMIENTO ---"
    cleanup_old_backups
    
    log INFO "============================================"
    log SUCCESS "Proceso de Backup Completado"
    log INFO "============================================"
}

# ============================================================================
# EJECUCIÓN
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi