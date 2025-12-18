#!/bin/bash

################################################################################
# SCRIPT DE INSTALACIÓN DEL SISTEMA DE BACKUP
# ============================================================================
# Propósito: Instalar y configurar automáticamente el sistema de backup
# Versión: 1.0
# Uso: sudo bash install.sh
################################################################################

set -euo pipefail

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

INSTALL_DIR="${INSTALL_DIR:-/opt/backup-scripts}"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
SCRIPT_USER="${SCRIPT_USER:-root}"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# FUNCIONES DE UTILIDAD
# ============================================================================

log() {
    local level=$1
    shift
    local message="$@"
    
    case $level in
        INFO)
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log ERROR "Este script debe ejecutarse como root o con sudo"
        exit 1
    fi
}

check_requirements() {
    log INFO "Verificando requisitos del sistema..."
    
    local missing_deps=()
    
    # Verificar bash
    local bash_version=$(bash --version | head -1 | awk '{print $4}' | cut -d. -f1)
    if [[ $bash_version -lt 4 ]]; then
        missing_deps+=("bash (versión >= 4)")
    fi
    
    # Verificar comandos
    local required_cmds=("tar" "systemctl")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log ERROR "Dependencias faltantes: ${missing_deps[*]}"
        log INFO "Instalando dependencias..."
        
        if command -v apt-get &> /dev/null; then
            apt-get update
            apt-get install -y bash-completion tar curl
        elif command -v yum &> /dev/null; then
            yum install -y bash-completion tar curl
        fi
    fi
    
    log SUCCESS "Requisitos verificados"
}

create_directories() {
    log INFO "Creando estructura de directorios..."
    
    mkdir -p "${INSTALL_DIR}"
    mkdir -p "${BACKUP_DIR}"/{logs,configs,databases,applications}
    
    chmod 755 "${BACKUP_DIR}"
    chmod 755 "${BACKUP_DIR}"/{logs,configs,databases,applications}
    
    log SUCCESS "Directorios creados: ${INSTALL_DIR} y ${BACKUP_DIR}"
}

copy_scripts() {
    log INFO "Copiando scripts de backup..."
    
    if [[ -f "backup_infrastructure.sh" ]]; then
        cp backup_infrastructure.sh "${INSTALL_DIR}/"
        chmod 755 "${INSTALL_DIR}/backup_infrastructure.sh"
        log SUCCESS "backup_infrastructure.sh copiado"
    else
        log WARN "backup_infrastructure.sh no encontrado"
    fi
    
    if [[ -f "restore_infrastructure.sh" ]]; then
        cp restore_infrastructure.sh "${INSTALL_DIR}/"
        chmod 755 "${INSTALL_DIR}/restore_infrastructure.sh"
        log SUCCESS "restore_infrastructure.sh copiado"
    else
        log WARN "restore_infrastructure.sh no encontrado"
    fi
    
    if [[ -f "test_backup_system.sh" ]]; then
        cp test_backup_system.sh "${INSTALL_DIR}/"
        chmod 755 "${INSTALL_DIR}/test_backup_system.sh"
        log SUCCESS "test_backup_system.sh copiado"
    else
        log WARN "test_backup_system.sh no encontrado"
    fi
}

copy_config() {
    log INFO "Copiando archivo de configuración..."
    
    if [[ -f "backup.conf" ]]; then
        cp backup.conf "${INSTALL_DIR}/"
        chmod 600 "${INSTALL_DIR}/backup.conf"
        log SUCCESS "backup.conf copiado con permisos 600"
    else
        log WARN "backup.conf no encontrado"
    fi
}

