-- ==========================================================================
-- DeliverExpress - 04_funciones_pedidos.sql
-- Funciones de pedidos: cotizar, crear, cambiar de estado, asignar
-- repartidor, responder ofertas, expirar ofertas, reasignar y registrar
-- ubicacion. roadmap_bd.txt seccion 6.
-- ==========================================================================
SET search_path TO deliverexpress;

-- --------------------------------------------------------------------------
-- fn_cotizar_pedido: calcula todo SIN guardar nada (usa el checkout y
-- fn_crear_pedido, asi el calculo vive en un solo lugar).
-- p_productos: [{"id_producto": 3, "cantidad": 2}, ...]
-- --------------------------------------------------------------------------
-- p_propina es DOUBLE PRECISION (no NUMERIC): el backend manda un float de
-- Python (Pydantic "propina: float"). double precision -> numeric es solo
-- cast de ASIGNACION en Postgres (no implicito), asi que con NUMERIC esta
-- llamada fallaria con "function does not exist" igual que paso con
-- fn_cambiar_estado/fn_calificar y SMALLINT. Por dentro se castea una sola
-- vez a NUMERIC (v_propina) para que toda la aritmetica de dinero siga
-- siendo exacta en base 10, nunca binaria.
CREATE OR REPLACE FUNCTION fn_cotizar_pedido(
    p_id_cliente     INT,
    p_id_restaurante INT,
    p_id_direccion   INT,
    p_productos      JSONB,
    p_propina        DOUBLE PRECISION,
    p_moneda         CHAR(3)
)
RETURNS TABLE (
    distancia_km  NUMERIC,
    subtotal      NUMERIC,
    costo_envio   NUMERIC,
    propina       NUMERIC,
    iva_total     NUMERIC,
    igtf          NUMERIC,
    total         NUMERIC,
    tasa_bcv      NUMERIC,
    total_ves     NUMERIC
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_rest_lat        NUMERIC;
    v_rest_lon        NUMERIC;
    v_dir_lat         NUMERIC;
    v_dir_lon         NUMERIC;
    v_distancia       NUMERIC;
    v_costo_envio     NUMERIC;
    v_subtotal        NUMERIC := 0;
    v_base_16         NUMERIC := 0;
    v_iva_total       NUMERIC;
    v_igtf            NUMERIC;
    v_total           NUMERIC;
    v_tasa_bcv        NUMERIC;
    v_total_ves       NUMERIC;
    v_iva_general     NUMERIC;
    v_igtf_pct        NUMERIC;
    v_item            JSONB;
    v_id_producto     INT;
    v_cantidad        INT;
    v_precio          NUMERIC;
    v_exento          BOOLEAN;
    v_propina         NUMERIC;
BEGIN
    v_propina := p_propina::NUMERIC;

    -- 1. La direccion existe y es del cliente
    SELECT latitud, longitud INTO v_dir_lat, v_dir_lon
    FROM direccion_cliente
    WHERE id_direccion = p_id_direccion AND id_cliente = p_id_cliente;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'DIRECCION_INVALIDA: la direccion no existe o no es del cliente';
    END IF;

    -- 2. El restaurante esta disponible
    IF NOT fn_restaurante_disponible(p_id_restaurante, p_id_direccion) THEN
        RAISE EXCEPTION 'RESTAURANTE_NO_DISPONIBLE: inactivo, cerrado o no cubre la zona';
    END IF;

    IF p_productos IS NULL OR jsonb_array_length(p_productos) = 0 THEN
        RAISE EXCEPTION 'PRODUCTO_INVALIDO: la lista de productos esta vacia';
    END IF;

    -- 3. Cada producto existe, es del restaurante, disponible y cantidad > 0
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos)
    LOOP
        v_id_producto := (v_item ->> 'id_producto')::INT;
        v_cantidad    := (v_item ->> 'cantidad')::INT;

        IF v_cantidad IS NULL OR v_cantidad <= 0 THEN
            RAISE EXCEPTION 'PRODUCTO_INVALIDO: cantidad invalida para el producto %', v_id_producto;
        END IF;

        SELECT precio, exento_iva INTO v_precio, v_exento
        FROM producto
        WHERE id_producto = v_id_producto
          AND id_restaurante = p_id_restaurante
          AND disponible = TRUE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'PRODUCTO_INVALIDO: el producto % no existe, es de otro restaurante o no esta disponible', v_id_producto;
        END IF;

        v_subtotal := v_subtotal + (v_cantidad * v_precio);
        IF NOT v_exento THEN
            v_base_16 := v_base_16 + (v_cantidad * v_precio);
        END IF;
    END LOOP;

    -- 4. Distancia y costo de envio
    SELECT latitud, longitud INTO v_rest_lat, v_rest_lon
    FROM restaurante WHERE id_restaurante = p_id_restaurante;

    v_distancia   := fn_distancia_km(v_rest_lat, v_rest_lon, v_dir_lat, v_dir_lon);
    v_costo_envio := fn_costo_envio(v_distancia);

    -- 5. Totales
    v_iva_general := fn_param_num('iva_general');
    v_igtf_pct    := fn_param_num('igtf');

    v_base_16   := v_base_16 + v_costo_envio;
    v_iva_total := ROUND(v_base_16 * v_iva_general, 2);

    IF p_moneda = 'USD' THEN
        v_igtf := ROUND((v_subtotal + v_costo_envio + v_propina + v_iva_total) * v_igtf_pct, 2);
    ELSE
        v_igtf := 0;
    END IF;

    v_total     := v_subtotal + v_costo_envio + v_propina + v_iva_total + v_igtf;
    v_tasa_bcv  := fn_tasa_bcv(CURRENT_DATE);
    v_total_ves := ROUND(v_total * v_tasa_bcv, 2);

    RETURN QUERY SELECT
        v_distancia, v_subtotal, v_costo_envio, v_propina, v_iva_total,
        v_igtf, v_total, v_tasa_bcv, v_total_ves;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_crear_pedido: valida, calcula y guarda pedido + detalle + pago, todo en
-- la misma transaccion. La factura NO se crea aqui (se crea al entregar).
-- --------------------------------------------------------------------------
-- p_propina es DOUBLE PRECISION por el mismo motivo que en fn_cotizar_pedido
-- (arriba): asi llega el float de Python. Solo se reenvia a fn_cotizar_pedido
-- (que ya lo convierte a NUMERIC); el resto de esta funcion usa v_cot.propina.
CREATE OR REPLACE FUNCTION fn_crear_pedido(
    p_id_cliente     INT,
    p_id_restaurante INT,
    p_id_direccion   INT,
    p_productos      JSONB,
    p_propina        DOUBLE PRECISION,
    p_moneda         CHAR(3),
    p_ultimos4       CHAR(4)
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_cot                RECORD;
    v_id_pedido          INT;
    v_comision_pct       NUMERIC;
    v_comision           NUMERIC;
    v_monto_restaurante  NUMERIC;
    v_item               JSONB;
    v_id_producto        INT;
    v_cantidad           INT;
    v_precio             NUMERIC;
BEGIN
    SELECT * INTO v_cot
    FROM fn_cotizar_pedido(p_id_cliente, p_id_restaurante, p_id_direccion, p_productos, p_propina, p_moneda);

    v_comision_pct      := fn_param_num('comision_plataforma');
    v_comision          := ROUND(v_cot.subtotal * v_comision_pct, 2);
    v_monto_restaurante := v_cot.subtotal - v_comision;

    INSERT INTO pedido (
        id_cliente, id_restaurante, id_direccion, id_estado,
        distancia_km, subtotal, costo_envio, propina, iva_total, igtf,
        comision_plataforma, monto_restaurante, total,
        moneda_pago, tasa_bcv_aplicada, total_ves
    ) VALUES (
        p_id_cliente, p_id_restaurante, p_id_direccion, 1,
        v_cot.distancia_km, v_cot.subtotal, v_cot.costo_envio, v_cot.propina,
        v_cot.iva_total, v_cot.igtf, v_comision, v_monto_restaurante, v_cot.total,
        p_moneda, v_cot.tasa_bcv, v_cot.total_ves
    )
    RETURNING id_pedido INTO v_id_pedido;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_productos)
    LOOP
        v_id_producto := (v_item ->> 'id_producto')::INT;
        v_cantidad    := (v_item ->> 'cantidad')::INT;

        SELECT precio INTO v_precio FROM producto WHERE id_producto = v_id_producto;

        INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario, subtotal)
        VALUES (v_id_pedido, v_id_producto, v_cantidad, v_precio, v_cantidad * v_precio);
    END LOOP;

    INSERT INTO pago (id_pedido, monto, moneda, ultimos4, referencia)
    VALUES (
        v_id_pedido, v_cot.total, p_moneda, p_ultimos4,
        'SIM-' || v_id_pedido || '-' || to_char(now(), 'YYYYMMDDHH24MISS')
    );

    UPDATE pedido SET tiempo_estimado_min = fn_tiempo_estimado(v_id_pedido)
    WHERE id_pedido = v_id_pedido;

    RETURN v_id_pedido;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_cambiar_estado: UNICA forma de cambiar el estado de un pedido.
-- --------------------------------------------------------------------------
-- p_nuevo_estado es INT (no SMALLINT, aunque pedido.id_estado si lo es):
-- Postgres no convierte automaticamente un integer "normal" a smallint al
-- resolver una funcion, ni siquiera habiendo una sola candidata (si lo hiciera
-- SMALLINT, toda llamada del backend con un entero de Python fallaria con
-- "function does not exist"). El INSERT/UPDATE hacia la columna SMALLINT si
-- hace ese cast de asignacion sin problema.
CREATE OR REPLACE FUNCTION fn_cambiar_estado(
    p_id_pedido    INT,
    p_nuevo_estado INT,
    p_id_usuario   INT,
    p_motivo       VARCHAR DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_repartidor INT;
BEGIN
    -- El trigger de historial lee este valor con current_setting(..., true).
    PERFORM set_config('deliverexpress.id_usuario', p_id_usuario::TEXT, TRUE);

    IF p_nuevo_estado = 4 THEN
        SELECT id_repartidor INTO v_id_repartidor FROM pedido WHERE id_pedido = p_id_pedido;
        IF v_id_repartidor IS NULL THEN
            RAISE EXCEPTION 'REPARTIDOR_NO_ASIGNADO: se intenta pasar a en_camino sin repartidor';
        END IF;
    END IF;

    -- trg_validar_transicion valida que el cambio de estado sea permitido.
    IF p_nuevo_estado = 6 THEN
        UPDATE pedido SET id_estado = p_nuevo_estado, motivo_cancelacion = p_motivo
        WHERE id_pedido = p_id_pedido;
    ELSE
        UPDATE pedido SET id_estado = p_nuevo_estado
        WHERE id_pedido = p_id_pedido;
    END IF;

    IF p_nuevo_estado = 2 THEN
        PERFORM fn_asignar_repartidor(p_id_pedido);
    END IF;

    IF p_nuevo_estado = 6 THEN
        UPDATE oferta_asignacion
        SET respuesta = 'expirada', fecha_respuesta = now()
        WHERE id_pedido = p_id_pedido AND respuesta = 'pendiente';
    END IF;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_asignar_repartidor: elige al mejor candidato (RN-07/RN-08) y crea la
-- oferta. SELECT ... FOR UPDATE SKIP LOCKED evita que dos asignaciones
-- simultaneas tomen al mismo repartidor (RNF-12).
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_asignar_repartidor(p_id_pedido INT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_restaurante  INT;
    v_rest_lat        NUMERIC;
    v_rest_lon        NUMERIC;
    v_id_repartidor   INT;
BEGIN
    IF EXISTS (SELECT 1 FROM pedido WHERE id_pedido = p_id_pedido AND id_repartidor IS NOT NULL) THEN
        RETURN NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM oferta_asignacion WHERE id_pedido = p_id_pedido AND respuesta = 'pendiente') THEN
        RETURN NULL;
    END IF;

    SELECT p.id_restaurante, r.latitud, r.longitud
    INTO v_id_restaurante, v_rest_lat, v_rest_lon
    FROM pedido p JOIN restaurante r ON r.id_restaurante = p.id_restaurante
    WHERE p.id_pedido = p_id_pedido;

    SELECT rep.id_repartidor
    INTO v_id_repartidor
    FROM repartidor rep
    JOIN restaurante_zona rz ON rz.id_zona = rep.id_zona AND rz.id_restaurante = v_id_restaurante
    WHERE rep.activo = TRUE
      AND rep.disponibilidad = 'libre'
      AND rep.latitud_actual IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM oferta_asignacion o
          WHERE o.id_repartidor = rep.id_repartidor AND o.respuesta = 'pendiente'
      )
      AND NOT EXISTS (
          SELECT 1 FROM oferta_asignacion o
          WHERE o.id_repartidor = rep.id_repartidor
            AND o.id_pedido = p_id_pedido
            AND o.respuesta IN ('rechazada', 'expirada')
      )
    ORDER BY (rep.prioridad = 'baja'),
             fn_distancia_km(rep.latitud_actual, rep.longitud_actual, v_rest_lat, v_rest_lon),
             rep.calificacion_promedio DESC
    LIMIT 1
    FOR UPDATE OF rep SKIP LOCKED;

    IF v_id_repartidor IS NULL THEN
        RETURN NULL;
    END IF;

    INSERT INTO oferta_asignacion (id_pedido, id_repartidor, distancia_km)
    SELECT p_id_pedido, v_id_repartidor,
           fn_distancia_km(latitud_actual, longitud_actual, v_rest_lat, v_rest_lon)
    FROM repartidor WHERE id_repartidor = v_id_repartidor;

    RETURN v_id_repartidor;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_responder_oferta
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_responder_oferta(p_id_oferta INT, p_acepta BOOLEAN)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_respuesta      VARCHAR(10);
    v_id_pedido      INT;
    v_id_repartidor  INT;
BEGIN
    SELECT respuesta, id_pedido, id_repartidor
    INTO v_respuesta, v_id_pedido, v_id_repartidor
    FROM oferta_asignacion
    WHERE id_oferta = p_id_oferta;

    IF v_respuesta IS DISTINCT FROM 'pendiente' THEN
        RAISE EXCEPTION 'OFERTA_NO_PENDIENTE: se responde una oferta ya respondida o expirada';
    END IF;

    IF p_acepta THEN
        UPDATE oferta_asignacion
        SET respuesta = 'aceptada', fecha_respuesta = now()
        WHERE id_oferta = p_id_oferta;

        UPDATE pedido SET id_repartidor = v_id_repartidor WHERE id_pedido = v_id_pedido;
        UPDATE repartidor SET disponibilidad = 'ocupado' WHERE id_repartidor = v_id_repartidor;
        UPDATE pedido SET tiempo_estimado_min = fn_tiempo_estimado(v_id_pedido) WHERE id_pedido = v_id_pedido;

        RETURN v_id_repartidor;
    ELSE
        UPDATE oferta_asignacion
        SET respuesta = 'rechazada', fecha_respuesta = now()
        WHERE id_oferta = p_id_oferta;

        RETURN fn_asignar_repartidor(v_id_pedido);
    END IF;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_expirar_ofertas: el backend la llama cada 30 segundos.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_expirar_ofertas()
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_expira_seg  NUMERIC;
    v_cantidad    INT;
    v_pedido      RECORD;
BEGIN
    v_expira_seg := fn_param_num('oferta_expira_seg');

    WITH expiradas AS (
        UPDATE oferta_asignacion
        SET respuesta = 'expirada', fecha_respuesta = now()
        WHERE respuesta = 'pendiente'
          AND fecha_oferta < now() - (v_expira_seg || ' seconds')::INTERVAL
        RETURNING id_oferta
    )
    SELECT count(*) INTO v_cantidad FROM expiradas;

    FOR v_pedido IN
        SELECT p.id_pedido
        FROM pedido p
        WHERE p.id_estado IN (2, 3)
          AND p.id_repartidor IS NULL
          AND NOT EXISTS (
              SELECT 1 FROM oferta_asignacion o
              WHERE o.id_pedido = p.id_pedido AND o.respuesta = 'pendiente'
          )
    LOOP
        PERFORM fn_asignar_repartidor(v_pedido.id_pedido);
    END LOOP;

    RETURN v_cantidad;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_reasignar_pedido: uso del coordinador (RF-23).
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_reasignar_pedido(p_id_pedido INT, p_id_repartidor INT, p_id_usuario INT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_estado_actual        SMALLINT;
    v_repartidor_anterior  INT;
    v_disponibilidad       VARCHAR(12);
BEGIN
    SELECT id_estado, id_repartidor INTO v_estado_actual, v_repartidor_anterior
    FROM pedido WHERE id_pedido = p_id_pedido;

    -- roadmap_bd §6 solo permite reasignar en preparacion (2) o listo (3);
    -- se reutiliza TRANSICION_INVALIDA (codigo permitido mas cercano).
    IF v_estado_actual NOT IN (2, 3) THEN
        RAISE EXCEPTION 'TRANSICION_INVALIDA: solo se puede reasignar un pedido en preparacion o listo para retirar';
    END IF;

    IF v_repartidor_anterior IS NOT NULL THEN
        UPDATE repartidor SET disponibilidad = 'libre' WHERE id_repartidor = v_repartidor_anterior;
    END IF;

    UPDATE oferta_asignacion
    SET respuesta = 'expirada', fecha_respuesta = now()
    WHERE id_pedido = p_id_pedido AND respuesta = 'pendiente';

    UPDATE pedido SET id_repartidor = NULL WHERE id_pedido = p_id_pedido;

    IF p_id_repartidor IS NULL THEN
        PERFORM fn_asignar_repartidor(p_id_pedido);
    ELSE
        SELECT disponibilidad INTO v_disponibilidad FROM repartidor WHERE id_repartidor = p_id_repartidor;

        IF v_disponibilidad IS DISTINCT FROM 'libre' THEN
            RAISE EXCEPTION 'REPARTIDOR_NO_DISPONIBLE: reasignacion manual a un repartidor no libre';
        END IF;

        UPDATE pedido SET id_repartidor = p_id_repartidor WHERE id_pedido = p_id_pedido;
        UPDATE repartidor SET disponibilidad = 'ocupado' WHERE id_repartidor = p_id_repartidor;
        UPDATE pedido SET tiempo_estimado_min = fn_tiempo_estimado(p_id_pedido) WHERE id_pedido = p_id_pedido;
    END IF;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_registrar_ubicacion: p_latitud/p_longitud son DOUBLE PRECISION (no
-- NUMERIC) porque el backend y el simulador mandan floats de Python; el
-- INSERT hacia las columnas NUMERIC(9,6) hace el cast de asignacion solo.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_registrar_ubicacion(p_id_repartidor INT, p_latitud DOUBLE PRECISION, p_longitud DOUBLE PRECISION)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id_pedido INT;
BEGIN
    SELECT id_pedido INTO v_id_pedido
    FROM pedido
    WHERE id_repartidor = p_id_repartidor AND id_estado IN (2, 3, 4)
    ORDER BY fecha_creacion DESC
    LIMIT 1;

    INSERT INTO ubicacion_repartidor (id_repartidor, id_pedido, latitud, longitud)
    VALUES (p_id_repartidor, v_id_pedido, p_latitud, p_longitud);
END;
$$;
