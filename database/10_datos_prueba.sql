-- ==========================================================================
-- DeliverExpress - 10_datos_prueba.sql
-- Integrante 1 (+ 3)
-- Datos de prueba: usuarios reales del cliente (20 restaurantes, 35
-- repartidores, 3 coordinadores, 50 clientes), tasas BCV, ~500 pedidos
-- historicos de los ultimos 60 dias (con historial, ofertas, calificaciones
-- y facturas), facturas de comision, liquidaciones, un par de notas de
-- credito, y ~10 pedidos activos para la demo. roadmap_bd.txt seccion 11.
--
-- NOTA: este script genera datos ALEATORIOS dentro de reglas de negocio
-- validas. Si al ejecutarlo aparece algun error, revisenlo entre los dos:
-- probablemente hace falta ajustar un rango aleatorio o un caso limite.
-- ==========================================================================
SET search_path TO deliverexpress;

-- ==========================================================================
-- A. Usuarios y perfiles (contrasenia demo1234 para todos)
-- ==========================================================================

-- Admin
DO $$
BEGIN
    PERFORM fn_registrar_usuario('admin@demo.com', 'demo1234', 'admin');
END $$;

-- Coordinadores (3)
DO $$
DECLARE
    v_id_usuario INT;
    i INT;
BEGIN
    FOR i IN 1..3 LOOP
        v_id_usuario := fn_registrar_usuario('coord' || lpad(i::text, 2, '0') || '@demo.com', 'demo1234', 'coordinador');
        INSERT INTO coordinador (id_usuario, nombre, telefono)
        VALUES (v_id_usuario, 'Coordinador ' || i, '0412-' || (1000000 + i)::text);
    END LOOP;
END $$;

-- Restaurantes (20), con horario, zonas de cobertura y menu
DO $$
DECLARE
    v_nombres TEXT[] := ARRAY[
        'La Arepa Dorada','Pizza Bella','Parrilla El Fogon','Sabor Criollo','Sushi Nippon',
        'Pollos a la Brasa Dona Rosa','El Rincon Guayanes','Pizzeria Napoli','Parrillera Los Llanos',
        'Comedor Criollo Mama Chepa','Sushi Sakura','Pollo Real','Arepera La Guayanesa',
        'Postres Dulce Tentacion','Pizza Loca','Parrilla del Este','Sabores de Casa',
        'Rollos y Sushi Bar','El Buen Pollo','Postres La Reposteria'
    ];
    v_platos TEXT[] := ARRAY[
        'Pabellon criollo','Arepa sencilla','Pizza margarita','Pizza pepperoni','Parrilla mixta',
        'Pollo asado a la brasa','Combo de sushi variado','Rollos california','Hamburguesa clasica',
        'Perro caliente especial','Pan casero','Agua mineral','Torta de chocolate','Quesillo','Ensalada cesar'
    ];
    v_zona_centro    RECORD;
    v_id_usuario     INT;
    v_id_restaurante INT;
    v_lat            NUMERIC;
    v_lon            NUMERIC;
    v_num_zonas      INT;
    v_num_productos  INT;
    v_precio         NUMERIC;
    v_nombre_prod    TEXT;
    i INT;
    j INT;
    v_dia INT;