configure_cron() {
    log INFO "¿Deseas configurar ejecución automática con cron?"
    read -p "Elige opción (s/n): " -r response
    
    if [[ "$response" =~ ^[Ss]$ ]]; then
        echo ""
        echo "Selecciona la frecuencia:"
        echo "1) Diariamente a las 2:00 AM (recomendado)"
        echo "2) Cada 12 horas"
        echo "3) Cada 6 horas"
        echo "0) Saltar configuración de cron"
        
        read -p "Tu selección: " -r cron_choice
        
        local cron_schedule
        case $cron_choice in
            1)
                cron_schedule="0 2 * * *"
                log INFO "Configurando: Diariamente a las 2:00 AM"
                ;;
            2)
                cron_schedule="0 */12 * * *"
                log INFO "Configurando: Cada 12 horas"
                ;;
            3)
                cron_schedule="0 */6 * * *"
                log INFO "Configurando: Cada 6 horas"
                ;;
            0)
                log INFO "Omitiendo configuración de cron"
                return
                ;;
            *)
                log ERROR "Opción inválida"
                return
                ;;
        esac
        
        # Crear entrada de cron
        local cron_entry="${cron_schedule} source ${INSTALL_DIR}/backup.conf && ${INSTALL_DIR}/backup_infrastructure.sh >> ${BACKUP_DIR}/logs/cron.log 2>&1"
        
        # Agregar a crontab
        (crontab -l 2>/dev/null || echo "") | grep -v "backup_infrastructure" | crontab - 2>/dev/null || true
        (crontab -l 2>/dev/null || echo ""; echo "$cron_entry") | crontab - 2>/dev/null
        
        log SUCCESS "Cron configurado: $cron_schedule"
    fi
}

configure_mysql() {
    log INFO "¿Deseas configurar credenciales de MariaDB/MySQL?"
    read -p "Elige opción (s/n): " -r response
    
    if [[ "$response" =~ ^[Ss]$ ]]; then
        echo ""
        echo "Opciones disponibles:"
        echo "1) Crear archivo ~/.my.cnf (recomendado)"
        echo "2) Usar variables de entorno en backup.conf"
        echo "3) Saltar configuración"
        
        read -p "Tu selección: " -r mysql_choice
        
        case $mysql_choice in
            1)
                setup_mysql_config_file
                ;;
            2)
                setup_mysql_env_vars
                ;;
            3)
                log INFO "Omitiendo configuración MySQL"
                ;;
            *)
                log ERROR "Opción inválida"
                ;;
        esac
    fi
}

setup_mysql_config_file() {
    log INFO "Creando archivo ~/.my.cnf"
    
    read -p "Usuario MySQL (default: root): " -r mysql_user
    mysql_user="${mysql_user:-root}"
    
    read -sp "Contraseña MySQL: " -r mysql_pass
    echo ""
    
    cat > ~/.my.cnf << EOF
[mysqldump]
user=${mysql_user}
password=${mysql_pass}
host=localhost
port=3306

[mysql]
user=${mysql_user}
password=${mysql_pass}
host=localhost
port=3306
EOF
    
    chmod 600 ~/.my.cnf
    
    # Probar conexión
    if mysqldump --all-databases --no-data > /dev/null 2>&1; then
        log SUCCESS "Conexión a MariaDB exitosa"
    else
        log ERROR "No se pudo conectar a MariaDB. Verifica las credenciales"
    fi
}

setup_mysql_env_vars() {
    log INFO "Configurando variables de entorno MySQL"
    
    read -p "Usuario MySQL (default: root): " -r mysql_user
    mysql_user="${mysql_user:-root}"
    
    read -sp "Contraseña MySQL: " -r mysql_pass
    echo ""
    
    # Actualizar backup.conf
    sed -i "s/export MYSQL_USER=\".*\"/export MYSQL_USER=\"${mysql_user}\"/g" "${INSTALL_DIR}/backup.conf" 2>/dev/null || true
    sed -i "s/export MYSQL_PASSWORD=\".*\"/export MYSQL_PASSWORD=\"${mysql_pass}\"/g" "${INSTALL_DIR}/backup.conf" 2>/dev/null || true
    
    log SUCCESS "Variables MySQL actualizadas en backup.conf"
}

