-- ==========================================================================
-- DeliverExpress - 00_reset.sql
-- Reinicia el esquema desde cero. Siempre el primero en ejecutar_todo.sql.
-- roadmap_bd.txt seccion 0 y 2.
-- ==========================================================================

DROP SCHEMA IF EXISTS deliverexpress CASCADE;
CREATE SCHEMA deliverexpress;

-- pgcrypto: crypt()/gen_salt() para el hash de contrasenias (09_indices_roles.sql).
-- Se reinstala siempre DENTRO de deliverexpress: el search_path del proyecto
-- es unicamente "deliverexpress" (sin "public"), asi que si la extension
-- quedara instalada en public sus funciones no se verian.
DROP EXTENSION IF EXISTS pgcrypto;
CREATE EXTENSION pgcrypto SCHEMA deliverexpress;

SET search_path TO deliverexpress;

-- Zona horaria de la base de datos completa (afecta a todas las sesiones).
-- Requiere ejecutarse con un rol dueño de la base (de_admin o postgres).
ALTER DATABASE deliverexpress SET timezone TO 'America/Caracas';
SET timezone TO 'America/Caracas';
