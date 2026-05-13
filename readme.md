# backup-imagunet

Script de backup para infraestructura de monitoreo. Respalda configuraciones, datos y bases de datos de los servicios más comunes, con rotación automática y protección contra llenado de disco.

## Servicios soportados

| Servicio | Configuración | Archivos | Base de datos |
|---|---|---|---|
| Zabbix | `/etc/zabbix` | `/var/lib/zabbix` | MariaDB o PostgreSQL |
| Grafana | `/etc/grafana` | `/var/lib/grafana` | — |
| GLPI | `/etc/glpi` | `/usr/share/glpi`, `/var/lib/glpi` | vía MariaDB |
| MariaDB | `/etc/my.cnf` | — | dump por schema |
| Airflow | — | `$AIRFLOW_HOME` | PostgreSQL |
| OpenSearch | — | snapshot API | — |

---

## Requisitos

- Linux con `bash` 4+
- `tar`, `curl` (el instalador los verifica e instala si faltan)
- Según los servicios habilitados: `mysqldump`, `pg_dump`
- Acceso root para la instalación

---

## Instalación

### 1. Clonar o copiar el repositorio al servidor

```bash
git clone <url-del-repo> /tmp/backup-imagunet
cd /tmp/backup-imagunet
```

O copiar los archivos con `scp` desde otra máquina:

```bash
scp backup_infrastructure.sh backup.conf install.sh uninstall.sh \
    usuario@servidor:/tmp/backup-imagunet/
```

### 2. Editar `backup.conf`

Antes de instalar, ajustar la configuración según el entorno:

```bash
nano /tmp/backup-imagunet/backup.conf
```