BEGIN
    FOR i IN 1..20 LOOP
        SELECT id_zona, latitud_centro, longitud_centro INTO v_zona_centro
        FROM zona ORDER BY random() LIMIT 1;

        v_lat := v_zona_centro.latitud_centro + (random() - 0.5) * 0.01;
        v_lon := v_zona_centro.longitud_centro + (random() - 0.5) * 0.01;

        v_id_usuario := fn_registrar_usuario('rest' || lpad(i::text, 2, '0') || '@demo.com', 'demo1234', 'restaurante');

        INSERT INTO restaurante (
            id_usuario, id_categoria, nombre, direccion, telefono, latitud, longitud,
            tiempo_prep_min, rif, razon_social, direccion_fiscal
        ) VALUES (
            v_id_usuario, ((i - 1) % 8) + 1, v_nombres[i],
            'Av. Principal, sector cercano, Puerto Ordaz', '0412-' || (5000000 + i)::text,
            v_lat, v_lon, 15 + (i % 5) * 5,
            'J-' || lpad((30000000 + i)::text, 8, '0') || '-' || (i % 10)::text,
            v_nombres[i] || ' C.A.',
            'Av. Principal, sector cercano, Puerto Ordaz, estado Bolivar'
        )
        RETURNING id_restaurante INTO v_id_restaurante;

        FOR v_dia IN 0..6 LOOP
            INSERT INTO horario_restaurante (id_restaurante, dia_semana, hora_apertura, hora_cierre)
            VALUES (v_id_restaurante, v_dia, '08:00', '23:00');
        END LOOP;

        v_num_zonas := 2 + floor(random() * 3)::INT;
        INSERT INTO restaurante_zona (id_restaurante, id_zona)
        SELECT v_id_restaurante, id_zona FROM (
            SELECT id_zona FROM zona ORDER BY random() LIMIT v_num_zonas
        ) sub;

        v_num_productos := 8 + floor(random() * 3)::INT;
        FOR j IN 1..v_num_productos LOOP
            v_nombre_prod := v_platos[((j - 1 + i) % array_length(v_platos, 1)) + 1];
            v_precio := round((3 + random() * 17)::NUMERIC, 2);
            INSERT INTO producto (id_restaurante, nombre, descripcion, precio, exento_iva)
            VALUES (
                v_id_restaurante, v_nombre_prod, 'Preparado en ' || v_nombres[i], v_precio,
                v_nombre_prod IN ('Arepa sencilla', 'Pan casero', 'Agua mineral')
            );
        END LOOP;
    END LOOP;
END $$;

-- Repartidores (35), repartidos en las 8 zonas, con ubicacion inicial
DO $$
DECLARE
    v_zonas        INT[];
    v_id_zona      INT;
    v_id_usuario   INT;
    v_zona_centro  RECORD;
    v_lat          NUMERIC;
    v_lon          NUMERIC;
    v_vehiculo     TEXT;
    i INT;
BEGIN
    SELECT array_agg(id_zona ORDER BY id_zona) INTO v_zonas FROM zona;

    FOR i IN 1..35 LOOP
        v_id_zona := v_zonas[((i - 1) % array_length(v_zonas, 1)) + 1];

        SELECT latitud_centro, longitud_centro INTO v_zona_centro FROM zona WHERE id_zona = v_id_zona;

        v_lat := v_zona_centro.latitud_centro + (random() - 0.5) * 0.01;
        v_lon := v_zona_centro.longitud_centro + (random() - 0.5) * 0.01;

        v_vehiculo := (ARRAY['bicicleta', 'moto', 'moto', 'auto'])[1 + floor(random() * 4)::INT];

        v_id_usuario := fn_registrar_usuario('rep' || lpad(i::text, 2, '0') || '@demo.com', 'demo1234', 'repartidor');

        INSERT INTO repartidor (
            id_usuario, id_zona, nombre, telefono, cedula, tipo_vehiculo,
            disponibilidad, latitud_actual, longitud_actual, ubicacion_actualizada_en
        ) VALUES (
            v_id_usuario, v_id_zona, 'Repartidor ' || i, '0414-' || (6000000 + i)::text,
            'V-' || (10000000 + i)::text, v_vehiculo, 'libre', v_lat, v_lon, now()
        );
    END LOOP;
END $$;

-- Clientes (50), 1 o 2 direcciones cada uno, mitad con cedula_rif
DO $$
DECLARE
    v_id_usuario    INT;
    v_id_cliente    INT;
    v_cedula_rif    VARCHAR(12);
    v_num_direcc    INT;
    v_zona_centro   RECORD;
    v_lat           NUMERIC;
    v_lon           NUMERIC;
    i INT;
    j INT;
