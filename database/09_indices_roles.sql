-- ==========================================================================
-- DeliverExpress - 09_indices_roles.sql
-- Indices, funciones de registro/login y roles de PostgreSQL.
-- roadmap_bd.txt seccion 10. Requiere ejecutarse con un rol que pueda crear
-- roles y reasignar el dueño del esquema (postgres o un rol CREATEROLE).
-- ==========================================================================
SET search_path TO deliverexpress;

-- --------------------------------------------------------------------------
-- Indices. Comparar con EXPLAIN ANALYZE antes/despues (ver README / seccion
-- de respaldo del documento) usando los datos de prueba de 10_datos_prueba.sql.
-- --------------------------------------------------------------------------
CREATE INDEX idx_pedido_activos       ON pedido(id_estado) WHERE id_estado IN (1, 2, 3, 4);
CREATE INDEX idx_pedido_cliente_fecha ON pedido(id_cliente, fecha_creacion);
CREATE INDEX idx_historial_pedido     ON historial_estado_pedido(id_pedido, fecha_hora);
CREATE INDEX idx_repartidor_zona_disp ON repartidor(id_zona, disponibilidad);
CREATE INDEX idx_ubicacion_rep_fecha  ON ubicacion_repartidor(id_repartidor, fecha_hora DESC);
CREATE INDEX idx_oferta_rep_fecha     ON oferta_asignacion(id_repartidor, fecha_oferta DESC);
CREATE INDEX idx_factura_fecha        ON factura(fecha_emision);
CREATE INDEX idx_detalle_factura_ped  ON detalle_factura(id_pedido);

-- --------------------------------------------------------------------------
-- fn_registrar_usuario: el backend la necesita desde la Fase 2.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_registrar_usuario(p_email VARCHAR, p_password VARCHAR, p_rol VARCHAR)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_usuario INT;
BEGIN
    IF EXISTS (SELECT 1 FROM usuario WHERE email = p_email) THEN
        RAISE EXCEPTION 'EMAIL_REPETIDO: ya existe un usuario registrado con ese email';
    END IF;

    INSERT INTO usuario (email, password_hash, rol)
    VALUES (p_email, crypt(p_password, gen_salt('bf')), p_rol)
    RETURNING id_usuario INTO v_id_usuario;

    RETURN v_id_usuario;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_registrar_cliente: crea usuario (rol cliente) + cliente
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_registrar_cliente(
    p_email       VARCHAR,
    p_password    VARCHAR,
    p_nombre      VARCHAR,
    p_telefono    VARCHAR,
    p_cedula_rif  VARCHAR DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_usuario  INT;
    v_id_cliente  INT;
BEGIN
    v_id_usuario := fn_registrar_usuario(p_email, p_password, 'cliente');

    INSERT INTO cliente (id_usuario, nombre, telefono, cedula_rif)
    VALUES (v_id_usuario, p_nombre, p_telefono, p_cedula_rif)
    RETURNING id_cliente INTO v_id_cliente;

    RETURN v_id_cliente;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_login: compara con crypt(); solo usuarios activos; sin filas si falla.
-- id_perfil = id_cliente/id_restaurante/id_repartidor/id_coordinador segun
-- el rol; NULL para admin (no tiene tabla de perfil propia).
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_login(p_email VARCHAR, p_password VARCHAR)
RETURNS TABLE (id_usuario INT, rol VARCHAR, id_perfil INT, nombre VARCHAR)
LANGUAGE plpgsql
AS $$
DECLARE
    v_usuario    RECORD;
    v_id_perfil  INT;
    v_nombre     VARCHAR;
BEGIN
    SELECT u.id_usuario, u.rol, u.password_hash
    INTO v_usuario
    FROM usuario u
    WHERE u.email = p_email AND u.activo = TRUE;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    IF v_usuario.password_hash <> crypt(p_password, v_usuario.password_hash) THEN
        RETURN;
    END IF;

    CASE v_usuario.rol
        WHEN 'cliente' THEN
            SELECT c.id_cliente, c.nombre INTO v_id_perfil, v_nombre
            FROM cliente c WHERE c.id_usuario = v_usuario.id_usuario;
        WHEN 'restaurante' THEN
            SELECT r.id_restaurante, r.nombre INTO v_id_perfil, v_nombre
            FROM restaurante r WHERE r.id_usuario = v_usuario.id_usuario;
        WHEN 'repartidor' THEN
            SELECT rp.id_repartidor, rp.nombre INTO v_id_perfil, v_nombre
            FROM repartidor rp WHERE rp.id_usuario = v_usuario.id_usuario;
        WHEN 'coordinador' THEN
            SELECT co.id_coordinador, co.nombre INTO v_id_perfil, v_nombre
            FROM coordinador co WHERE co.id_usuario = v_usuario.id_usuario;
        ELSE
            v_id_perfil := NULL;
            v_nombre := 'Administrador';
    END CASE;

    RETURN QUERY SELECT v_usuario.id_usuario, v_usuario.rol, v_id_perfil, v_nombre;
END;
$$;

-- --------------------------------------------------------------------------
-- Roles de PostgreSQL. Las contraseñas de abajo son solo para desarrollo
-- local; la real de_app va en el .env del backend, nunca en un script subido.
-- CREATE ROLE no admite IF NOT EXISTS: se verifica con pg_roles para que el
-- script se pueda correr de nuevo sin error al reconstruir la base.
-- --------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'de_admin') THEN
        CREATE ROLE de_admin LOGIN PASSWORD 'cambiar_esto_admin' CREATEDB CREATEROLE;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'de_app') THEN
        CREATE ROLE de_app LOGIN PASSWORD 'cambiar_esto_app';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'de_reportes') THEN
        CREATE ROLE de_reportes LOGIN PASSWORD 'cambiar_esto_reportes';
    END IF;
END $$;

-- de_admin: dueño del esquema (requiere que quien ejecuta este script pueda
-- reasignar el owner, p. ej. conectado como postgres).
ALTER SCHEMA deliverexpress OWNER TO de_admin;

-- de_app: usuario del backend (rol de_app en la connection string del .env).
GRANT USAGE ON SCHEMA deliverexpress TO de_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA deliverexpress TO de_app;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA deliverexpress TO de_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA deliverexpress TO de_app;
GRANT DELETE ON restaurante_zona, horario_restaurante TO de_app;

-- Facturacion y liquidacion: solo SELECT e INSERT (UPDATE en factura solo
-- para anular). Los triggers de inmutabilidad protegen igual: el permiso es
-- la primera barrera.
REVOKE UPDATE ON factura, detalle_factura, liquidacion_repartidor, detalle_liquidacion FROM de_app;
GRANT UPDATE ON factura TO de_app;

-- de_reportes: solo lectura sobre las vistas vw_ (no sobre las tablas base).
GRANT USAGE ON SCHEMA deliverexpress TO de_reportes;

DO $$
DECLARE
    v_vista TEXT;
BEGIN
    FOR v_vista IN SELECT viewname FROM pg_views WHERE schemaname = 'deliverexpress'
    LOOP
        EXECUTE format('GRANT SELECT ON deliverexpress.%I TO de_reportes', v_vista);
    END LOOP;
END $$;
