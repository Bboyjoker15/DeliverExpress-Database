-- ==========================================================================
-- DeliverExpress - ejecutar_todo.sql
-- Reconstruye la base de datos completa desde cero, en orden
-- (roadmap_bd.txt seccion 0).
--
-- Ejecutar conectado a la base de datos "deliverexpress" con un rol que
-- pueda crear roles y reasignar el dueño del esquema (por ejemplo postgres):
--   psql -U postgres -d deliverexpress -f ejecutar_todo.sql
-- o con \i desde psql / el Query Tool de pgAdmin estando parado en esta carpeta.
-- ==========================================================================
\i 00_reset.sql
\i 01_esquema_tablas.sql
\i 02_catalogos.sql
\i 03_funciones_logistica.sql
\i 04_funciones_pedidos.sql
\i 05_triggers_pedidos.sql
\i 06_pagos_calificaciones.sql
\i 07_vistas.sql
\i 08_facturacion.sql
\i 09_indices_roles.sql
\i 10_datos_prueba.sql