BEGIN
    FOR i IN 1..50 LOOP
        v_cedula_rif := CASE WHEN i % 2 = 0 THEN 'V-' || (20000000 + i)::text ELSE NULL END;

        v_id_usuario := fn_registrar_usuario('cliente' || lpad(i::text, 2, '0') || '@demo.com', 'demo1234', 'cliente');

        INSERT INTO cliente (id_usuario, nombre, telefono, cedula_rif)
        VALUES (v_id_usuario, 'Cliente ' || i, '0424-' || (7000000 + i)::text, v_cedula_rif)
        RETURNING id_cliente INTO v_id_cliente;

        v_num_direcc := 1 + (i % 2);

        FOR j IN 1..v_num_direcc LOOP
            SELECT id_zona, latitud_centro, longitud_centro INTO v_zona_centro
            FROM zona ORDER BY random() LIMIT 1;

            v_lat := v_zona_centro.latitud_centro + (random() - 0.5) * 0.012;
            v_lon := v_zona_centro.longitud_centro + (random() - 0.5) * 0.012;

            INSERT INTO direccion_cliente (id_cliente, id_zona, direccion, referencia, latitud, longitud, principal)
            VALUES (
                v_id_cliente, v_zona_centro.id_zona,
                'Calle ' || j || ', Puerto Ordaz', 'Cerca de un punto de referencia conocido',
                v_lat, v_lon, (j = 1)
            );
        END LOOP;
    END LOOP;
END $$;

-- ==========================================================================
-- B. Tasas BCV de los ultimos 60 dias (ANTES de crear pedidos) + la de hoy
-- ==========================================================================
DO $$
DECLARE
    v_id_admin INT;
    v_tasa     NUMERIC := 36.0;
    d          DATE;
BEGIN
    SELECT id_usuario INTO v_id_admin FROM usuario WHERE email = 'admin@demo.com';

    FOR d IN SELECT generate_series(CURRENT_DATE - 60, CURRENT_DATE, '1 day')::DATE LOOP
        v_tasa := v_tasa + (random() * 0.6 - 0.1);
        INSERT INTO tasa_bcv (fecha, tasa_usd, id_usuario)
        VALUES (d, round(v_tasa, 4), v_id_admin)
        ON CONFLICT (fecha) DO NOTHING;
    END LOOP;
END $$;

-- ==========================================================================
-- C. ~500 pedidos historicos de los ultimos 60 dias (triggers desactivados
-- SOLO en este bloque, para poder poner fechas pasadas)
-- ==========================================================================
DO $$
DECLARE
    v_id_pedido         INT;
    v_fecha_creacion    TIMESTAMPTZ;
    v_id_cliente        INT;
    v_id_direccion      INT;
    v_zona_cliente      INT;
    v_lat_dir           NUMERIC;
    v_lon_dir           NUMERIC;
    v_id_restaurante    INT;
    v_lat_rest          NUMERIC;
    v_lon_rest          NUMERIC;
    v_distancia         NUMERIC;
    v_costo_envio       NUMERIC;
    v_subtotal          NUMERIC;
    v_base_16           NUMERIC;
    v_iva_total         NUMERIC;
    v_igtf              NUMERIC;
    v_propina           NUMERIC;
    v_moneda            CHAR(3);
    v_tasa_bcv          NUMERIC;
    v_total             NUMERIC;
    v_total_ves         NUMERIC;
    v_comision          NUMERIC;
    v_monto_restaurante NUMERIC;
    v_id_estado_final   SMALLINT;
    v_es_cancelado      BOOLEAN;
    v_id_repartidor     INT;
    v_num_productos     INT;
    v_producto          RECORD;
    v_t                 TIMESTAMPTZ;
    v_puntaje           SMALLINT;
    i INT;
    j INT;
