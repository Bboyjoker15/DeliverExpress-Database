-- ==========================================================================
-- DeliverExpress - pruebas_funciones.sql
-- Integrante 1 (asumido: el Integrante 2 no se presento al equipo).
-- Pruebas de las funciones de 03-06, originalmente a cargo del Integrante 2
-- (roadmap_bd.txt seccion 13). NO entra en ejecutar_todo.sql. Ejecutar sobre
-- una base ya cargada con 10_datos_prueba.sql.
-- ==========================================================================
SET search_path TO deliverexpress;

-- --------------------------------------------------------------------------
-- [1] Crear pedido valido
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_id_cliente     INT;
    v_id_direccion   INT;
    v_id_zona        INT;
    v_id_restaurante INT;
    v_productos      JSONB;
    v_id_pedido      INT;
BEGIN
    SELECT dc.id_cliente, dc.id_direccion, dc.id_zona INTO v_id_cliente, v_id_direccion, v_id_zona
    FROM direccion_cliente dc ORDER BY random() LIMIT 1;

    SELECT r.id_restaurante INTO v_id_restaurante
    FROM restaurante r JOIN restaurante_zona rz ON rz.id_restaurante = r.id_restaurante
    WHERE rz.id_zona = v_id_zona ORDER BY random() LIMIT 1;

    SELECT jsonb_agg(jsonb_build_object('id_producto', id_producto, 'cantidad', 1))
    INTO v_productos
    FROM (SELECT id_producto FROM producto WHERE id_restaurante = v_id_restaurante AND disponible LIMIT 2) s;

    v_id_pedido := fn_crear_pedido(v_id_cliente, v_id_restaurante, v_id_direccion, v_productos, 1, 'USD', '1234');
    RAISE NOTICE 'OK [1]: pedido % creado', v_id_pedido;
END $$;

-- --------------------------------------------------------------------------
-- [2] Crear pedido con restaurante cerrado -> RESTAURANTE_NO_DISPONIBLE
-- (se cierra un restaurante de prueba temporalmente)
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_id_restaurante INT;
    v_id_direccion   INT;
    v_id_cliente     INT;
    v_productos      JSONB;
BEGIN
    SELECT id_restaurante INTO v_id_restaurante FROM restaurante ORDER BY random() LIMIT 1;
    UPDATE restaurante SET activo = FALSE WHERE id_restaurante = v_id_restaurante;

    SELECT id_cliente, id_direccion INTO v_id_cliente, v_id_direccion FROM direccion_cliente LIMIT 1;
    SELECT jsonb_agg(jsonb_build_object('id_producto', id_producto, 'cantidad', 1))
    INTO v_productos FROM (SELECT id_producto FROM producto WHERE id_restaurante = v_id_restaurante LIMIT 1) s;

    BEGIN
        PERFORM fn_crear_pedido(v_id_cliente, v_id_restaurante, v_id_direccion, v_productos, 0, 'USD', '1234');
        RAISE NOTICE 'ERROR EN LA PRUEBA [2]: no lanzo RESTAURANTE_NO_DISPONIBLE';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK [2]: %', SQLERRM;
    END;

    UPDATE restaurante SET activo = TRUE WHERE id_restaurante = v_id_restaurante;
END $$;

-- --------------------------------------------------------------------------
-- [3] Crear pedido con una direccion fuera de las zonas que cubre el
-- restaurante -> RESTAURANTE_NO_DISPONIBLE
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_id_restaurante INT;
    v_id_direccion   INT;
    v_id_cliente     INT;
    v_productos      JSONB;
BEGIN
    SELECT r.id_restaurante INTO v_id_restaurante FROM restaurante r ORDER BY random() LIMIT 1;

    SELECT dc.id_cliente, dc.id_direccion INTO v_id_cliente, v_id_direccion
    FROM direccion_cliente dc
    WHERE dc.id_zona NOT IN (SELECT id_zona FROM restaurante_zona WHERE id_restaurante = v_id_restaurante)
    LIMIT 1;

    SELECT jsonb_agg(jsonb_build_object('id_producto', id_producto, 'cantidad', 1))
    INTO v_productos FROM (SELECT id_producto FROM producto WHERE id_restaurante = v_id_restaurante LIMIT 1) s;

    BEGIN
        PERFORM fn_crear_pedido(v_id_cliente, v_id_restaurante, v_id_direccion, v_productos, 0, 'USD', '1234');
        RAISE NOTICE 'ERROR EN LA PRUEBA [3]: no lanzo RESTAURANTE_NO_DISPONIBLE';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK [3]: %', SQLERRM;
    END;
END $$;

-- --------------------------------------------------------------------------
-- [4] Producto de otro restaurante -> PRODUCTO_INVALIDO
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_id_restaurante_a INT;
    v_id_restaurante_b INT;
    v_id_producto_b    INT;
    v_id_cliente       INT;
    v_id_direccion     INT;
    v_id_zona          INT;
    v_productos        JSONB;
BEGIN
    SELECT dc.id_cliente, dc.id_direccion, dc.id_zona INTO v_id_cliente, v_id_direccion, v_id_zona
    FROM direccion_cliente dc ORDER BY random() LIMIT 1;

    SELECT r.id_restaurante INTO v_id_restaurante_a
    FROM restaurante r JOIN restaurante_zona rz ON rz.id_restaurante = r.id_restaurante
    WHERE rz.id_zona = v_id_zona ORDER BY random() LIMIT 1;

    SELECT id_producto, id_restaurante INTO v_id_producto_b, v_id_restaurante_b
    FROM producto WHERE id_restaurante <> v_id_restaurante_a ORDER BY random() LIMIT 1;

    v_productos := jsonb_build_array(jsonb_build_object('id_producto', v_id_producto_b, 'cantidad', 1));

    BEGIN
        PERFORM fn_crear_pedido(v_id_cliente, v_id_restaurante_a, v_id_direccion, v_productos, 0, 'USD', '1234');
        RAISE NOTICE 'ERROR EN LA PRUEBA [4]: no lanzo PRODUCTO_INVALIDO';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK [4]: %', SQLERRM;
    END;
END $$;

-- --------------------------------------------------------------------------
-- [5] Saltar de recibido a entregado -> TRANSICION_INVALIDA
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_id_pedido INT;
BEGIN
    SELECT id_pedido INTO v_id_pedido FROM pedido WHERE id_estado = 1 LIMIT 1;

    IF v_id_pedido IS NULL THEN
        RAISE NOTICE 'No hay pedidos en estado 1 para esta prueba.';
        RETURN;
    END IF;

    BEGIN
        PERFORM fn_cambiar_estado(v_id_pedido, 5::SMALLINT, NULL::INT);
        RAISE NOTICE 'ERROR EN LA PRUEBA [5]: no lanzo TRANSICION_INVALIDA';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK [5]: %', SQLERRM;
    END;
END $$;

-- --------------------------------------------------------------------------
-- [6] Pasar a en_camino sin repartidor -> REPARTIDOR_NO_ASIGNADO
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_id_pedido INT;
BEGIN
    SELECT id_pedido INTO v_id_pedido FROM pedido
    WHERE id_estado = 3 AND id_repartidor IS NULL LIMIT 1;

    IF v_id_pedido IS NULL THEN
        RAISE NOTICE 'No hay un pedido en estado 3 sin repartidor para esta prueba.';
        RETURN;
    END IF;

    BEGIN
        PERFORM fn_cambiar_estado(v_id_pedido, 4::SMALLINT, NULL::INT);
        RAISE NOTICE 'ERROR EN LA PRUEBA [6]: no lanzo REPARTIDOR_NO_ASIGNADO';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK [6]: %', SQLERRM;
    END;
END $$;

-- --------------------------------------------------------------------------
-- [7] Aceptar pedido -> se crea oferta al repartidor mas cercano
-- [8] Rechazar oferta -> pasa al siguiente candidato
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_id_pedido INT;
    v_id_oferta INT;
BEGIN
    SELECT id_pedido INTO v_id_pedido FROM pedido WHERE id_estado = 1 LIMIT 1;
    IF v_id_pedido IS NULL THEN
        RAISE NOTICE 'No hay pedidos en estado 1 para esta prueba.';
        RETURN;
    END IF;

    PERFORM fn_cambiar_estado(v_id_pedido, 2::SMALLINT, NULL::INT);

    SELECT id_oferta INTO v_id_oferta FROM oferta_asignacion
    WHERE id_pedido = v_id_pedido AND respuesta = 'pendiente';

    IF v_id_oferta IS NULL THEN
        RAISE NOTICE 'No se genero oferta (puede que no haya repartidores libres en esa zona).';
        RETURN;
    END IF;
    RAISE NOTICE 'OK [7]: oferta % creada para el pedido %', v_id_oferta, v_id_pedido;

    PERFORM fn_responder_oferta(v_id_oferta, FALSE);
    RAISE NOTICE 'OK [8]: revisar oferta_asignacion para el pedido % (debe haber una nueva oferta pendiente si habia otro candidato)', v_id_pedido;
