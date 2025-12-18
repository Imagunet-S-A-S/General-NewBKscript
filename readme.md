# SISTEMA DE BACKUP AUTOMÁTICO

## ¿QUÉ ES?

Este sistema es un **script de respaldo automático** que realiza copias de seguridad diarias de aplicaciones críticas y bases de datos del servidor.

Funciona de forma **totalmente automática**, sin intervención manual, y garantiza la protección de configuraciones y datos.

---

## ¿QUÉ RESPALDA?

El sistema realiza backups automáticos de las siguientes aplicaciones **solo si están instaladas y en ejecución**:

### ZABBIX
- Configuración: `/etc/zabbix`
- Datos: `/var/lib/zabbix`  
  *(historial, eventos, alertas)*

### GLPI
- Aplicación completa: `/var/www/glpi`
- Datos: `/var/lib/glpi`  
  *(documentos, adjuntos, registros)*

### GRAFANA
- Configuración: `/etc/grafana`
- Datos: `/var/lib/grafana`  
  *(dashboards, plugins, base de datos interna)*

### MARIADB
- Todas las bases de datos (`mysqldump`)
- Configuración: `/etc/mysql`  
  *(archivos `my.cnf` y parámetros)*

### OPENSEARCH *(si está instalado)*
- Configuración: `/etc/opensearch`
- Datos: índices y búsquedas

### JAEGER *(si está instalado)*
- Configuración: `/etc/jaeger`
- Datos: trazas distribuidas

### AIRFLOW *(si está instalado)*
- Directorio completo: `$AIRFLOW_HOME`
- Configuración, DAGs e historial de ejecuciones

---

## ¿CÓMO FUNCIONA EL SISTEMA?

### 1. Detección automática
El script identifica qué servicios están activos en el servidor.

Ejemplos:
- Si Zabbix está corriendo → se respalda Zabbix
- Si Grafana está corriendo → se respalda Grafana
- Si MariaDB está corriendo → se respalda MariaDB

Solo se respaldan los componentes disponibles.

---

### 2. Creación de los backups
- Se copian **configuraciones y datos**
- Los archivos se almacenan en `/backups/`
- Cada respaldo se comprime en formato **`.tar.gz`** para reducir espacio

**Ejemplo de archivos generados:**
```text
zabbix_config_20240115_020000.tar.gz
zabbix_lib_20240115_020000.tar.gz
mariadb_full_20240115_020000.tar.gz
grafana_lib_20240115_020000.tar.gz
