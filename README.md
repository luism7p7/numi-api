# Numi · API (Backend)

Backend único de los dos paneles web de **Numi**, la app educativa para niños de 1° a 5° de las instituciones
rurales de Medellín. Lo usan el panel administrativo, el panel docente y el backend de la app del celular.

- **Frontends:** [numi-admin-frontend](https://github.com/luism7p7/numi-admin-frontend) · [numi-docente-frontend](https://github.com/luism7p7/numi-docente-frontend)
- **En producción (Azure):** https://numi-g01.northcentralus.cloudapp.azure.com/api/v1/salud

| Capa | Tecnología |
|------|------------|
| API | Python 3.12 + Flask 3 (Gunicorn en Docker) |
| Validación | Marshmallow (DTOs) |
| Sesión | Tokens JWT (PyJWT) con roles `Administrador` y `Docente` |
| Base de datos | MySQL 8.4 con PyMySQL |
| Archivos | openpyxl (Excel) y fpdf2 (PDF) |
| Pruebas | pytest |

## Arquitectura

Cada tema es un **dominio** con sus capas, y cada capa hace una sola cosa:

```
controladores.py   rutas (Blueprint): reciben la petición y responden
dtos.py            validan lo que llega (Marshmallow)
servicios.py       reglas de negocio
repositorios.py    SQL: lo único que habla con la base de datos
```

Una petición recorre siempre: **controlador → DTO → servicio → repositorio → MySQL**. Las respuestas tienen el
formato `{"success": true, "data": ...}` o `{"success": false, "error": {...}}`.

```
├── api/
│   ├── app.py                 # python app.py → http://localhost:5001/api/v1/salud
│   ├── app/
│   │   ├── __init__.py        # crear_app(): une los dominios y los manejadores de error
│   │   ├── config.py          # lee las variables de entorno
│   │   ├── seguridad.py       # JWT: requiere_admin y requiere_docente
│   │   ├── respuestas.py      # formato {success, data} / {success, error}
│   │   ├── excepciones.py     # errores de negocio (400, 401, 403, 404, 409)
│   │   ├── compartido/        # base de datos, textos, fechas, códigos, validaciones
│   │   ├── integraciones/     # backend de la app (monitoreo y paquete de contenido)
│   │   └── dominios/          # autenticacion, usuarios, instituciones, grupos, actividades, recursos,
│   │                          # inicio, monitoreo, docente, seguimiento, reportes, gestion, puente_app
│   ├── tests/
│   └── requirements.txt
├── database/                  # schema.sql (16 tablas), init_db.py, importar_recursos_app.py
├── despliegue/                # compose.yaml, nginx/admin.conf, nginx/docente.conf, instalar.sh
├── Dockerfile                 # imagen con Gunicorn en el puerto 5000
└── .env.example
```

## Rutas principales

Todas empiezan por `/api/v1` y piden `Authorization: Bearer <token>`, salvo el acceso y los archivos.

| Método | Ruta | Qué hace |
|--------|------|----------|
| POST | `/auth/login` | `{correo, password, rol}` → token JWT |
| POST | `/auth/registro` | Solicitud de cuenta (queda pendiente) |
| GET | `/salud` | La API responde |
| GET | `/admin/inicio`, `/admin/actividades`, `/admin/recursos`, `/admin/instituciones`, `/admin/usuarios`, `/admin/monitoreo` | Panel administrativo (rol Administrador) |
| GET | `/docente/me`, `/docente/panel`, `/docente/estudiantes`, `/docente/actividades`, `/docente/reportes`, `/docente/gestion` | Panel docente (rol Docente) |
| — | `/api/app/v1/...` | Puente con el backend de la app (cabecera `X-Api-Key`) |

## Despliegue en Azure

En la VM `vm-numi-g01` (Ubuntu 24.04) todo corre con Docker Compose (`despliegue/compose.yaml`):

| Servicio | Qué es | Puertos |
|----------|--------|---------|
| `mysql` | MySQL 8.4, volumen `numi_mysql_data` | ninguno publicado |
| `backend` | Esta API (Gunicorn :5000) | solo red interna |
| `frontend-admin` | Nginx con la SPA administrativa + proxy `/api/` → backend | 80 → 443 |
| `frontend-docente` | Nginx con la SPA docente + proxy `/api/` → backend | 8080 → 8443 |

```bash
git clone https://github.com/luism7p7/numi-api.git ~/numi/backend
bash ~/numi/backend/despliegue/instalar.sh
```

## Probarlo en local

```powershell
python -m venv .venv; .\.venv\Scripts\Activate.ps1
pip install -r api/requirements.txt
Copy-Item .env.example .env          # escribe tus datos de MySQL y SECRET_KEY
python database/init_db.py           # crea la base numi con datos de ejemplo
cd api; python app.py                # http://localhost:5001/api/v1/salud
python -m pytest                     # desde la raíz
```

## Equipo

- Luis Miguel Muñoz Rendón
- Alexander Mejía Ospina
- Santiago Mayorga Hueso
- Santiago Rodríguez Jiménez

Proyecto Numi · Universidad Cooperativa de Colombia, sede Medellín.