END $$;

SELECT id_oferta, id_repartidor, respuesta, fecha_oferta
FROM oferta_asignacion
ORDER BY id_oferta DESC
LIMIT 5;

-- --------------------------------------------------------------------------
-- [9] Rechazar muchas veces -> prioridad 'baja'
-- (se simula forzando varias ofertas 'rechazada' seguidas de un repartidor)
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_id_repartidor INT;
    v_id_pedido     INT;
    i INT;
BEGIN
    SELECT id_repartidor INTO v_id_repartidor FROM repartidor WHERE prioridad = 'normal' LIMIT 1;
    SELECT id_pedido INTO v_id_pedido FROM pedido LIMIT 1;

    FOR i IN 1..8 LOOP
        INSERT INTO oferta_asignacion (id_pedido, id_repartidor, distancia_km, respuesta, fecha_respuesta)
        VALUES (v_id_pedido, v_id_repartidor, 1, 'rechazada', now());
    END LOOP;

    RAISE NOTICE 'OK [9]: revisar repartidor % (deberia quedar en prioridad baja)', v_id_repartidor;
END $$;

SELECT id_repartidor, prioridad FROM repartidor WHERE id_repartidor = (
    SELECT id_repartidor FROM oferta_asignacion ORDER BY id_oferta DESC LIMIT 1
);

-- --------------------------------------------------------------------------
-- [10] Entregar -> repartidor vuelve a 'libre', historial con 5 filas
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_id_pedido     INT;
    v_id_repartidor INT;
BEGIN
    SELECT id_pedido, id_repartidor INTO v_id_pedido, v_id_repartidor
    FROM pedido WHERE id_estado = 4 AND id_repartidor IS NOT NULL LIMIT 1;

    IF v_id_pedido IS NULL THEN
        RAISE NOTICE 'No hay un pedido en estado 4 con repartidor para esta prueba.';
        RETURN;
    END IF;

    PERFORM fn_cambiar_estado(v_id_pedido, 5::SMALLINT, NULL::INT);

    RAISE NOTICE 'OK [10]: pedido % entregado, repartidor %', v_id_pedido, v_id_repartidor;
END $$;

-- Revisar manualmente con los IDs del NOTICE:
--   SELECT disponibilidad FROM repartidor WHERE id_repartidor = <el de arriba>;  -> 'libre'
--   SELECT count(*) FROM historial_estado_pedido WHERE id_pedido = <el pedido>; -> 5

-- --------------------------------------------------------------------------
-- [11] Calificar pedido no entregado -> CALIFICACION_NO_PERMITIDA
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_id_pedido INT;
BEGIN
    SELECT id_pedido INTO v_id_pedido FROM pedido WHERE id_estado <> 5 LIMIT 1;

    BEGIN
        PERFORM fn_calificar(v_id_pedido, 'cliente_a_restaurante', 5, NULL);
        RAISE NOTICE 'ERROR EN LA PRUEBA [11]: no lanzo CALIFICACION_NO_PERMITIDA';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK [11]: %', SQLERRM;
    END;
END $$;

-- --------------------------------------------------------------------------
-- [12] Calificar dos veces el mismo tipo -> CALIFICACION_NO_PERMITIDA
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_id_pedido INT;
BEGIN
    -- Un pedido entregado que TODAVIA no tenga calificacion cliente_a_restaurante
    -- (10_datos_prueba.sql ya califico la mayoria de los pedidos historicos).
    SELECT p.id_pedido INTO v_id_pedido
    FROM pedido p
    WHERE p.id_estado = 5
      AND NOT EXISTS (
          SELECT 1 FROM calificacion c
          WHERE c.id_pedido = p.id_pedido AND c.tipo = 'cliente_a_restaurante'
      )
    LIMIT 1;

    IF v_id_pedido IS NULL THEN
        RAISE NOTICE 'No hay un pedido entregado sin calificar para esta prueba.';
        RETURN;
    END IF;

    PERFORM fn_calificar(v_id_pedido, 'cliente_a_restaurante', 5, 'Primera calificacion');

    BEGIN
        PERFORM fn_calificar(v_id_pedido, 'cliente_a_restaurante', 4, 'Segunda calificacion');
        RAISE NOTICE 'ERROR EN LA PRUEBA [12]: no lanzo CALIFICACION_NO_PERMITIDA';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK [12]: %', SQLERRM;
    END;
