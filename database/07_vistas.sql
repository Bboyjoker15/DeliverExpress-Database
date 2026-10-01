-- ==========================================================================
-- DeliverExpress - 07_vistas.sql
-- Integrante 1
-- Las 7 vistas de negocio (roadmap_bd.txt seccion 9). Las columnas listadas
-- son CONTRATO con el backend: mismos nombres, no se renombran sin avisar.
-- ==========================================================================
SET search_path TO deliverexpress;

-- --------------------------------------------------------------------------
-- vw_pedidos_activos: panel de coordinadores (pedidos en estado 1,2,3 o 4)
-- --------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_pedidos_activos AS
SELECT
    p.id_pedido,
    p.fecha_creacion,
    p.id_estado,
    e.codigo AS estado_codigo,
    e.nombre AS estado_nombre,
    FLOOR(EXTRACT(EPOCH FROM (now() - h.fecha_hora)) / 60)::INT AS minutos_en_estado,
    p.id_restaurante,
    r.nombre AS restaurante,
    r.tiempo_prep_min,
    r.latitud AS restaurante_lat,
    r.longitud AS restaurante_lon,
    p.id_cliente,
    c.nombre AS cliente,
    d.direccion AS direccion_entrega,
    d.latitud AS entrega_lat,
    d.longitud AS entrega_lon,
    p.id_repartidor,
    rep.nombre AS repartidor,
    rep.latitud_actual AS repartidor_lat,
    rep.longitud_actual AS repartidor_lon,
    p.tiempo_estimado_min,
    FLOOR(EXTRACT(EPOCH FROM (now() - p.fecha_creacion)) / 60)::INT AS minutos_desde_creacion,
    p.total
FROM pedido p
JOIN estado_pedido e ON e.id_estado = p.id_estado
JOIN restaurante r ON r.id_restaurante = p.id_restaurante
JOIN cliente c ON c.id_cliente = p.id_cliente
JOIN direccion_cliente d ON d.id_direccion = p.id_direccion
LEFT JOIN repartidor rep ON rep.id_repartidor = p.id_repartidor
JOIN LATERAL (
    SELECT fecha_hora FROM historial_estado_pedido h2
    WHERE h2.id_pedido = p.id_pedido AND h2.id_estado = p.id_estado
    ORDER BY h2.fecha_hora DESC LIMIT 1
) h ON TRUE
WHERE p.id_estado IN (1, 2, 3, 4);

-- --------------------------------------------------------------------------
-- vw_repartidores_disponibles: activos y libres, con su posicion
-- --------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_repartidores_disponibles AS
SELECT
    rep.id_repartidor,
    rep.nombre,
    rep.id_zona,
    z.nombre AS zona,
    rep.tipo_vehiculo,
    rep.prioridad,
    rep.calificacion_promedio,
    rep.latitud_actual,
    rep.longitud_actual
FROM repartidor rep
JOIN zona z ON z.id_zona = rep.id_zona
WHERE rep.activo = TRUE AND rep.disponibilidad = 'libre';

-- --------------------------------------------------------------------------
-- vw_tiempos_por_etapa: minutos entre cada estado, con LAG sobre el
-- historial (solo pedidos entregados)
-- --------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_tiempos_por_etapa AS
WITH transiciones AS (
    SELECT
        h.id_pedido,
        h.id_estado,
        LAG(h.id_estado) OVER (PARTITION BY h.id_pedido ORDER BY h.fecha_hora) AS estado_anterior,
        h.fecha_hora,
        LAG(h.fecha_hora) OVER (PARTITION BY h.id_pedido ORDER BY h.fecha_hora) AS fecha_anterior
    FROM historial_estado_pedido h
    JOIN pedido p ON p.id_pedido = h.id_pedido
    WHERE p.id_estado = 5
)
SELECT
    p.id_pedido,
    p.id_restaurante,
    p.id_repartidor,
    p.fecha_creacion,
    MAX(CASE WHEN t.estado_anterior = 1 AND t.id_estado = 2
             THEN ROUND(EXTRACT(EPOCH FROM (t.fecha_hora - t.fecha_anterior)) / 60, 2) END) AS min_espera_restaurante,
    MAX(CASE WHEN t.estado_anterior = 2 AND t.id_estado = 3
             THEN ROUND(EXTRACT(EPOCH FROM (t.fecha_hora - t.fecha_anterior)) / 60, 2) END) AS min_preparacion,
    MAX(CASE WHEN t.estado_anterior = 3 AND t.id_estado = 4
             THEN ROUND(EXTRACT(EPOCH FROM (t.fecha_hora - t.fecha_anterior)) / 60, 2) END) AS min_espera_retiro,
    MAX(CASE WHEN t.estado_anterior = 4 AND t.id_estado = 5
             THEN ROUND(EXTRACT(EPOCH FROM (t.fecha_hora - t.fecha_anterior)) / 60, 2) END) AS min_entrega,
    ROUND(EXTRACT(EPOCH FROM (
        MAX(CASE WHEN t.id_estado = 5 THEN t.fecha_hora END) - p.fecha_creacion
    )) / 60, 2) AS min_total
