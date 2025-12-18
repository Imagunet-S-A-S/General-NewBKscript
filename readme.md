SISTEMA DE BACKUP - README SIMPLE


¿QUÉ ES?
Un script que automáticamente realiza copias de seguridad de tus aplicaciones
y bases de datos cada día. Se ejecuta solo, sin que hagas nada.


¿QUÉ BACKUPS HACE?


El script respalda AUTOMÁTICAMENTE:

1. ZABBIX
   ├─ Configuración: /etc/zabbix
   └─ Datos: /var/lib/zabbix (historial, eventos, alertas)

2. GLPI
   ├─ Aplicación completa: /var/www/glpi
   └─ Datos: /var/lib/glpi (documentos, registros)

3. GRAFANA
   ├─ Configuración: /etc/grafana
   └─ Datos: /var/lib/grafana (dashboards, plugins, BD de usuario)

4. MARIADB
   ├─ Todas las bases de datos (mysqldump)
   └─ Configuración: /etc/mysql (my.cnf, settings)

5. OPENSEARCH (si está instalado)
   ├─ Configuración: /etc/opensearch
   └─ Datos: índices y búsquedas

6. JAEGER (si está instalado)
   ├─ Configuración: /etc/jaeger
   └─ Datos: trazas distribuidas

7. AIRFLOW (si está instalado)
   ├─ Todo el directorio: $AIRFLOW_HOME
   └─ Configuración, DAGs, historial


¿CÓMO FUNCIONAN LOS BACKUPS?

DETECCIÓN AUTOMÁTICA
   El script detecta qué aplicaciones tienes corriendo.
   Si Zabbix está corriendo → respalda Zabbix
   Si Grafana está corriendo → respalda Grafana
   Si MariaDB está corriendo → respalda MariaDB
   Y así con todas.

CREAR COPIA
   Copia toda la información (configuración + datos) a /backups/
   Los archivos se comprimen en formato TAR.GZ (para ocupar menos espacio)
   
   Ejemplo:
   ├─ zabbix_config_20240115_020000.tar.gz (20 MB)
   ├─ zabbix_lib_20240115_020000.tar.gz (15 MB)
   ├─ mariadb_full_20240115_020000.tar.gz (150 MB)
   └─ grafana_lib_20240115_020000.tar.gz (5 MB)

EJECUCIÓN
   Se ejecuta automáticamente cada noche a las 2:00 AM (configurable)
   O puedes ejecutar manualmente: backup-now
   
ROTACIÓN AUTOMÁTICA
   Los backups viejos se eliminan automáticamente 


RETENCIÓN - ¿CUÁNTO TIEMPO SE GUARDAN?

Periodo: 21 dia (3 semanas) Configurable


ESTRUCTURA FINAL EN TU SERVIDOR


/backups/                  ← Donde se guardan todos los backups
├── logs/
│   ├── backup_20240115_020000.log
│   ├── backup_20240116_020000.log
│   └── ...
│
├── configs/
│   ├── zabbix_config_*.tar.gz
│   ├── zabbix_lib_*.tar.gz
│   ├── glpi_lib_*.tar.gz
│   ├── grafana_lib_*.tar.gz
│   ├── mariadb_config_*.tar.gz
│   └── ...
│
└── databases/
    ├── mariadb_full_*.tar.gz
    └── ...

/opt/backup-scripts/       ← Donde se instalan los scripts
├── backup_infrastructure.sh
├── restore_infrastructure.sh
├── test_backup_system.sh
├── install.sh
└── backup.conf