BEGIN
    SET session_replication_role = replica;

    CREATE TEMP TABLE tmp_lineas (id_producto INT, cantidad INT, precio NUMERIC, exento BOOLEAN) ON COMMIT DROP;

    FOR i IN 1..500 LOOP
        BEGIN
            v_id_restaurante := NULL;
            v_id_repartidor  := NULL;
            TRUNCATE tmp_lineas;

            SELECT dc.id_cliente, dc.id_direccion, dc.id_zona, dc.latitud, dc.longitud
            INTO v_id_cliente, v_id_direccion, v_zona_cliente, v_lat_dir, v_lon_dir
            FROM direccion_cliente dc
            ORDER BY random() LIMIT 1;

            SELECT r.id_restaurante, r.latitud, r.longitud
            INTO v_id_restaurante, v_lat_rest, v_lon_rest
            FROM restaurante r
            JOIN restaurante_zona rz ON rz.id_restaurante = r.id_restaurante
            WHERE rz.id_zona = v_zona_cliente
            ORDER BY fn_distancia_km(r.latitud, r.longitud, v_lat_dir, v_lon_dir)
            LIMIT 3
            OFFSET floor(random() * 3)::INT;

            IF v_id_restaurante IS NULL THEN
                CONTINUE;
            END IF;

            v_distancia := fn_distancia_km(v_lat_rest, v_lon_rest, v_lat_dir, v_lon_dir);
            IF v_distancia >= 20 THEN
                CONTINUE;
            END IF;
            v_costo_envio := fn_costo_envio(v_distancia);

            -- Maximo ~59.9 dias atras: queda dentro de las tasas BCV cargadas (ultimos 60 dias)
            v_fecha_creacion := now() - (random() * 59 + random()) * INTERVAL '1 day';
            v_tasa_bcv := fn_tasa_bcv(v_fecha_creacion::DATE);

            v_num_productos := 1 + floor(random() * 4)::INT;
            v_subtotal := 0;
            v_base_16  := 0;

            FOR v_producto IN
                SELECT id_producto, precio, exento_iva
                FROM producto
                WHERE id_restaurante = v_id_restaurante AND disponible = TRUE
                ORDER BY random() LIMIT v_num_productos
            LOOP
                j := 1 + floor(random() * 3)::INT;
                INSERT INTO tmp_lineas VALUES (v_producto.id_producto, j, v_producto.precio, v_producto.exento_iva);
                v_subtotal := v_subtotal + (j * v_producto.precio);
                IF NOT v_producto.exento_iva THEN
                    v_base_16 := v_base_16 + (j * v_producto.precio);
                END IF;
            END LOOP;

            IF NOT EXISTS (SELECT 1 FROM tmp_lineas) THEN
                CONTINUE;
            END IF;

            v_base_16   := v_base_16 + v_costo_envio;
            v_iva_total := round(v_base_16 * 0.16, 2);
            v_propina   := (ARRAY[0, 1, 1.5, 2, 3])[1 + floor(random() * 5)::INT];
            v_moneda    := CASE WHEN random() < 0.6 THEN 'USD' ELSE 'VES' END;

            v_igtf := CASE WHEN v_moneda = 'USD'
                THEN round((v_subtotal + v_costo_envio + v_propina + v_iva_total) * 0.03, 2)
                ELSE 0 END;

            v_total     := v_subtotal + v_costo_envio + v_propina + v_iva_total + v_igtf;
            v_total_ves := round(v_total * v_tasa_bcv, 2);
            v_comision  := round(v_subtotal * 0.15, 2);
            v_monto_restaurante := v_subtotal - v_comision;

            v_es_cancelado    := random() < 0.08;
            v_id_estado_final := CASE WHEN v_es_cancelado THEN 6 ELSE 5 END;

            SELECT rep.id_repartidor INTO v_id_repartidor
            FROM repartidor rep
            WHERE rep.id_zona IN (SELECT id_zona FROM restaurante_zona WHERE id_restaurante = v_id_restaurante)
            ORDER BY random() LIMIT 1;

            IF v_id_repartidor IS NULL THEN
                SELECT id_repartidor INTO v_id_repartidor FROM repartidor ORDER BY random() LIMIT 1;
            END IF;

            IF v_es_cancelado AND random() < 0.5 THEN
                v_id_repartidor := NULL;  -- se cancelo estando en 'recibido', sin repartidor
            END IF;

            INSERT INTO pedido (
                id_cliente, id_restaurante, id_direccion, id_repartidor, id_estado,
                distancia_km, subtotal, costo_envio, propina, iva_total, igtf,
                comision_plataforma, monto_restaurante, total, moneda_pago,
                tasa_bcv_aplicada, total_ves, motivo_cancelacion, fecha_creacion
            ) VALUES (
                v_id_cliente, v_id_restaurante, v_id_direccion, v_id_repartidor, v_id_estado_final,
                v_distancia, v_subtotal, v_costo_envio, v_propina, v_iva_total, v_igtf,
                v_comision, v_monto_restaurante, v_total, v_moneda, v_tasa_bcv, v_total_ves,
                CASE WHEN v_es_cancelado THEN 'El cliente cancelo el pedido' ELSE NULL END,
                v_fecha_creacion
            )
            RETURNING id_pedido INTO v_id_pedido;

            INSERT INTO detalle_pedido (id_pedido, id_producto, cantidad, precio_unitario, subtotal)
            SELECT v_id_pedido, id_producto, cantidad, precio, cantidad * precio FROM tmp_lineas;

            UPDATE pedido SET tiempo_estimado_min = fn_tiempo_estimado(v_id_pedido) WHERE id_pedido = v_id_pedido;

            -- El pago se registra siempre (fn_crear_pedido lo hace al crear, sin importar el desenlace)
            INSERT INTO pago (id_pedido, monto, moneda, ultimos4, referencia, estado, fecha)
            VALUES (
                v_id_pedido, v_total, v_moneda, lpad(floor(random() * 10000)::TEXT, 4, '0'),
                'SIM-' || v_id_pedido || '-' || to_char(v_fecha_creacion, 'YYYYMMDDHH24MISS'),
                'aprobado', v_fecha_creacion
            );

            v_t := v_fecha_creacion;
            INSERT INTO historial_estado_pedido (id_pedido, id_estado, fecha_hora) VALUES (v_id_pedido, 1, v_t);

            IF v_id_estado_final = 6 THEN
                IF v_id_repartidor IS NOT NULL THEN
                    v_t := v_t + make_interval(mins => 2 + floor(random() * 8)::INT);
                    INSERT INTO historial_estado_pedido (id_pedido, id_estado, fecha_hora) VALUES (v_id_pedido, 2, v_t);

                    IF random() < 0.5 THEN
                        v_t := v_t + make_interval(mins => 5 + floor(random() * 15)::INT);
                        INSERT INTO historial_estado_pedido (id_pedido, id_estado, fecha_hora) VALUES (v_id_pedido, 3, v_t);
                    END IF;

                    INSERT INTO oferta_asignacion (id_pedido, id_repartidor, distancia_km, fecha_oferta, respuesta, fecha_respuesta)
                    VALUES (v_id_pedido, v_id_repartidor, round((random() * 6)::NUMERIC, 2),
                            v_fecha_creacion, 'aceptada', v_fecha_creacion + INTERVAL '20 seconds');
                END IF;

                v_t := v_t + make_interval(mins => 2 + floor(random() * 10)::INT);
                INSERT INTO historial_estado_pedido (id_pedido, id_estado, fecha_hora) VALUES (v_id_pedido, 6, v_t);
            ELSE
                v_t := v_t + make_interval(mins => 2 + floor(random() * 8)::INT);
                INSERT INTO historial_estado_pedido (id_pedido, id_estado, fecha_hora) VALUES (v_id_pedido, 2, v_t);

                v_t := v_t + make_interval(mins => 5 + floor(random() * 20)::INT);
                INSERT INTO historial_estado_pedido (id_pedido, id_estado, fecha_hora) VALUES (v_id_pedido, 3, v_t);

                v_t := v_t + make_interval(mins => 1 + floor(random() * 8)::INT);
                INSERT INTO historial_estado_pedido (id_pedido, id_estado, fecha_hora) VALUES (v_id_pedido, 4, v_t);

                v_t := v_t + make_interval(mins => 8 + floor(random() * 20)::INT);
                INSERT INTO historial_estado_pedido (id_pedido, id_estado, fecha_hora) VALUES (v_id_pedido, 5, v_t);

                -- 0 o 1 ofertas rechazadas antes de la aceptada (alimenta la tasa de rechazo)
                IF random() < 0.15 THEN
                    INSERT INTO oferta_asignacion (id_pedido, id_repartidor, distancia_km, fecha_oferta, respuesta, fecha_respuesta)
                    SELECT v_id_pedido, rep2.id_repartidor, round((random() * 6)::NUMERIC, 2),
                           v_fecha_creacion, 'rechazada', v_fecha_creacion + INTERVAL '30 seconds'
                    FROM repartidor rep2
                    WHERE rep2.id_repartidor <> v_id_repartidor
                    ORDER BY random() LIMIT 1;
                END IF;

                INSERT INTO oferta_asignacion (id_pedido, id_repartidor, distancia_km, fecha_oferta, respuesta, fecha_respuesta)
                VALUES (v_id_pedido, v_id_repartidor, round((random() * 6)::NUMERIC, 2),
                        v_fecha_creacion, 'aceptada', v_fecha_creacion + INTERVAL '20 seconds');

                -- Calificaciones: casi siempre, con sesgo positivo y algunas bajas
                IF random() < 0.9 THEN
                    v_puntaje := CASE WHEN random() < 0.1 THEN (1 + floor(random() * 2))::SMALLINT ELSE (4 + floor(random() * 2))::SMALLINT END;
                    INSERT INTO calificacion (id_pedido, tipo, puntaje, fecha) VALUES (v_id_pedido, 'cliente_a_repartidor', v_puntaje, v_t);
                END IF;
                IF random() < 0.85 THEN
                    v_puntaje := CASE WHEN random() < 0.1 THEN (1 + floor(random() * 2))::SMALLINT ELSE (4 + floor(random() * 2))::SMALLINT END;
                    INSERT INTO calificacion (id_pedido, tipo, puntaje, fecha) VALUES (v_id_pedido, 'cliente_a_restaurante', v_puntaje, v_t);
                END IF;
                IF random() < 0.7 THEN
                    v_puntaje := (3 + floor(random() * 3))::SMALLINT;
                    INSERT INTO calificacion (id_pedido, tipo, puntaje, fecha) VALUES (v_id_pedido, 'repartidor_a_cliente', v_puntaje, v_t);
                END IF;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Pedido historico % omitido: %', i, SQLERRM;
        END;
    END LOOP;

    SET session_replication_role = origin;
