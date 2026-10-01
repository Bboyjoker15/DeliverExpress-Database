-- ==========================================================================
-- DeliverExpress - 08_facturacion.sql
-- Integrante 1
-- Facturas al cliente, de comision, notas de credito, liquidaciones de
-- repartidor, inmutabilidad y vistas de facturacion. roadmap_bd.txt §8b.
-- Fuera de alcance: retenciones de IVA/ISLR, libro de compras, autorizacion
-- del SENIAT y PDF con validez legal.
-- ==========================================================================
SET search_path TO deliverexpress;

-- --------------------------------------------------------------------------
-- fn_siguiente_correlativo: numeracion SIN huecos. El UPDATE bloquea la
-- fila; si la transaccion falla, el numero vuelve con el ROLLBACK.
-- Facturas y notas de credito comparten la misma serie (simplificacion).
-- --------------------------------------------------------------------------
-- p_punto_venta es INT (no SMALLINT como correlativo.punto_venta): un
-- integer "normal" pasado desde pgAdmin o el backend no se convierte solo a
-- smallint al resolver la funcion.
CREATE OR REPLACE FUNCTION fn_siguiente_correlativo(p_punto_venta INT)
RETURNS TABLE (numero_factura VARCHAR, numero_control VARCHAR)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    UPDATE correlativo
    SET ultimo_numero = ultimo_numero + 1,
        ultimo_control = ultimo_control + 1
    WHERE punto_venta = p_punto_venta
    RETURNING
        (lpad(punto_venta::text, 4, '0') || '-' || lpad(ultimo_numero::text, 8, '0'))::VARCHAR,
        (lpad(punto_venta::text, 2, '0') || '-' || lpad(ultimo_control::text, 6, '0'))::VARCHAR;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_emitir_factura_cliente: factura automatica al entregar un pedido.
-- La linea de "Servicio de envio" absorbe el ajuste de centavos para que la
-- suma de las lineas cuadre exacto con iva_16 de la cabecera (= pedido.iva_total).
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_emitir_factura_cliente(p_id_pedido INT, p_fecha TIMESTAMPTZ DEFAULT now())
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_pedido             RECORD;
    v_correlativo        RECORD;
    v_punto_venta        SMALLINT;
    v_id_factura         INT;
    v_det                RECORD;
    v_iva_acumulado      NUMERIC := 0;
    v_iva_item           NUMERIC;
    v_base_imponible_16  NUMERIC;
    v_base_exenta        NUMERIC;
    v_monto_no_sujeto    NUMERIC := 0;
