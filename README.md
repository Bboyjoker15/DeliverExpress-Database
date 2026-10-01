# DeliverExpress — Base de datos

Base de datos PostgreSQL 16 del proyecto DeliverExpress (materia Bases de Datos). Contiene el esquema completo, funciones, triggers, vistas, facturación, índices, roles y datos de prueba. Es la fuente de verdad del backend (`DeliverExpress-backend`) y del frontend (`DeliverExpress-frontend`): ver `Docs/roadmap_bd.txt` para el contrato completo de nombres.

Los dos puestos de base de datos (Integrante 1 y 2) del roadmap original los cubre actualmente un solo integrante, porque el Integrante 2 no se incorporó al equipo. Los scripts `03` a `06` y `pruebas_funciones.sql` (originalmente su parte) están escritos y verificados contra el backend ya construido, que ya llama exactamente a estas funciones, columnas y canales de notificación.

## Requisitos

- PostgreSQL 16 instalado localmente (no se usan servicios en la nube).
- Una base de datos vacía llamada `deliverexpress`.
- Un rol con privilegios para crear roles y reasignar el dueño del esquema (por ejemplo `postgres`), para ejecutar `09_indices_roles.sql`.

## Instalación y ejecución

```bash
createdb -U postgres deliverexpress
cd database
psql -U postgres -d deliverexpress -f ejecutar_todo.sql
```

También puede ejecutarse `ejecutar_todo.sql` con `\i` desde el Query Tool de pgAdmin, parado en la carpeta `database/`.

`ejecutar_todo.sql` corre, en orden: `00_reset.sql` → `01_esquema_tablas.sql` → `02_catalogos.sql` → `03_funciones_logistica.sql` → `04_funciones_pedidos.sql` → `05_triggers_pedidos.sql` → `06_pagos_calificaciones.sql` → `07_vistas.sql` → `08_facturacion.sql` → `09_indices_roles.sql` → `10_datos_prueba.sql`.

La base debe poder reconstruirse así desde cero, sin errores, antes de cualquier `git push` (regla del equipo).

## Roles creados

| Rol | Uso | Contraseña de desarrollo |
|---|---|---|
| `de_admin` | Dueño del esquema | `cambiar_esto_admin` |
| `de_app` | El backend se conecta con este rol | `cambiar_esto_app` |
| `de_reportes` | Solo lectura sobre las vistas `vw_*` | `cambiar_esto_reportes` |

Estas contraseñas son solo para desarrollo local. La del backend va en su `.env` (`DATABASE_URL`, `LISTEN_URL`), que no se sube a GitHub.

## Usuarios de prueba

Todos con contraseña `demo1234` (ver `10_datos_prueba.sql`):

- `admin@demo.com`
- `coord01@demo.com` … `coord03@demo.com`
- `rest01@demo.com` … `rest20@demo.com`
- `rep01@demo.com` … `rep35@demo.com`
- `cliente01@demo.com` … `cliente50@demo.com`

## Pruebas manuales

- `pruebas_funciones.sql`: casos de las funciones de logística/pedidos/calificaciones (no entra en `ejecutar_todo.sql`). Incluye instrucciones para la demostración de concurrencia con dos ventanas del Query Tool.
- `pruebas_facturacion.sql`: casos de facturación, notas de crédito e inmutabilidad (no entra en `ejecutar_todo.sql`). Incluye instrucciones para la concurrencia del correlativo de facturas.

Ejecutar ambos después de `ejecutar_todo.sql`, y revisar cada resultado contra el comentario que lo acompaña.

## Respaldo y restauración

```bash
pg_dump -U postgres -F c -f deliverexpress.backup deliverexpress
createdb -U postgres deliverexpress_restaurada
pg_restore -U postgres -d deliverexpress_restaurada deliverexpress.backup
```

Probar la restauración antes de la presentación.

## Estructura

```
database/
  00_reset.sql
  01_esquema_tablas.sql
  02_catalogos.sql
  03_funciones_logistica.sql
  04_funciones_pedidos.sql
  05_triggers_pedidos.sql
  06_pagos_calificaciones.sql
  07_vistas.sql
  08_facturacion.sql
  09_indices_roles.sql
  10_datos_prueba.sql
  ejecutar_todo.sql
  pruebas_funciones.sql
  pruebas_facturacion.sql
Docs/
  roadmap_bd.txt            contrato de la base de datos
  roadmap_backend.txt
  roadmap_frontend.txt
  DeliverExpress — Documentación del Proyecto.pdf
```
