-- ==========================================================================
-- DeliverExpress - 06_pagos_calificaciones.sql
-- Calificaciones cruzadas, calculo de promedio, marcado en revision y
-- prioridad del repartidor segun su tasa de rechazo. roadmap_bd.txt
-- seccion 8. El pago se inserta dentro de fn_crear_pedido
-- (04_funciones_pedidos.sql): no hay otra forma de crear pagos.
-- ==========================================================================
SET search_path TO deliverexpress;

-- --------------------------------------------------------------------------
-- fn_calificar
-- --------------------------------------------------------------------------
-- p_puntaje es INT (no SMALLINT como calificacion.puntaje): un integer
-- "normal" de Python/SQLAlchemy no se convierte solo a smallint al resolver
-- la funcion. El INSERT hacia la columna SMALLINT si hace ese cast.
CREATE OR REPLACE FUNCTION fn_calificar(
    p_id_pedido   INT,
    p_tipo        VARCHAR,
    p_puntaje     INT,
    p_comentario  VARCHAR DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_calificacion INT;
BEGIN
    INSERT INTO calificacion (id_pedido, tipo, puntaje, comentario)
    VALUES (p_id_pedido, p_tipo, p_puntaje, p_comentario)
    RETURNING id_calificacion INTO v_id_calificacion;

    RETURN v_id_calificacion;
END;
$$;

-- --------------------------------------------------------------------------
-- trg_validar_calificacion: solo se califica un pedido entregado, una vez
-- por tipo, y solo se califica al repartidor si el pedido tiene uno.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_validar_calificacion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_estado      SMALLINT;
    v_id_repartidor  INT;
BEGIN
    SELECT id_estado, id_repartidor INTO v_id_estado, v_id_repartidor
    FROM pedido WHERE id_pedido = NEW.id_pedido;

    IF v_id_estado IS DISTINCT FROM 5 THEN
        RAISE EXCEPTION 'CALIFICACION_NO_PERMITIDA: el pedido no esta entregado';
    END IF;

    IF NEW.tipo IN ('cliente_a_repartidor', 'repartidor_a_cliente') AND v_id_repartidor IS NULL THEN
        RAISE EXCEPTION 'CALIFICACION_NO_PERMITIDA: el pedido no tiene repartidor asignado';
    END IF;

    -- Chequeo explicito (ademas de uq_calificacion_pedido_tipo) para devolver
    -- el CODIGO de negocio en vez de un error generico de restriccion unica.
    IF EXISTS (
        SELECT 1 FROM calificacion WHERE id_pedido = NEW.id_pedido AND tipo = NEW.tipo
    ) THEN
        RAISE EXCEPTION 'CALIFICACION_NO_PERMITIDA: ya existe una calificacion de este tipo para el pedido';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_calificacion
    BEFORE INSERT ON calificacion
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_validar_calificacion();

-- --------------------------------------------------------------------------
-- trg_actualizar_promedio: recalcula el promedio y marca en_revision
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_actualizar_promedio()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_repartidor        INT;
    v_id_restaurante       INT;
    v_id_cliente           INT;
    v_promedio             NUMERIC;
    v_total                INT;
    v_calificacion_minima  NUMERIC;
    v_calificaciones_min   INT;
BEGIN
    SELECT id_repartidor, id_restaurante, id_cliente
    INTO v_id_repartidor, v_id_restaurante, v_id_cliente
    FROM pedido WHERE id_pedido = NEW.id_pedido;

    v_calificacion_minima := fn_param_num('calificacion_minima');
    v_calificaciones_min  := fn_param_num('calificaciones_minimas');

    IF NEW.tipo = 'cliente_a_repartidor' THEN
        SELECT ROUND(AVG(c.puntaje), 2), COUNT(*)
        INTO v_promedio, v_total
        FROM calificacion c
        JOIN pedido p ON p.id_pedido = c.id_pedido
        WHERE p.id_repartidor = v_id_repartidor AND c.tipo = 'cliente_a_repartidor';

        UPDATE repartidor
        SET calificacion_promedio = v_promedio,
            total_calificaciones = v_total,
            en_revision = (v_total >= v_calificaciones_min AND v_promedio < v_calificacion_minima)
        WHERE id_repartidor = v_id_repartidor;

    ELSIF NEW.tipo = 'cliente_a_restaurante' THEN
        SELECT ROUND(AVG(c.puntaje), 2), COUNT(*)
        INTO v_promedio, v_total
        FROM calificacion c
        JOIN pedido p ON p.id_pedido = c.id_pedido
        WHERE p.id_restaurante = v_id_restaurante AND c.tipo = 'cliente_a_restaurante';

        -- restaurante no tiene columna en_revision (roadmap_bd §3).
        UPDATE restaurante
        SET calificacion_promedio = v_promedio,
            total_calificaciones = v_total
        WHERE id_restaurante = v_id_restaurante;

    ELSIF NEW.tipo = 'repartidor_a_cliente' THEN
        SELECT ROUND(AVG(c.puntaje), 2), COUNT(*)
        INTO v_promedio, v_total
        FROM calificacion c
        JOIN pedido p ON p.id_pedido = c.id_pedido
        WHERE p.id_cliente = v_id_cliente AND c.tipo = 'repartidor_a_cliente';

        UPDATE cliente
        SET calificacion_promedio = v_promedio,
            total_calificaciones = v_total,
            en_revision = (v_total >= v_calificaciones_min AND v_promedio < v_calificacion_minima)
        WHERE id_cliente = v_id_cliente;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_actualizar_promedio
    AFTER INSERT ON calificacion
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_actualizar_promedio();

-- --------------------------------------------------------------------------
-- trg_actualizar_prioridad: recalcula la tasa de rechazo de las ultimas N
-- ofertas respondidas y baja la prioridad si supera el umbral (RN-10)
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_actualizar_prioridad()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_rechazo_ventana  INT;
    v_rechazo_minimo   INT;
    v_rechazo_umbral   NUMERIC;
    v_respondidas      INT;
    v_rechazadas       INT;
    v_tasa             NUMERIC;
BEGIN
    v_rechazo_ventana := fn_param_num('rechazo_ventana');
    v_rechazo_minimo  := fn_param_num('rechazo_minimo');
    v_rechazo_umbral  := fn_param_num('rechazo_umbral');

    WITH ultimas AS (
        SELECT respuesta
        FROM oferta_asignacion
        WHERE id_repartidor = NEW.id_repartidor
          AND respuesta IN ('aceptada', 'rechazada', 'expirada')
        ORDER BY fecha_oferta DESC
        LIMIT v_rechazo_ventana
    )
    SELECT count(*), count(*) FILTER (WHERE respuesta IN ('rechazada', 'expirada'))
    INTO v_respondidas, v_rechazadas
    FROM ultimas;

    IF v_respondidas < v_rechazo_minimo THEN
        RETURN NEW;
    END IF;

    v_tasa := v_rechazadas::NUMERIC / v_respondidas;

    UPDATE repartidor
    SET prioridad = CASE WHEN v_tasa > v_rechazo_umbral THEN 'baja' ELSE 'normal' END
    WHERE id_repartidor = NEW.id_repartidor;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_actualizar_prioridad
    AFTER UPDATE OF respuesta ON oferta_asignacion
    FOR EACH ROW
    WHEN (NEW.respuesta IN ('aceptada','rechazada','expirada'))
    EXECUTE FUNCTION fn_trg_actualizar_prioridad();