END $$;

-- Recalcular promedios y en_revision (los triggers estuvieron desactivados)
UPDATE restaurante r
SET calificacion_promedio = COALESCE(sub.promedio, 0),
    total_calificaciones = COALESCE(sub.total, 0)
FROM (
    SELECT p.id_restaurante, ROUND(AVG(c.puntaje), 2) AS promedio, COUNT(*) AS total
    FROM calificacion c JOIN pedido p ON p.id_pedido = c.id_pedido
    WHERE c.tipo = 'cliente_a_restaurante'
    GROUP BY p.id_restaurante
) sub
WHERE sub.id_restaurante = r.id_restaurante;

UPDATE repartidor rep
SET calificacion_promedio = COALESCE(sub.promedio, 0),
    total_calificaciones = COALESCE(sub.total, 0),
    en_revision = (COALESCE(sub.total, 0) >= fn_param_num('calificaciones_minimas')
                   AND COALESCE(sub.promedio, 5) < fn_param_num('calificacion_minima'))
FROM (
    SELECT p.id_repartidor, ROUND(AVG(c.puntaje), 2) AS promedio, COUNT(*) AS total
    FROM calificacion c JOIN pedido p ON p.id_pedido = c.id_pedido
    WHERE c.tipo = 'cliente_a_repartidor'
    GROUP BY p.id_repartidor
) sub
WHERE sub.id_repartidor = rep.id_repartidor;

UPDATE cliente cl
SET calificacion_promedio = COALESCE(sub.promedio, 0),
    total_calificaciones = COALESCE(sub.total, 0),
    en_revision = (COALESCE(sub.total, 0) >= fn_param_num('calificaciones_minimas')
                   AND COALESCE(sub.promedio, 5) < fn_param_num('calificacion_minima'))
FROM (
    SELECT p.id_cliente, ROUND(AVG(c.puntaje), 2) AS promedio, COUNT(*) AS total
    FROM calificacion c JOIN pedido p ON p.id_pedido = c.id_pedido
    WHERE c.tipo = 'repartidor_a_cliente'
    GROUP BY p.id_cliente
) sub
WHERE sub.id_cliente = cl.id_cliente;

-- Recalcular prioridad segun la tasa de rechazo de las ultimas N ofertas
UPDATE repartidor rep
SET prioridad = CASE
    WHEN sub.respondidas >= fn_param_num('rechazo_minimo')
         AND sub.rechazadas::NUMERIC / sub.respondidas > fn_param_num('rechazo_umbral')
    THEN 'baja' ELSE 'normal' END
FROM (
    SELECT id_repartidor,
           COUNT(*) AS respondidas,
           COUNT(*) FILTER (WHERE respuesta IN ('rechazada', 'expirada')) AS rechazadas
    FROM (
        SELECT id_repartidor, respuesta,
               ROW_NUMBER() OVER (PARTITION BY id_repartidor ORDER BY fecha_oferta DESC) AS rn
        FROM oferta_asignacion
        WHERE respuesta IN ('aceptada', 'rechazada', 'expirada')
    ) x
    WHERE rn <= fn_param_num('rechazo_ventana')
    GROUP BY id_repartidor
) sub
WHERE sub.id_repartidor = rep.id_repartidor;

-- ==========================================================================
-- D. Facturacion de los datos historicos (con los triggers ya reactivados)
-- ==========================================================================

-- Factura de cada pedido entregado, en orden cronologico de entrega
DO $$
DECLARE
    v_ped RECORD;
BEGIN
    FOR v_ped IN
        SELECT p.id_pedido, h.fecha_hora AS fecha_entrega
        FROM pedido p
        JOIN historial_estado_pedido h ON h.id_pedido = p.id_pedido AND h.id_estado = 5
        WHERE p.id_estado = 5
        ORDER BY h.fecha_hora
    LOOP
        BEGIN
            PERFORM fn_emitir_factura_cliente(v_ped.id_pedido, v_ped.fecha_entrega);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Factura del pedido % omitida: %', v_ped.id_pedido, SQLERRM;
        END;
    END LOOP;
END $$;

-- Facturas de comision y liquidaciones de los "meses" pasados (dos periodos
-- dentro de la ventana de 60 dias)
DO $$
DECLARE
    v_id_admin INT;
BEGIN
    SELECT id_usuario INTO v_id_admin FROM usuario WHERE email = 'admin@demo.com';

    PERFORM fn_generar_facturas_comision(CURRENT_DATE - 60, CURRENT_DATE - 31, v_id_admin);
    PERFORM fn_generar_facturas_comision(CURRENT_DATE - 30, CURRENT_DATE - 1, v_id_admin);

    PERFORM fn_generar_liquidaciones(CURRENT_DATE - 60, CURRENT_DATE - 31);
    PERFORM fn_generar_liquidaciones(CURRENT_DATE - 30, CURRENT_DATE - 1);