BEGIN
    SELECT p.*, c.nombre AS cliente_nombre, c.cedula_rif
    INTO v_pedido
    FROM pedido p JOIN cliente c ON c.id_cliente = p.id_cliente
    WHERE p.id_pedido = p_id_pedido;

    v_punto_venta := fn_param_num('punto_venta')::SMALLINT;
    SELECT * INTO v_correlativo FROM fn_siguiente_correlativo(v_punto_venta);

    SELECT COALESCE(SUM(dp.subtotal) FILTER (WHERE pr.exento_iva = FALSE), 0),
           COALESCE(SUM(dp.subtotal) FILTER (WHERE pr.exento_iva = TRUE), 0)
    INTO v_base_imponible_16, v_base_exenta
    FROM detalle_pedido dp JOIN producto pr ON pr.id_producto = dp.id_producto
    WHERE dp.id_pedido = p_id_pedido;

    v_base_imponible_16 := v_base_imponible_16 + v_pedido.costo_envio;

    IF v_pedido.propina > 0 THEN
        v_monto_no_sujeto := v_pedido.propina;
    END IF;

    INSERT INTO factura (
        tipo, numero_factura, numero_control, punto_venta, id_cliente, id_pedido,
        rif_emisor, razon_social_emisor, direccion_fiscal_emisor,
        rif_receptor, razon_social_receptor,
        moneda, tasa_bcv, base_imponible_16, base_exenta, monto_no_sujeto,
        iva_16, igtf, total, total_ves, fecha_emision
    ) VALUES (
        'factura_cliente', v_correlativo.numero_factura, v_correlativo.numero_control, v_punto_venta,
        v_pedido.id_cliente, p_id_pedido,
        (SELECT valor FROM parametro_sistema WHERE clave = 'emisor_rif'),
        (SELECT valor FROM parametro_sistema WHERE clave = 'emisor_razon_social'),
        (SELECT valor FROM parametro_sistema WHERE clave = 'emisor_direccion_fiscal'),
        v_pedido.cedula_rif, v_pedido.cliente_nombre,
        v_pedido.moneda_pago, v_pedido.tasa_bcv_aplicada,
        v_base_imponible_16, v_base_exenta, v_monto_no_sujeto,
        v_pedido.iva_total, v_pedido.igtf, v_pedido.total, v_pedido.total_ves, p_fecha
    )
    RETURNING id_factura INTO v_id_factura;

    -- Una linea por producto
    FOR v_det IN
        SELECT dp.id_producto, pr.nombre, dp.cantidad, dp.precio_unitario, dp.subtotal, pr.exento_iva
        FROM detalle_pedido dp JOIN producto pr ON pr.id_producto = dp.id_producto
        WHERE dp.id_pedido = p_id_pedido
        ORDER BY dp.id_producto
    LOOP
        IF v_det.exento_iva THEN
            v_iva_item := 0;
        ELSE
            v_iva_item := ROUND(v_det.subtotal * 0.16, 2);
            v_iva_acumulado := v_iva_acumulado + v_iva_item;
        END IF;

        INSERT INTO detalle_factura (
            id_factura, id_pedido, descripcion, cantidad, precio_unitario,
            alicuota_iva, no_sujeto, base_item, iva_item, subtotal_item
        ) VALUES (
            v_id_factura, p_id_pedido, v_det.nombre, v_det.cantidad, v_det.precio_unitario,
            CASE WHEN v_det.exento_iva THEN 0 ELSE 16 END, FALSE,
            v_det.subtotal, v_iva_item, v_det.subtotal + v_iva_item
        );
    END LOOP;

    -- "Servicio de envio": el iva_item se ajusta con lo que falte para que
    -- la suma de todas las lineas de 16% cuadre con v_pedido.iva_total.
    v_iva_item := v_pedido.iva_total - v_iva_acumulado;

    INSERT INTO detalle_factura (
        id_factura, id_pedido, descripcion, cantidad, precio_unitario,
        alicuota_iva, no_sujeto, base_item, iva_item, subtotal_item
    ) VALUES (
        v_id_factura, p_id_pedido, 'Servicio de envio', 1, v_pedido.costo_envio,
        16, FALSE, v_pedido.costo_envio, v_iva_item, v_pedido.costo_envio + v_iva_item
    );

    -- "Propina para el repartidor": no sujeta a IVA
    IF v_pedido.propina > 0 THEN
        INSERT INTO detalle_factura (
            id_factura, id_pedido, descripcion, cantidad, precio_unitario,
            alicuota_iva, no_sujeto, base_item, iva_item, subtotal_item
        ) VALUES (
            v_id_factura, p_id_pedido, 'Propina para el repartidor', 1, v_pedido.propina,
            0, TRUE, v_pedido.propina, 0, v_pedido.propina
        );
    END IF;

    -- IGTF: linea aparte (no es IVA, por eso alicuota 0) para que la suma de
    -- las lineas del detalle cuadre exacto con el total de la cabecera.
    IF v_pedido.igtf > 0 THEN
        INSERT INTO detalle_factura (
            id_factura, id_pedido, descripcion, cantidad, precio_unitario,
            alicuota_iva, no_sujeto, base_item, iva_item, subtotal_item
        ) VALUES (
            v_id_factura, p_id_pedido, 'IGTF 3%', 1, v_pedido.igtf,
            0, FALSE, v_pedido.igtf, 0, v_pedido.igtf
        );
    END IF;

    RETURN v_id_factura;
END;
$$;

-- --------------------------------------------------------------------------
-- trg_facturar_pedido: al entregar (estado 5), emite la factura sola
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_facturar_pedido()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_emitir_factura_cliente(NEW.id_pedido);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_facturar_pedido
    AFTER UPDATE OF id_estado ON pedido
    FOR EACH ROW
    WHEN (NEW.id_estado = 5)
    EXECUTE FUNCTION fn_trg_facturar_pedido();

-- --------------------------------------------------------------------------
-- fn_anular_factura: crea una nota de credito y marca la original 'anulada'
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_anular_factura(p_id_factura INT, p_motivo VARCHAR, p_id_usuario INT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_factura      RECORD;
    v_correlativo  RECORD;
    v_punto_venta  SMALLINT;
    v_id_nota      INT;
BEGIN
    SELECT * INTO v_factura FROM factura WHERE id_factura = p_id_factura;

    IF v_factura.tipo NOT IN ('factura_cliente', 'factura_comision') OR v_factura.estado <> 'emitida' THEN
        RAISE EXCEPTION 'FACTURA_YA_ANULADA: la factura ya esta anulada o es una nota de credito';
    END IF;

    v_punto_venta := fn_param_num('punto_venta')::SMALLINT;
    SELECT * INTO v_correlativo FROM fn_siguiente_correlativo(v_punto_venta);

    INSERT INTO factura (
        tipo, numero_factura, numero_control, punto_venta, estado,
        id_cliente, id_restaurante, id_pedido, id_factura_afectada,
        rif_emisor, razon_social_emisor, direccion_fiscal_emisor,
        rif_receptor, razon_social_receptor, direccion_fiscal_receptor,
        periodo_desde, periodo_hasta,
        moneda, tasa_bcv, base_imponible_16, base_exenta, monto_no_sujeto,
        iva_16, igtf, total, total_ves, observaciones, id_usuario
    ) VALUES (
        'nota_credito', v_correlativo.numero_factura, v_correlativo.numero_control, v_punto_venta, 'emitida',
        v_factura.id_cliente, v_factura.id_restaurante, v_factura.id_pedido, p_id_factura,
        v_factura.rif_emisor, v_factura.razon_social_emisor, v_factura.direccion_fiscal_emisor,
        v_factura.rif_receptor, v_factura.razon_social_receptor, v_factura.direccion_fiscal_receptor,
        v_factura.periodo_desde, v_factura.periodo_hasta,
        v_factura.moneda, v_factura.tasa_bcv, v_factura.base_imponible_16, v_factura.base_exenta,
        v_factura.monto_no_sujeto, v_factura.iva_16, v_factura.igtf, v_factura.total, v_factura.total_ves,
        p_motivo, p_id_usuario
    )
    RETURNING id_factura INTO v_id_nota;

    INSERT INTO detalle_factura (
        id_factura, id_pedido, descripcion, cantidad, precio_unitario,
        alicuota_iva, no_sujeto, base_item, iva_item, subtotal_item
    )
    SELECT v_id_nota, id_pedido, descripcion, cantidad, precio_unitario,
           alicuota_iva, no_sujeto, base_item, iva_item, subtotal_item
    FROM detalle_factura
    WHERE id_factura = p_id_factura;

    UPDATE factura SET estado = 'anulada' WHERE id_factura = p_id_factura;

    IF v_factura.tipo = 'factura_cliente' THEN
        UPDATE pago SET estado = 'reembolsado' WHERE id_pedido = v_factura.id_pedido;
    END IF;

    RETURN v_id_nota;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_generar_facturas_comision: una factura por restaurante y periodo, con
-- una linea por pedido entregado. iva_16 de la cabecera se define como la
-- SUMA de los iva_item ya redondeados por pedido (nunca al reves), para que
-- la cabecera y el detalle cuadren siempre exacto.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_generar_facturas_comision(p_desde DATE, p_hasta DATE, p_id_usuario INT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_rest               RECORD;
    v_punto_venta        SMALLINT;
    v_tasa_bcv           NUMERIC;
    v_correlativo        RECORD;
    v_id_factura         INT;
    v_base_imponible_16  NUMERIC;
    v_iva_16             NUMERIC;
    v_total              NUMERIC;
    v_total_ves          NUMERIC;
    v_creadas            INT := 0;
    v_ped                RECORD;
BEGIN
    v_punto_venta := fn_param_num('punto_venta')::SMALLINT;
    v_tasa_bcv    := fn_tasa_bcv(CURRENT_DATE);

    FOR v_rest IN
        SELECT DISTINCT r.id_restaurante, r.rif, r.razon_social, r.direccion_fiscal
        FROM restaurante r
        JOIN pedido p ON p.id_restaurante = r.id_restaurante
        WHERE p.id_estado = 5
          AND p.fecha_creacion::DATE BETWEEN p_desde AND p_hasta
          AND NOT EXISTS (
              SELECT 1 FROM factura f
              WHERE f.tipo = 'factura_comision' AND f.estado = 'emitida'
                AND f.id_restaurante = r.id_restaurante
                AND f.periodo_desde = p_desde AND f.periodo_hasta = p_hasta
          )
    LOOP
        SELECT SUM(comision_plataforma), SUM(ROUND(comision_plataforma * 0.16, 2))
        INTO v_base_imponible_16, v_iva_16
        FROM pedido
        WHERE id_restaurante = v_rest.id_restaurante
          AND id_estado = 5
          AND fecha_creacion::DATE BETWEEN p_desde AND p_hasta;

        v_total     := v_base_imponible_16 + v_iva_16;
        v_total_ves := ROUND(v_total * v_tasa_bcv, 2);

        SELECT * INTO v_correlativo FROM fn_siguiente_correlativo(v_punto_venta);

        INSERT INTO factura (
            tipo, numero_factura, numero_control, punto_venta,
            id_restaurante, periodo_desde, periodo_hasta,
            rif_emisor, razon_social_emisor, direccion_fiscal_emisor,
            rif_receptor, razon_social_receptor, direccion_fiscal_receptor,
            moneda, tasa_bcv, base_imponible_16, iva_16, igtf, total, total_ves, id_usuario
        ) VALUES (
            'factura_comision', v_correlativo.numero_factura, v_correlativo.numero_control, v_punto_venta,
            v_rest.id_restaurante, p_desde, p_hasta,
            (SELECT valor FROM parametro_sistema WHERE clave = 'emisor_rif'),
            (SELECT valor FROM parametro_sistema WHERE clave = 'emisor_razon_social'),
            (SELECT valor FROM parametro_sistema WHERE clave = 'emisor_direccion_fiscal'),
            v_rest.rif, v_rest.razon_social, v_rest.direccion_fiscal,
            'USD', v_tasa_bcv, v_base_imponible_16, v_iva_16, 0, v_total, v_total_ves, p_id_usuario
        )
        RETURNING id_factura INTO v_id_factura;

        FOR v_ped IN
            SELECT id_pedido, comision_plataforma
            FROM pedido
            WHERE id_restaurante = v_rest.id_restaurante
              AND id_estado = 5
              AND fecha_creacion::DATE BETWEEN p_desde AND p_hasta
            ORDER BY id_pedido
        LOOP
            INSERT INTO detalle_factura (
                id_factura, id_pedido, descripcion, cantidad, precio_unitario,
                alicuota_iva, no_sujeto, base_item, iva_item, subtotal_item
            ) VALUES (
                v_id_factura, v_ped.id_pedido,
                'Comision 15% pedido #' || v_ped.id_pedido,
                1, v_ped.comision_plataforma, 16, FALSE,
                v_ped.comision_plataforma, ROUND(v_ped.comision_plataforma * 0.16, 2),
                v_ped.comision_plataforma + ROUND(v_ped.comision_plataforma * 0.16, 2)
            );
        END LOOP;

        v_creadas := v_creadas + 1;
    END LOOP;

    RETURN v_creadas;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_generar_liquidaciones: pago periodico al repartidor (no es factura
-- fiscal). El id_liquidacion se saca de la secuencia ANTES del INSERT para
-- poder armar el numero LIQ-NNNNNNNN sin necesitar un UPDATE posterior (la
-- tabla es inmutable, ver trg_liquidacion_inmutable).
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_generar_liquidaciones(p_desde DATE, p_hasta DATE)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_rep             RECORD;
    v_id_liq          INT;
    v_numero          VARCHAR(12);
    v_viajes          INT;
    v_total_envios    NUMERIC;
    v_total_propinas  NUMERIC;
    v_creadas         INT := 0;
BEGIN
    FOR v_rep IN
        SELECT DISTINCT p.id_repartidor
        FROM pedido p
        WHERE p.id_estado = 5
          AND p.fecha_creacion::DATE BETWEEN p_desde AND p_hasta
          AND p.id_repartidor IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM detalle_liquidacion dl WHERE dl.id_pedido = p.id_pedido)
    LOOP
        SELECT COUNT(*), COALESCE(SUM(costo_envio), 0), COALESCE(SUM(propina), 0)
        INTO v_viajes, v_total_envios, v_total_propinas
        FROM pedido
        WHERE id_repartidor = v_rep.id_repartidor
          AND id_estado = 5
          AND fecha_creacion::DATE BETWEEN p_desde AND p_hasta
          AND id_pedido NOT IN (SELECT id_pedido FROM detalle_liquidacion);

        v_id_liq := nextval(pg_get_serial_sequence('liquidacion_repartidor', 'id_liquidacion'));
        v_numero := 'LIQ-' || lpad(v_id_liq::TEXT, 8, '0');

        INSERT INTO liquidacion_repartidor (
            id_liquidacion, numero, id_repartidor, periodo_desde, periodo_hasta,
            viajes, total_envios, total_propinas, total
        ) VALUES (
            v_id_liq, v_numero, v_rep.id_repartidor, p_desde, p_hasta,
            v_viajes, v_total_envios, v_total_propinas, v_total_envios + v_total_propinas
        );

        INSERT INTO detalle_liquidacion (id_liquidacion, id_pedido, costo_envio, propina)
        SELECT v_id_liq, id_pedido, costo_envio, propina
        FROM pedido
        WHERE id_repartidor = v_rep.id_repartidor
          AND id_estado = 5
          AND fecha_creacion::DATE BETWEEN p_desde AND p_hasta
          AND id_pedido NOT IN (SELECT id_pedido FROM detalle_liquidacion);

        v_creadas := v_creadas + 1;
    END LOOP;

    RETURN v_creadas;
END;
$$;

-- --------------------------------------------------------------------------
-- Inmutabilidad
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_factura_inmutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'FACTURA_INMUTABLE: no se puede borrar una factura';
    END IF;

    IF (to_jsonb(NEW) - 'estado') IS DISTINCT FROM (to_jsonb(OLD) - 'estado')
       OR NOT (OLD.estado = 'emitida' AND NEW.estado = 'anulada') THEN
        RAISE EXCEPTION 'FACTURA_INMUTABLE: solo se permite anular una factura emitida';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_factura_inmutable
    BEFORE UPDATE OR DELETE ON factura
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_factura_inmutable();

CREATE OR REPLACE FUNCTION fn_trg_detalle_factura_inmutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'FACTURA_INMUTABLE: el detalle de una factura no se puede modificar ni borrar';
END;
$$;

CREATE TRIGGER trg_detalle_factura_inmutable
    BEFORE UPDATE OR DELETE ON detalle_factura
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_detalle_factura_inmutable();

CREATE OR REPLACE FUNCTION fn_trg_liquidacion_inmutable()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'FACTURA_INMUTABLE: una liquidacion no se puede modificar ni borrar';
END;
$$;

CREATE TRIGGER trg_liquidacion_inmutable
    BEFORE UPDATE OR DELETE ON liquidacion_repartidor
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_liquidacion_inmutable();

CREATE TRIGGER trg_liquidacion_inmutable
    BEFORE UPDATE OR DELETE ON detalle_liquidacion
    FOR EACH ROW
    EXECUTE FUNCTION fn_trg_liquidacion_inmutable();

-- --------------------------------------------------------------------------
-- Vistas de facturacion (columnas = contrato con el backend)
-- --------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_libro_ventas AS
SELECT
    f.fecha_emision,
    f.tipo,
    f.numero_factura,
    f.numero_control,
    f.estado,
    fa.numero_factura AS numero_factura_afectada,
    f.rif_receptor,
    f.razon_social_receptor,
    f.moneda,
    f.tasa_bcv,
    CASE WHEN f.tipo = 'nota_credito' THEN -f.base_imponible_16 ELSE f.base_imponible_16 END AS base_imponible_16,
    CASE WHEN f.tipo = 'nota_credito' THEN -f.base_exenta ELSE f.base_exenta END AS base_exenta,
    CASE WHEN f.tipo = 'nota_credito' THEN -f.monto_no_sujeto ELSE f.monto_no_sujeto END AS monto_no_sujeto,
    CASE WHEN f.tipo = 'nota_credito' THEN -f.iva_16 ELSE f.iva_16 END AS iva_16,
    CASE WHEN f.tipo = 'nota_credito' THEN -f.igtf ELSE f.igtf END AS igtf,
    CASE WHEN f.tipo = 'nota_credito' THEN -f.total ELSE f.total END AS total,
    CASE WHEN f.tipo = 'nota_credito' THEN -f.total_ves ELSE f.total_ves END AS total_ves
FROM factura f
LEFT JOIN factura fa ON fa.id_factura = f.id_factura_afectada
ORDER BY f.fecha_emision;

CREATE OR REPLACE VIEW vw_resumen_iva_mensual AS
SELECT
    to_char(f.fecha_emision, 'YYYY-MM') AS periodo,
    COUNT(*) AS cantidad_documentos,
    SUM(CASE WHEN f.tipo = 'nota_credito' THEN -f.base_imponible_16 ELSE f.base_imponible_16 END) AS base_imponible_16,
    SUM(CASE WHEN f.tipo = 'nota_credito' THEN -f.base_exenta ELSE f.base_exenta END) AS base_exenta,
    SUM(CASE WHEN f.tipo = 'nota_credito' THEN -f.iva_16 ELSE f.iva_16 END) AS iva_debito,
    SUM(CASE WHEN f.tipo = 'nota_credito' THEN -f.igtf ELSE f.igtf END) AS igtf,
    SUM(CASE WHEN f.tipo = 'nota_credito' THEN -f.total ELSE f.total END) AS total,
    SUM(CASE WHEN f.tipo = 'nota_credito' THEN -f.total_ves ELSE f.total_ves END) AS total_ves
FROM factura f
GROUP BY to_char(f.fecha_emision, 'YYYY-MM')
ORDER BY periodo;

CREATE OR REPLACE VIEW vw_facturas AS
SELECT
    id_factura, tipo, numero_factura, numero_control, estado, fecha_emision,
    id_cliente, id_restaurante, id_pedido, razon_social_receptor, moneda, total, total_ves
FROM factura
ORDER BY fecha_emision DESC;
