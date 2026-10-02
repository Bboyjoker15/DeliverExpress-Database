-- ==========================================================================
-- DeliverExpress - pruebas_facturacion.sql
-- Pruebas manuales de facturacion (roadmap_bd.txt seccion 13). NO entra en
-- ejecutar_todo.sql. Ejecutar sobre una base ya cargada con
-- 10_datos_prueba.sql y revisar cada resultado contra lo que dice el
-- comentario.
-- ==========================================================================
SET search_path TO deliverexpress;

-- --------------------------------------------------------------------------
-- [1] Entregar un pedido -> se crea su factura_cliente con numero y control
-- correlativos
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_id_pedido INT;
BEGIN
    SELECT id_pedido INTO v_id_pedido FROM pedido WHERE id_estado = 4 LIMIT 1;
    IF v_id_pedido IS NOT NULL THEN
        PERFORM fn_cambiar_estado(v_id_pedido, 5::SMALLINT, NULL::INT);
        RAISE NOTICE 'Pedido % entregado. Revisar su factura mas abajo.', v_id_pedido;
    ELSE
        RAISE NOTICE 'No hay pedidos en estado 4 (en_camino) para esta prueba.';
    END IF;
END $$;

-- Resultado esperado: la ultima fila tiene numero_factura/numero_control
-- correlativos con la anterior (mismo punto_venta).
SELECT id_factura, numero_factura, numero_control, id_pedido
FROM factura
WHERE tipo = 'factura_cliente'
ORDER BY id_factura DESC
LIMIT 5;

-- --------------------------------------------------------------------------
-- [2] Suma de lineas del detalle = totales de la cabecera = totales del pedido
-- --------------------------------------------------------------------------
-- Resultado esperado: esta consulta NO devuelve filas (diferencia siempre 0).
SELECT
    f.id_factura,
    f.total AS total_factura,
    p.total AS total_pedido,
    SUM(df.subtotal_item) AS suma_detalle,
    f.total - SUM(df.subtotal_item) AS diferencia
FROM factura f
JOIN detalle_factura df ON df.id_factura = f.id_factura
JOIN pedido p ON p.id_pedido = f.id_pedido
WHERE f.tipo = 'factura_cliente'
GROUP BY f.id_factura, f.total, p.total
HAVING f.total <> p.total OR f.total - SUM(df.subtotal_item) <> 0;

-- --------------------------------------------------------------------------
-- [3] UPDATE o DELETE de una factura -> FACTURA_INMUTABLE
-- Ejecutar cada uno por separado y confirmar el error:
-- --------------------------------------------------------------------------
-- UPDATE factura SET total = 0
--   WHERE id_factura = (SELECT id_factura FROM factura WHERE tipo = 'factura_cliente' LIMIT 1);
-- DELETE FROM factura
--   WHERE id_factura = (SELECT id_factura FROM factura WHERE tipo = 'factura_cliente' LIMIT 1);

-- --------------------------------------------------------------------------
-- [4] Anular factura -> nota de credito, original 'anulada', pago
-- 'reembolsado'.  [5] Anular dos veces -> FACTURA_YA_ANULADA
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_id_factura INT;
    v_id_pedido  INT;
    v_id_nota    INT;
    v_id_admin   INT;
BEGIN
    SELECT id_usuario INTO v_id_admin FROM usuario WHERE email = 'admin@demo.com';

    SELECT id_factura, id_pedido INTO v_id_factura, v_id_pedido
    FROM factura WHERE tipo = 'factura_cliente' AND estado = 'emitida' LIMIT 1;

    IF v_id_factura IS NULL THEN
        RAISE NOTICE 'No hay facturas emitidas para esta prueba.';
        RETURN;
    END IF;

    v_id_nota := fn_anular_factura(v_id_factura, 'Prueba de anulacion', v_id_admin);
    RAISE NOTICE 'Factura % anulada. Nota de credito %. Pedido afectado: %.', v_id_factura, v_id_nota, v_id_pedido;

    BEGIN
        PERFORM fn_anular_factura(v_id_factura, 'Segundo intento', v_id_admin);
        RAISE NOTICE 'ERROR EN LA PRUEBA: se debio lanzar FACTURA_YA_ANULADA';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK: al anular dos veces se obtuvo -> %', SQLERRM;
    END;
END $$;

-- Revisar manualmente con los IDs que salieron por NOTICE:
--   SELECT estado FROM factura WHERE id_factura = <la original>;  -> 'anulada'
--   SELECT estado FROM pago WHERE id_pedido = <el pedido>;        -> 'reembolsado'

-- --------------------------------------------------------------------------
-- [6] Generar comisiones dos veces el mismo periodo -> la segunda crea 0
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_id_admin  INT;
    v_creadas_1 INT;
    v_creadas_2 INT;
BEGIN
    SELECT id_usuario INTO v_id_admin FROM usuario WHERE email = 'admin@demo.com';
    v_creadas_1 := fn_generar_facturas_comision(CURRENT_DATE - 120, CURRENT_DATE - 91, v_id_admin);
    v_creadas_2 := fn_generar_facturas_comision(CURRENT_DATE - 120, CURRENT_DATE - 91, v_id_admin);
    RAISE NOTICE 'Primera corrida: % facturas. Segunda corrida (debe ser 0): %', v_creadas_1, v_creadas_2;
END $$;

-- --------------------------------------------------------------------------
-- [7] Generar liquidaciones dos veces -> la segunda crea 0
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_creadas_1 INT;
    v_creadas_2 INT;
BEGIN
    v_creadas_1 := fn_generar_liquidaciones(CURRENT_DATE - 120, CURRENT_DATE - 91);
    v_creadas_2 := fn_generar_liquidaciones(CURRENT_DATE - 120, CURRENT_DATE - 91);
    RAISE NOTICE 'Primera corrida: % liquidaciones. Segunda corrida (debe ser 0): %', v_creadas_1, v_creadas_2;
END $$;

-- --------------------------------------------------------------------------
-- [8] Dos facturas a la vez en dos ventanas: numeros seguidos, sin huecos ni
-- repetidos (concurrencia sobre correlativo). Prueba MANUAL con dos Query
-- Tool de pgAdmin:
--   Ventana A: BEGIN; SELECT * FROM fn_siguiente_correlativo(1);
--              (no hacer COMMIT todavia: la fila de correlativo queda bloqueada)
--   Ventana B: BEGIN; SELECT * FROM fn_siguiente_correlativo(1);
--              (se queda esperando)
--   Ventana A: COMMIT;
--   Ventana B: (continua sola y devuelve el siguiente numero) COMMIT;
-- Resultado esperado: los dos numeros son consecutivos, ninguno se repite.
-- --------------------------------------------------------------------------

-- --------------------------------------------------------------------------
-- [9] Libro de ventas: la nota de credito resta
-- --------------------------------------------------------------------------
-- Resultado esperado: las filas con tipo = 'nota_credito' tienen total NEGATIVO.
SELECT tipo, numero_factura, numero_factura_afectada, total
FROM vw_libro_ventas
WHERE tipo IN ('factura_cliente', 'nota_credito')
ORDER BY fecha_emision DESC
LIMIT 10;