Ver la sección [Configuración](#configuración) más abajo para el detalle de cada variable.

### 3. Ejecutar el instalador como root

```bash
cd /tmp/backup-imagunet
chmod +x install.sh
sudo bash install.sh
```

El instalador realiza las siguientes acciones:

1. Verifica e instala dependencias faltantes (`tar`, `curl`)
2. Copia el script a `/opt/backup-scripts/`
3. Copia la configuración a `/etc/backup-imagunet/backup.conf` *(solo si no existe)*
4. Crea el comando `backup-now` en `/usr/local/bin/`
5. Registra la tarea en `cron` para ejecutarse todos los días a las **02:00 AM**

> Si ya existía una instalación previa, el archivo `backup.conf` **no se sobreescribe** para preservar la configuración existente. El instalador avisa para revisar si hay variables nuevas.

---

## Uso

### Ejecutar un backup manualmente

```bash
sudo backup-now
```

### Ver el log del último backup

Cada servicio genera su propio log dentro de su directorio de backup:

```bash
cat /var/backups/glpi/logs/backup.log      # GLPI
cat /var/lib/zabbix/logs/backup.log        # Zabbix
cat /var/lib/grafana/logs/backup.log       # Grafana
cat /var/lib/mariadb/logs/backup.log       # MariaDB
cat /var/lib/airflow/logs/backup.log       # Airflow
cat /var/lib/opensearch/logs/backup.log    # OpenSearch
```

### Cambiar la hora de ejecución

```bash
sudo crontab -e
```

El formato es estándar cron (`minuto hora * * *`):

```
# Todos los días a las 03:30 AM
30 3 * * * . /etc/backup-imagunet/backup.conf && /opt/backup-scripts/backup_infrastructure.sh
```

---

## Configuración

El archivo `/etc/backup-imagunet/backup.conf` controla el comportamiento completo del script.

### Habilitar o deshabilitar servicios

```bash
export BACKUP_ENABLE_ZABBIX=true
export BACKUP_ENABLE_GRAFANA=true
export BACKUP_ENABLE_GLPI=true
export BACKUP_ENABLE_MARIADB=true
export BACKUP_ENABLE_AIRFLOW=true
export BACKUP_ENABLE_OPENSEARCH=true
```

Cambiar a `false` para saltar un servicio completamente, sin importar si está corriendo.

### Retención y protección de disco

```bash
export RETENTION_DAYS=21       # días totales que se conservan los backups
export HOT_DAYS=7              # días en formato descomprimido (acceso rápido)
export DISK_THRESHOLD_PCT=85   # % máximo de uso permitido en la partición
```

Cuando la partición de destino supera el umbral, el script intenta liberar espacio ejecutando la rotación. Si el disco sigue lleno tras la rotación, cancela ese servicio y continúa con los demás.

### Rutas por servicio

Cada ruta se respalda solo si su variable está definida. **Comentar una variable deshabilita ese path:**

```bash
# Se respalda:
export GLPI_CFG_DIR="/etc/glpi"

# No se respalda (comentado):
# export GLPI_APP_DIR="/usr/share/glpi"
```

Para agregar rutas adicionales fuera de las predefinidas, usar la variable `_EXTRA_DIRS` del servicio separando paths con `:`:

```bash
# Una sola ruta extra
export GLPI_EXTRA_DIRS="/opt/mi-plugin"

# Varias rutas extra
export ZABBIX_EXTRA_DIRS="/opt/zabbix-scripts:/srv/zabbix-templates"
```

### MariaDB — conexión local o remota

```bash
export MYSQL_HOST="localhost"   # IP del servidor si es remoto
export MYSQL_PORT="3306"
export MYSQL_USER="root"
export MYSQL_PASSWORD=""        # recomendado: dejar vacío y usar ~/.my.cnf
```

Cuando MariaDB tiene múltiples schemas, cada uno se respalda por separado y se almacena en el directorio del servicio al que pertenece (`glpi`, `zabbix`, `grafana`). Los schemas sin asociación van a `/var/lib/mariadb/newest/databases/`.

### Zabbix — base de datos

Por defecto, si Zabbix usa MariaDB en el mismo servidor, `backup_mariadb` respalda el schema `zabbix` automáticamente. Definir `ZABBIX_DB_TYPE` solo en estos casos:

| Caso | Acción |
|---|---|
| Zabbix en MariaDB **local** | Dejar `ZABBIX_DB_TYPE` comentado |
| Zabbix en **PostgreSQL** | `ZABBIX_DB_TYPE=postgresql` |
| Zabbix en MariaDB en **otro servidor** | `ZABBIX_DB_TYPE=mariadb` + `ZABBIX_DB_HOST` |

```bash
# export ZABBIX_DB_TYPE="postgresql"
# export ZABBIX_DB_HOST="localhost"
# export ZABBIX_DB_PORT="5432"
# export ZABBIX_DB_NAME="zabbix"
# export ZABBIX_DB_USER="zabbix"
# export ZABBIX_DB_PASSWORD=""      # recomendado: usar ~/.pgpass
```

---

## Estructura de los backups

Cada servicio guarda sus backups en su propio directorio base:

```
/var/backups/glpi/          GLPI (directorio separado para evitar conflictos)
/var/lib/zabbix/            Zabbix
/var/lib/grafana/           Grafana
/var/lib/mariadb/           MariaDB (schemas sin servicio asociado)
/var/lib/airflow/           Airflow
/var/lib/opensearch/        OpenSearch
```

Dentro de cada directorio base la estructura es:

```
<base>/
├── newest/                 backup más reciente (descomprimido)
│   ├── configs/
│   ├── databases/
│   └── applications/
├── 20260511/               semana anterior (un directorio por fecha de domingo)
│   └── ...
├── 20260504.tar.gz         semanas antiguas comprimidas al máximo
└── logs/
    └── backup.log
```

**Ciclo de vida:**

1. El backup entra en `newest/` como archivos individuales
2. Al superar `HOT_DAYS` días se comprime la semana completa en un `.tar.gz`
3. Al superar `RETENTION_DAYS` días se elimina definitivamente

---

## Desinstalación

```bash
cd /tmp/backup-imagunet
sudo bash uninstall.sh
```

El script de desinstalación realiza las siguientes acciones:

1. Elimina la entrada de cron
2. Elimina el script de `/opt/backup-scripts/`
3. Elimina el symlink `/usr/local/bin/backup-now`
4. Detiene y elimina las units de systemd si quedaron de una instalación anterior como servicio
5. **Pregunta antes de borrar** `/etc/backup-imagunet/` para no eliminar la configuración accidentalmente

> Los directorios de backup (`/var/backups/glpi`, `/var/lib/zabbix/newest`, etc.) **no se eliminan** durante la desinstalación. Contienen los backups generados y deben borrarse manualmente si ya no se necesitan.

---

© Imagunet S.A.S