FROM pedido p
JOIN transiciones t ON t.id_pedido = p.id_pedido
WHERE p.id_estado = 5
GROUP BY p.id_pedido, p.id_restaurante, p.id_repartidor, p.fecha_creacion;

-- --------------------------------------------------------------------------
-- vw_desempeno_restaurantes
-- --------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_desempeno_restaurantes AS
SELECT
    r.id_restaurante,
    r.nombre AS restaurante,
    cat.nombre AS categoria,
    COUNT(p.id_pedido) AS total_pedidos,
    COUNT(p.id_pedido) FILTER (WHERE p.id_estado = 6) AS pedidos_cancelados,
    ROUND(AVG(vt.min_preparacion), 2) AS prom_min_preparacion,
    r.calificacion_promedio,
    COALESCE(SUM(p.subtotal) FILTER (WHERE p.id_estado = 5), 0) AS ventas_productos
FROM restaurante r
JOIN categoria cat ON cat.id_categoria = r.id_categoria
LEFT JOIN pedido p ON p.id_restaurante = r.id_restaurante
LEFT JOIN vw_tiempos_por_etapa vt ON vt.id_pedido = p.id_pedido
GROUP BY r.id_restaurante, r.nombre, cat.nombre, r.calificacion_promedio;

-- --------------------------------------------------------------------------
-- vw_desempeno_repartidores
-- --------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_desempeno_repartidores AS
SELECT
    rep.id_repartidor,
    rep.nombre AS repartidor,
    rep.tipo_vehiculo,
    COUNT(p.id_pedido) FILTER (WHERE p.id_estado = 5) AS entregas,
    ROUND(AVG(vt.min_entrega), 2) AS prom_min_entrega,
    COALESCE(of.ofertas_recibidas, 0) AS ofertas_recibidas,
    COALESCE(of.ofertas_rechazadas, 0) AS ofertas_rechazadas,
    CASE WHEN COALESCE(of.ofertas_recibidas, 0) = 0 THEN 0
         ELSE ROUND(of.ofertas_rechazadas::NUMERIC / of.ofertas_recibidas, 2)
    END AS tasa_rechazo,
    COALESCE(SUM(p.costo_envio + p.propina) FILTER (WHERE p.id_estado = 5), 0) AS ganancias,
    rep.calificacion_promedio,
    rep.prioridad,
    rep.en_revision
FROM repartidor rep
LEFT JOIN pedido p ON p.id_repartidor = rep.id_repartidor
LEFT JOIN vw_tiempos_por_etapa vt ON vt.id_pedido = p.id_pedido
LEFT JOIN (
    SELECT
        id_repartidor,
        COUNT(*) AS ofertas_recibidas,
        COUNT(*) FILTER (WHERE respuesta IN ('rechazada', 'expirada')) AS ofertas_rechazadas
    FROM oferta_asignacion
    GROUP BY id_repartidor
) of ON of.id_repartidor = rep.id_repartidor
GROUP BY rep.id_repartidor, rep.nombre, rep.tipo_vehiculo, of.ofertas_recibidas,
         of.ofertas_rechazadas, rep.calificacion_promedio, rep.prioridad, rep.en_revision;

-- --------------------------------------------------------------------------
-- vw_liquidacion: cuanto corresponde a plataforma, restaurante y repartidor
-- por dia (solo pedidos entregados)
-- --------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_liquidacion AS
SELECT
    p.fecha_creacion::DATE AS fecha,
    p.id_restaurante,
    r.nombre AS restaurante,
    COUNT(*) AS pedidos,
    SUM(p.subtotal) AS ventas_productos,
    SUM(p.comision_plataforma) AS comision_plataforma,
    SUM(p.monto_restaurante) AS monto_restaurante,
    SUM(p.costo_envio) AS envios,
    SUM(p.propina) AS propinas
FROM pedido p
JOIN restaurante r ON r.id_restaurante = p.id_restaurante
WHERE p.id_estado = 5
GROUP BY p.fecha_creacion::DATE, p.id_restaurante, r.nombre;

-- --------------------------------------------------------------------------
-- vw_recomendaciones_cliente: categorias y productos que mas pide cada
-- cliente (pedidos entregados). ranking = 1 es el que mas pide.
-- --------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_recomendaciones_cliente AS
SELECT
    id_cliente, id_producto, producto, id_restaurante, restaurante, categoria, veces_pedido,
    ROW_NUMBER() OVER (PARTITION BY id_cliente ORDER BY veces_pedido DESC) AS ranking
FROM (
    SELECT
        p.id_cliente,
        dp.id_producto,
        pr.nombre AS producto,
        pr.id_restaurante,
        r.nombre AS restaurante,
        cat.nombre AS categoria,
        COUNT(*) AS veces_pedido
    FROM detalle_pedido dp
    JOIN pedido p ON p.id_pedido = dp.id_pedido
    JOIN producto pr ON pr.id_producto = dp.id_producto
    JOIN restaurante r ON r.id_restaurante = pr.id_restaurante
    JOIN categoria cat ON cat.id_categoria = r.id_categoria
    WHERE p.id_estado = 5
    GROUP BY p.id_cliente, dp.id_producto, pr.nombre, pr.id_restaurante, r.nombre, cat.nombre
) base;
