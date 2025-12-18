================================================================================
SISTEMA DE BACKUP - README SIMPLE
================================================================================

¿QUÉ ES?
Un script que automáticamente realiza copias de seguridad de tus aplicaciones
y bases de datos cada día. Se ejecuta solo, sin que hagas nada.

================================================================================
¿QUÉ BACKUPS HACE?
================================================================================

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

================================================================================
¿CÓMO FUNCIONAN LOS BACKUPS?
================================================================================

PASO 1: DETECCIÓN AUTOMÁTICA
   El script detecta qué aplicaciones tienes corriendo.
   Si Zabbix está corriendo → respalda Zabbix
   Si Grafana está corriendo → respalda Grafana
   Si MariaDB está corriendo → respalda MariaDB
   Y así con todas.

PASO 2: CREAR COPIA
   Copia toda la información (configuración + datos) a /backups/
   Los archivos se comprimen en formato TAR.GZ (para ocupar menos espacio)
   
   Ejemplo:
   ├─ zabbix_config_20240115_020000.tar.gz (20 MB)
   ├─ zabbix_lib_20240115_020000.tar.gz (15 MB)
   ├─ mariadb_full_20240115_020000.tar.gz (150 MB)
   └─ grafana_lib_20240115_020000.tar.gz (5 MB)

PASO 3: EJECUCIÓN
   Se ejecuta automáticamente cada noche a las 2:00 AM (configurable)
   O puedes ejecutar manualmente: backup-now
   
PASO 4: ROTACIÓN AUTOMÁTICA
   Los backups viejos se eliminan automáticamente (ver sección de retención)

================================================================================
RETENCIÓN - ¿CUÁNTO TIEMPO SE GUARDAN?
================================================================================

PERÍODO: 21 DÍAS (3 SEMANAS)

FUNCIONAMIENTO:
- Día 1:  Se crea backup del día 1
- Día 2:  Se crea backup del día 2 (Día 1 se mantiene)
- Día 3:  Se crea backup del día 3 (Días 1-2 se mantienen)
- ...
- Día 21: Se crea backup del día 21 (Días 1-20 se mantienen)
- Día 22: Se crea backup del día 22 Y SE ELIMINA EL BACKUP DEL DÍA 1
- Día 23: Se crea backup del día 23 Y SE ELIMINA EL BACKUP DEL DÍA 2

RESULTADO: Siempre tienes los últimos 21 días de backups disponibles

¿POR QUÉ 21 DÍAS?
✓ Suficiente para recuperar si algo falla hace 1-2 semanas
✓ No ocupa mucho espacio en disco
✓ Si necesitas cambiar, edita: backup.conf (RETENTION_DAYS="21")

EJEMPLO:
Si hoy es viernes y Zabbix se daña, puedes restaurar desde hace 20 días.
Pero si esperas 22 días, el backup más antiguo se habrá eliminado.

================================================================================
¿QUÉ OCUPA ESPACIO?
================================================================================

COMPRESIÓN: Los backups se comprimen automáticamente 70-90%

EJEMPLO CON DATOS REALES:

Sin comprimir → Con tar.gz comprimido
─────────────────────────────────────
80 MB (Zabbix config)    → 15 MB
200 MB (GLPI datos)      → 35 MB
120 MB (Grafana datos)   → 18 MB
5 GB (MariaDB)           → 400 MB
3 GB (OpenSearch)        → 200 MB

TOTAL 21 DÍAS:
Sin comprimir: ~350 GB
Con tar.gz:    ~50 GB
Ahorras:       ~300 GB de espacio

RECOMENDACIÓN: Ten al menos 50-100 GB disponibles en /backups/

================================================================================
INSTALACIÓN - 3 PASOS SIMPLES
================================================================================

PASO 1: INSTALAR
   $ sudo bash install.sh
   
   El instalador:
   ✓ Crea directorios (/backups, /opt/backup-scripts)
   ✓ Configura credenciales de MySQL
   ✓ Configura ejecución automática (cron)
   ✓ Haz las preguntas que te hace

PASO 2: CREAR PRIMER BACKUP
   $ backup-now
   
   Espera a que termine (depende de cuántos datos tengas)
   Ver progreso: tail -f /backups/logs/backup_*.log

PASO 3: VERIFICAR
   $ ls -lh /backups/
   
   Deberías ver archivos .tar.gz con tus backups

================================================================================
COMANDOS BÁSICOS
================================================================================

CREAR BACKUP AHORA:
   $ backup-now

RESTAURAR UN BACKUP (menú interactivo):
   $ restore-backup
   
   Selecciona:
   1. Qué aplicación
   2. Qué fecha/backup
   3. Confirma
   
   ¡Listo!

VER LOGS:
   $ tail -50 /backups/logs/backup_*.log
   
   Muestra qué se respaldaró, si hubo errores, etc.

VER ESPACIO USADO:
   $ du -sh /backups/
   
   Cuánto espacio ocupan todos los backups

LISTAR BACKUPS DISPONIBLES:
   $ ls -lh /backups/configs/
   $ ls -lh /backups/databases/

EJECUTAR TESTS:
   $ test-backup
   
   Valida que todo está bien instalado