END $$;

-- --------------------------------------------------------------------------
-- [13] 10 calificaciones de 2 -> repartidor en_revision
-- --------------------------------------------------------------------------
DO $$
DECLARE
    v_id_repartidor INT;
    v_pedido        RECORD;
    v_creadas       INT := 0;
BEGIN
    -- El repartidor con mas pedidos entregados SIN calificacion cliente_a_repartidor
    -- todavia, para poder insertar hasta 10 calificaciones nuevas de verdad.
    SELECT p.id_repartidor INTO v_id_repartidor
    FROM pedido p
    WHERE p.id_estado = 5 AND p.id_repartidor IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM calificacion c
          WHERE c.id_pedido = p.id_pedido AND c.tipo = 'cliente_a_repartidor'
      )
    GROUP BY p.id_repartidor
    ORDER BY count(*) DESC
    LIMIT 1;

    FOR v_pedido IN
        SELECT p.id_pedido FROM pedido p
        WHERE p.id_estado = 5 AND p.id_repartidor = v_id_repartidor
          AND NOT EXISTS (
              SELECT 1 FROM calificacion c
              WHERE c.id_pedido = p.id_pedido AND c.tipo = 'cliente_a_repartidor'
          )
        LIMIT 10
    LOOP
        BEGIN
            PERFORM fn_calificar(v_pedido.id_pedido, 'cliente_a_repartidor', 2, 'Mal servicio');
            v_creadas := v_creadas + 1;
        EXCEPTION WHEN OTHERS THEN
            NULL; -- puede que ya tuviera calificacion de ese tipo
        END;
    END LOOP;

    RAISE NOTICE 'OK [13]: % calificaciones de 2 creadas para el repartidor %', v_creadas, v_id_repartidor;
END $$;

SELECT id_repartidor, calificacion_promedio, total_calificaciones, en_revision
FROM repartidor
ORDER BY total_calificaciones DESC
LIMIT 5;

-- --------------------------------------------------------------------------
-- [14] Concurrencia: dos ventanas asignan a la vez, no toman al mismo
-- repartidor. Prueba MANUAL con dos Query Tool de pgAdmin:
--   Crear dos pedidos nuevos en estado 1 que cubran la MISMA zona.
--   Ventana A: BEGIN; SELECT fn_asignar_repartidor(<id_pedido_A>);
--              (no hacer COMMIT todavia)
--   Ventana B: BEGIN; SELECT fn_asignar_repartidor(<id_pedido_B>);
--              (con SKIP LOCKED, NO deberia esperar: toma al SIGUIENTE
--               candidato disponible en vez de bloquearse)
--   Ventana A: COMMIT;  Ventana B: COMMIT;
-- Resultado esperado: id_repartidor devuelto en A es distinto al de B.
-- --------------------------------------------------------------------------

-- --------------------------------------------------------------------------
-- [15] Pedido pagado en USD -> igtf > 0; en VES -> igtf = 0
-- --------------------------------------------------------------------------
SELECT moneda_pago, count(*) AS pedidos, count(*) FILTER (WHERE igtf > 0) AS con_igtf
FROM pedido
GROUP BY moneda_pago;
-- Resultado esperado: USD tiene con_igtf = pedidos (todos); VES tiene con_igtf = 0.

-- --------------------------------------------------------------------------
-- [16] Sin ninguna tasa BCV cargada -> TASA_BCV_NO_REGISTRADA
-- (se prueba con una fecha bien vieja, anterior a cualquier tasa cargada)
-- --------------------------------------------------------------------------
DO $$
BEGIN
    BEGIN
        PERFORM fn_tasa_bcv('1900-01-01'::DATE);
        RAISE NOTICE 'ERROR EN LA PRUEBA [16]: no lanzo TASA_BCV_NO_REGISTRADA';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'OK [16]: %', SQLERRM;
    END;
END $$;
