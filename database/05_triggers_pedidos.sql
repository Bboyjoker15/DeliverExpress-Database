-- ==========================================================================
-- DeliverExpress - 05_triggers_pedidos.sql
-- Triggers de pedidos: transicion de estados, historial, liberar
-- repartidor, mismo restaurante por pedido, y notificaciones en tiempo real
-- con pg_notify. roadmap_bd.txt seccion 7. Los nombres de canal
-- (canal_pedidos/canal_ofertas/canal_ubicaciones) y los campos del JSON son
-- el contrato con el backend.
-- ==========================================================================
SET search_path TO deliverexpress;

-- --------------------------------------------------------------------------
-- trg_validar_transicion: rechaza saltos o retrocesos de estado (RN-01)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_validar_transicion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF (OLD.id_estado, NEW.id_estado) NOT IN (
        (1,2), (2,3), (3,4), (4,5), (1,6), (2,6), (3,6)
    ) THEN
        RAISE EXCEPTION 'TRANSICION_INVALIDA: no se puede pasar del estado % al %', OLD.id_estado, NEW.id_estado;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_transicion
    BEFORE UPDATE OF id_estado ON pedido
    FOR EACH ROW
    WHEN (OLD.id_estado IS DISTINCT FROM NEW.id_estado)
    EXECUTE FUNCTION fn_trg_validar_transicion();

-- --------------------------------------------------------------------------
-- trg_historial_estado: guarda cada cambio de estado con fecha y hora (RN-02)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_historial_estado()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO historial_estado_pedido (id_pedido, id_estado, fecha_hora, id_usuario)
    VALUES (
        NEW.id_pedido, NEW.id_estado, now(),
        NULLIF(current_setting('deliverexpress.id_usuario', true), '')::INT
    );
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_historial_estado
    AFTER INSERT OR UPDATE OF id_estado ON pedido
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_historial_estado();

-- --------------------------------------------------------------------------
-- trg_liberar_repartidor: al entregar o cancelar, el repartidor vuelve a
-- 'libre' (RN-09)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_liberar_repartidor()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.id_estado IN (5, 6) AND NEW.id_repartidor IS NOT NULL THEN
        UPDATE repartidor SET disponibilidad = 'libre' WHERE id_repartidor = NEW.id_repartidor;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_liberar_repartidor
    AFTER UPDATE OF id_estado ON pedido
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_liberar_repartidor();

-- --------------------------------------------------------------------------
-- trg_mismo_restaurante: todos los productos de un pedido son del mismo
-- restaurante (RN-04)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_mismo_restaurante()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_restaurante_pedido    INT;
    v_id_restaurante_producto  INT;
BEGIN
    SELECT id_restaurante INTO v_id_restaurante_pedido FROM pedido WHERE id_pedido = NEW.id_pedido;
    SELECT id_restaurante INTO v_id_restaurante_producto FROM producto WHERE id_producto = NEW.id_producto;

    IF v_id_restaurante_pedido IS DISTINCT FROM v_id_restaurante_producto THEN
        RAISE EXCEPTION 'PRODUCTO_INVALIDO: el producto % no pertenece al restaurante del pedido', NEW.id_producto;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_mismo_restaurante
    BEFORE INSERT ON detalle_pedido
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_mismo_restaurante();

-- --------------------------------------------------------------------------
-- trg_notificar_pedido: aviso en vivo para coordinador/restaurante/cliente/
-- repartidor. Nombre del canal y campos = contrato con el backend.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_notificar_pedido()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM pg_notify('canal_pedidos', json_build_object(
        'id_pedido', NEW.id_pedido,
        'id_estado', NEW.id_estado,
        'id_cliente', NEW.id_cliente,
        'id_restaurante', NEW.id_restaurante,
        'id_repartidor', NEW.id_repartidor
    )::text);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_notificar_pedido
    AFTER INSERT OR UPDATE ON pedido
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_notificar_pedido();

-- --------------------------------------------------------------------------
-- trg_notificar_oferta
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_notificar_oferta()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM pg_notify('canal_ofertas', json_build_object(
        'id_oferta', NEW.id_oferta,
        'id_pedido', NEW.id_pedido,
        'id_repartidor', NEW.id_repartidor,
        'respuesta', NEW.respuesta
    )::text);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_notificar_oferta
    AFTER INSERT OR UPDATE ON oferta_asignacion
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_notificar_oferta();

-- --------------------------------------------------------------------------
-- trg_ubicacion_actual: actualiza la posicion actual del repartidor y avisa
-- al mapa. id_cliente e id_restaurante salen del pedido; NULL si no tiene.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_ubicacion_actual()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_cliente      INT;
    v_id_restaurante  INT;
BEGIN
    UPDATE repartidor
    SET latitud_actual = NEW.latitud,
        longitud_actual = NEW.longitud,
        ubicacion_actualizada_en = NEW.fecha_hora
    WHERE id_repartidor = NEW.id_repartidor;

    IF NEW.id_pedido IS NOT NULL THEN
        SELECT id_cliente, id_restaurante INTO v_id_cliente, v_id_restaurante
        FROM pedido WHERE id_pedido = NEW.id_pedido;
    END IF;

    PERFORM pg_notify('canal_ubicaciones', json_build_object(
        'id_repartidor', NEW.id_repartidor,
        'id_pedido', NEW.id_pedido,
        'id_cliente', v_id_cliente,
        'id_restaurante', v_id_restaurante,
        'latitud', NEW.latitud,
        'longitud', NEW.longitud
    )::text);

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ubicacion_actual
    AFTER INSERT ON ubicacion_repartidor
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_ubicacion_actual();