================================================================================
¿CUÁNDO SE EJECUTA?
================================================================================

AUTOMÁTICO: Cada noche a las 2:00 AM (configurable)
   Se ejecuta sin que hagas nada
   Los backups se crean automáticamente

MANUAL: Cuando quieras
   $ backup-now
   Crea un backup inmediatamente

SUPERVISIÓN:
   Ver los logs para confirmar que funciona:
   $ tail -f /backups/logs/backup_*.log

================================================================================
¿QUÉ PASA SI ALGO FALLA?
================================================================================

FALLA UN DÍA:
   Si el backup falla el día 10, el día 11 volverá a intentar.
   Los backups de los días 1-9 están intactos.

FALLA MARIADB:
   Si MariaDB está caído cuando se ejecuta, solo se respaldan otros servicios.
   Cuando MariaDB vuelva a estar up, el siguiente día se respalda.

ESPACIO DISCO LLENO:
   Si se llena /backups, la ejecución fallaará.
   Solución: Aumenta espacio o reduce RETENTION_DAYS a 14 días.

RESTAURACIÓN FALLIDA:
   Usa restore-backup, selecciona otro día anterior.
   Siempre tienes 21 intentos disponibles.

================================================================================
ARCHIVOS INCLUIDOS
================================================================================

backup_infrastructure.sh    → Script principal (el que hace todo)
restore_infrastructure.sh   → Herramienta para restaurar
test_backup_system.sh      → Tests para validar instalación
install.sh                 → Instalador automático
backup.conf                → Configuración (edita si necesitas cambiar algo)

================================================================================
ESTRUCTURA FINAL EN TU SERVIDOR
================================================================================

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

================================================================================
EJEMPLOS PRÁCTICOS
================================================================================

EJEMPLO 1: SE DAÑA GRAFANA HOYOY
   1. Necesito restaurar del backup de hace 3 días
   2. $ restore-backup
   3. Selecciono "3. Configuración de Grafana"
   4. Selecciono backup del 3 de enero
   5. Confirmo
   6. ¡Grafana restaurada!

EJEMPLO 2: NECESITO LISTAR QUÉ HAY EN UN BACKUP
   $ tar -tzf /backups/databases/mariadb_full_*.tar.gz | head -20
   (Muestra qué BD están dentro)

EJEMPLO 3: VER SI UN BACKUP ESTÁ CORRUPTO
   $ tar -tzf /backups/configs/zabbix_config_*.tar.gz > /dev/null && echo "OK"
   Si dice "OK" → backup intacto
   Si dice error → backup corrupto (usa otro anterior)

EJEMPLO 4: MONITOREAR EN VIVO LA EJECUCIÓN
   1. $ backup-now
   2. En otra terminal: $ tail -f /backups/logs/backup_*.log
   (Ves en tiempo real qué se está respalda)

================================================================================
¿PREGUNTAS COMUNES?
================================================================================

P: ¿Se ejecuta solo sin que haga nada?
R: Sí. El cron automático lo ejecuta cada noche. Solo mira logs ocasionalmente.

P: ¿Puedo cambiar la hora de ejecución?
R: Sí. El instalador te pregunta (2 AM, 12 mediodía, etc.)
   O edita crontab: crontab -e

P: ¿Cuánto tarda un backup?
R: Depende de tus datos. Típicamente 5-30 minutos.

P: ¿Puedo cambiar los 21 días?
R: Sí. Edita backup.conf: RETENTION_DAYS="14" (o lo que necesites)

P: ¿Dónde se guardan realmente los backups?
R: En /backups/ del servidor donde instalaste.

P: ¿Puedo enviarlos a otro servidor?
R: Sí, pero requiere configuración avanzada (ver BACKUP_DOCUMENTATION.md)

P: ¿Se puede restaurar automáticamente?
R: No. restore-backup es menú interactivo (por seguridad).

P: ¿Qué pasa si falla el servidor?
R: Los backups están en el servidor. Si el servidor explota, pierdes todo.
   Solución: Copia backups a otro servidor periódicamente (backup remoto).

================================================================================
SOPORTE
================================================================================

Email: systems@imagunet.com.co
Wiki: https://wiki.imagunet.com.co/backups

Para más información:
  - Leer BACKUP_DOCUMENTATION.md (completo)
  - Ver logs: tail -f /backups/logs/backup_*.log
  - Ejecutar tests: test-backup

================================================================================
RESUMEN
================================================================================

✓ Script que respalda AUTOMÁTICAMENTE Zabbix, GLPI, Grafana, MariaDB
✓ Se ejecuta cada noche (2 AM por defecto)
✓ Guarda últimos 21 días de backups
✓ Se elimina automáticamente lo más antiguo
✓ Comprimido en TAR.GZ (70-90% menos espacio)
✓ Fácil de restaurar con: restore-backup
✓ Cero intervención manual
✓ Instalación en 3 pasos

¡Listo para proteger tu infraestructura! 🚀

================================================================================
VERSIÓN: 2.1
ÚLTIMO CAMBIO: Enero 2024
================================================================================

========================
-rw-r--r-- 1 999 root  14K Dec 18 17:08 test_backup_system.sh