create_test_backup() {
    log INFO "¿Deseas crear un backup de prueba ahora?"
    read -p "Elige opción (s/n): " -r response
    
    if [[ "$response" =~ ^[Ss]$ ]]; then
        log INFO "Ejecutando backup de prueba..."
        
        if bash -c "source ${INSTALL_DIR}/backup.conf && ${INSTALL_DIR}/backup_infrastructure.sh"; then
            log SUCCESS "Backup de prueba completado"
            
            # Mostrar resultados
            echo ""
            log INFO "Contenido del directorio de backups:"
            du -sh "${BACKUP_DIR}"/*
        else
            log ERROR "Backup de prueba falló. Revisa los logs"
        fi
    fi
}

run_tests() {
    log INFO "¿Deseas ejecutar tests del sistema ahora?"
    read -p "Elige opción (s/n): " -r response
    
    if [[ "$response" =~ ^[Ss]$ ]]; then
        if [[ -f "${INSTALL_DIR}/test_backup_system.sh" ]]; then
            bash "${INSTALL_DIR}/test_backup_system.sh"
        else
            log WARN "Script de testing no encontrado"
        fi
    fi
}

setup_systemd() {
    log INFO "¿Deseas crear un servicio systemd para backups programados?"
    read -p "Elige opción (s/n): " -r response
    
    if [[ "$response" =~ ^[Ss]$ ]]; then
        log INFO "Creando unidades systemd..."
        
        # Crear servicio
        cat > /etc/systemd/system/backup-infrastructure.service << EOF
[Unit]
Description=Backup Infrastructure Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=${INSTALL_DIR}/backup.conf
ExecStart=${INSTALL_DIR}/backup_infrastructure.sh
StandardOutput=journal
StandardError=journal
User=root

[Install]
WantedBy=multi-user.target
EOF
        
        # Crear timer
        cat > /etc/systemd/system/backup-infrastructure.timer << EOF
[Unit]
Description=Backup Infrastructure Timer
Requires=backup-infrastructure.service

[Timer]
OnBootSec=10min
OnUnitActiveSec=12h
Persistent=true

[Install]
WantedBy=timers.target
EOF
        
        systemctl daemon-reload
        systemctl enable backup-infrastructure.timer
        
        log SUCCESS "Unidades systemd creadas y habilitadas"
        log INFO "Para iniciar: sudo systemctl start backup-infrastructure.timer"
        log INFO "Para ver estado: sudo systemctl status backup-infrastructure.timer"
    fi
}

create_symlinks() {
    log INFO "Creando enlaces de acceso rápido..."
    
    # Enlaces en /usr/local/bin para acceso fácil
    ln -sf "${INSTALL_DIR}/backup_infrastructure.sh" /usr/local/bin/backup-now
    ln -sf "${INSTALL_DIR}/restore_infrastructure.sh" /usr/local/bin/restore-backup
    ln -sf "${INSTALL_DIR}/test_backup_system.sh" /usr/local/bin/test-backup
    
    log SUCCESS "Enlaces simbólicos creados:"
    log INFO "  - backup-now     : Ejecutar backup inmediatamente"
    log INFO "  - restore-backup : Restaurar desde backup"
    log INFO "  - test-backup    : Ejecutar tests del sistema"
}

show_summary() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   INSTALACIÓN COMPLETADA                              ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
    
    echo ""
    echo "Directorios configurados:"
    echo "  - Scripts: ${INSTALL_DIR}"
    echo "  - Backups: ${BACKUP_DIR}"
    echo ""
    
    echo "Próximos pasos:"
    echo ""
    echo "1. Revisar configuración:"
    echo "   nano ${INSTALL_DIR}/backup.conf"
    echo ""
    
    echo "2. Ejecutar tests del sistema:"
    echo "   test-backup"
    echo ""
    
    echo "3. Crear primer backup:"
    echo "   backup-now"
    echo ""
    
    echo "4. Restaurar desde backup:"
    echo "   restore-backup"
    echo ""
    
    echo "5. Ver logs:"
    echo "   tail -f ${BACKUP_DIR}/logs/backup_*.log"
    echo ""
    
    echo -e "${GREEN}¡El sistema de backup ha sido instalado correctamente!${NC}"
}

# ============================================================================
# FUNCIÓN PRINCIPAL
# ============================================================================

main() {
    echo -e "${BLUE}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║   INSTALADOR DEL SISTEMA DE BACKUP                    ║"
    echo "║   Infraestructura de Monitoreo - Imagunet S.A.S.       ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
    
    check_root
    check_requirements
    create_directories
    copy_scripts
    copy_config
    
    echo ""
    configure_cron
    
    echo ""
    configure_mysql
    
    echo ""
    setup_systemd
    
    echo ""
    create_symlinks
    
    echo ""
    run_tests
    
    echo ""
    create_test_backup
    
    show_summary
}

# ============================================================================
# EJECUCIÓN
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi