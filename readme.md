# 📦 Sistema de Backup – Infraestructura

## 📌 Descripción general

Este proyecto implementa un **sistema de backup automatizado** para una infraestructura .


El sistema:
- Detecta servicios activos
- Respalda configuraciones y datos críticos
- Ejecuta backups **diarios vía cron a las 02:00 AM**
- Mantiene una política de **retención configurable**
- **No incluye restauración automática** (solo respaldo)

---

## 🧱 Componentes soportados

- Zabbix
- Grafana
- GLPI
- MariaDB / MySQL
- OpenSearch
- Jaeger (usa OpenSearch como backend)
- Apache Airflow (**metadata en PostgreSQL únicamente**)

---

## 📂 Estructura de directorios

### 📁 Scripts
```
/opt/backup-scripts/
├── backup_infrastructure.sh
└── backup.conf
```

### 📁 Backups
```
/backups/
├── logs/
├── configs/
├── databases/
└── applications/
```

### 📁 Snapshots OpenSearch
```
/var/lib/opensearch/snapshots/
```

> ⚠️ El directorio de snapshots debe estar declarado en `opensearch.yml`
> mediante `path.repo`.

---

## ⏱️ Programación del backup

- **Frecuencia:** Diaria
- **Hora:** 02:00 AM
- **Método:** cron

Ejemplo de cron:
```
0 2 * * * source /opt/backup-scripts/backup.conf && /opt/backup-scripts/backup_infrastructure.sh >> /backups/logs/cron.log 2>&1
```

---

## 📦 ¿Qué se respalda?

### 🔧 Configuraciones
- Zabbix: `/etc/zabbix`, `/var/lib/zabbix`
- Grafana: `/etc/grafana`, `/var/lib/grafana`
- GLPI: `/var/www/glpi` o `/usr/share/glpi`
- OpenSearch: `/etc/opensearch`
- Airflow: `$AIRFLOW_HOME`

### 🗄️ Bases de datos
- **MariaDB/MySQL**: todas las bases de datos (`mysqldump`)
- **PostgreSQL (Airflow)**: metadata completa (`pg_dump`)
- **OpenSearch**: snapshots del cluster (incluye Jaeger)

---

## ⏳ Retención

Configurada en `backup.conf`:
```
RETENTION_DAYS=21
```

| Tipo | Retención |
|-----|-----------|
| Configuraciones | 21 días |
| MariaDB | 21 días |
| PostgreSQL | 21 días |
| Logs | 21 días |
| OpenSearch snapshots | Manual |

---

## 🚀 Instalación

Ejecutar como root:
```
sudo bash install.sh
```

---

## ▶️ Ejecución manual

```
backup-now
```

---

## 🔒 Consideraciones

- Backups en caliente (no se detienen servicios)
- Uso recomendado de `.my.cnf` y `.pgpass`
- Snapshots OpenSearch no se eliminan automáticamente

---

© Imagunet S.A.S 