END $$;

-- 2 o 3 notas de credito, para que el libro de ventas las muestre
DO $$
DECLARE
    v_id_admin INT;
    v_factura  RECORD;
BEGIN
    SELECT id_usuario INTO v_id_admin FROM usuario WHERE email = 'admin@demo.com';

    FOR v_factura IN
        SELECT id_factura FROM factura
        WHERE tipo = 'factura_cliente' AND estado = 'emitida'
        ORDER BY random() LIMIT 3
    LOOP
        PERFORM fn_anular_factura(v_factura.id_factura, 'Devolucion solicitada por el cliente', v_id_admin);
    END LOOP;
END $$;

-- ==========================================================================
-- E. ~10 pedidos activos para la demo (creados CON las funciones, no con
-- INSERT directo), repartidos entre los estados 1, 2, 3 y 4
-- ==========================================================================
DO $$
DECLARE
    v_id_cliente      INT;
    v_id_direccion    INT;
    v_zona_cliente    INT;
    v_id_restaurante  INT;
    v_productos       JSONB;
    v_id_pedido       INT;
    v_id_oferta       INT;
    v_estado_objetivo INT;
    i INT;
BEGIN
    FOR i IN 1..10 LOOP
        BEGIN
            v_id_restaurante := NULL;

            SELECT dc.id_cliente, dc.id_direccion, dc.id_zona
            INTO v_id_cliente, v_id_direccion, v_zona_cliente
            FROM direccion_cliente dc ORDER BY random() LIMIT 1;

            SELECT r.id_restaurante INTO v_id_restaurante
            FROM restaurante r JOIN restaurante_zona rz ON rz.id_restaurante = r.id_restaurante
            WHERE rz.id_zona = v_zona_cliente
            ORDER BY random() LIMIT 1;

            IF v_id_restaurante IS NULL THEN
                CONTINUE;
            END IF;

            SELECT jsonb_agg(jsonb_build_object('id_producto', id_producto, 'cantidad', 1 + floor(random() * 2)::INT))
            INTO v_productos
            FROM (
                SELECT id_producto FROM producto
                WHERE id_restaurante = v_id_restaurante AND disponible = TRUE
                ORDER BY random() LIMIT (1 + floor(random() * 3)::INT)
            ) sub;

            v_id_pedido := fn_crear_pedido(
                v_id_cliente, v_id_restaurante, v_id_direccion, v_productos,
                (ARRAY[0, 1, 2])[1 + floor(random() * 3)::INT], 'USD', '4242'
            );

            v_estado_objetivo := (ARRAY[1, 2, 3, 4])[1 + floor(random() * 4)::INT];

            IF v_estado_objetivo >= 2 THEN
                PERFORM fn_cambiar_estado(v_id_pedido, 2::SMALLINT, NULL::INT);

                SELECT id_oferta INTO v_id_oferta FROM oferta_asignacion
                WHERE id_pedido = v_id_pedido AND respuesta = 'pendiente';

                IF v_id_oferta IS NOT NULL THEN
                    PERFORM fn_responder_oferta(v_id_oferta, TRUE);
                END IF;
            END IF;

            IF v_estado_objetivo >= 3 THEN
                PERFORM fn_cambiar_estado(v_id_pedido, 3::SMALLINT, NULL::INT);
            END IF;

            IF v_estado_objetivo >= 4
               AND EXISTS (SELECT 1 FROM pedido WHERE id_pedido = v_id_pedido AND id_repartidor IS NOT NULL) THEN
                PERFORM fn_cambiar_estado(v_id_pedido, 4::SMALLINT, NULL::INT);
            END IF;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Pedido activo de demo % omitido: %', i, SQLERRM;
        END;
    END LOOP;
END $$;
