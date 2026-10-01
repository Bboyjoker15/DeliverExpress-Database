-- ==========================================================================
-- DeliverExpress - 03_funciones_logistica.sql
-- Integrante 1 (asumido: el Integrante 2 no se presento al equipo).
-- Funciones de logistica originalmente asignadas al Integrante 2
-- (roadmap_bd.txt seccion 5). Verificado contra el backend ya construido
-- (DeliverExpress-backend): nombres de funcion y parametros coinciden.
-- ==========================================================================
SET search_path TO deliverexpress;

-- --------------------------------------------------------------------------
-- fn_param_num: lee un valor de parametro_sistema como numero
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_param_num(p_clave VARCHAR)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_valor NUMERIC;
BEGIN
    SELECT valor::NUMERIC INTO v_valor
    FROM parametro_sistema
    WHERE clave = p_clave;

    RETURN v_valor;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_distancia_km: formula de Haversine, radio de la Tierra 6371 km.
-- Parametros DOUBLE PRECISION (no NUMERIC): numeric->float8 es implicito en
-- Postgres pero float8->numeric NO lo es, asi que con NUMERIC esta funcion
-- fallaria con "function does not exist" apenas alguien le pasara floats de
-- Python (el simulador, p. ej., castea las coordenadas a ::float8). Con
-- DOUBLE PRECISION se aceptan los dos: columnas NUMERIC de la BD y floats de
-- Python. El resultado se redondea a NUMERIC(.,2) al final igual que antes.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_distancia_km(
    p_lat1 DOUBLE PRECISION, p_lon1 DOUBLE PRECISION,
    p_lat2 DOUBLE PRECISION, p_lon2 DOUBLE PRECISION
)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_radio_km  CONSTANT DOUBLE PRECISION := 6371;
    v_dlat      DOUBLE PRECISION;
    v_dlon      DOUBLE PRECISION;
    v_a         DOUBLE PRECISION;
    v_c         DOUBLE PRECISION;
BEGIN
    v_dlat := radians(p_lat2 - p_lat1);
    v_dlon := radians(p_lon2 - p_lon1);
    v_a := sin(v_dlat / 2) ^ 2
         + cos(radians(p_lat1)) * cos(radians(p_lat2)) * sin(v_dlon / 2) ^ 2;
    v_c := 2 * atan2(sqrt(v_a), sqrt(1 - v_a));
    RETURN ROUND((v_radio_km * v_c)::NUMERIC, 2);
END;
$$;

-- --------------------------------------------------------------------------
-- fn_costo_envio: busca el rango de tarifa_envio que contiene la distancia
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_costo_envio(p_distancia NUMERIC)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_precio NUMERIC;
BEGIN
    SELECT precio INTO v_precio
    FROM tarifa_envio
    WHERE p_distancia >= km_desde AND p_distancia < km_hasta;

    IF v_precio IS NULL THEN
        RAISE EXCEPTION 'FUERA_DE_COBERTURA: la distancia % km no entra en ninguna tarifa de envio', p_distancia;
    END IF;

    RETURN v_precio;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_restaurante_disponible: activo, abierto ahora, cubre la zona
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_restaurante_disponible(p_id_restaurante INT, p_id_direccion INT)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_activo   BOOLEAN;
    v_zona     INT;
    v_dia      SMALLINT;
    v_hora     TIME;
    v_abierto  BOOLEAN;
    v_cubre    BOOLEAN;
BEGIN
    SELECT activo INTO v_activo FROM restaurante WHERE id_restaurante = p_id_restaurante;
    IF v_activo IS NULL OR NOT v_activo THEN
        RETURN FALSE;
    END IF;

    -- EXTRACT(DOW ...) da 0 = domingo, igual que horario_restaurante.dia_semana.
    v_dia  := EXTRACT(DOW FROM now());
    v_hora := now()::TIME;

    SELECT EXISTS (
        SELECT 1 FROM horario_restaurante
        WHERE id_restaurante = p_id_restaurante
          AND dia_semana = v_dia
          AND v_hora BETWEEN hora_apertura AND hora_cierre
    ) INTO v_abierto;

    IF NOT v_abierto THEN
        RETURN FALSE;
    END IF;

    SELECT id_zona INTO v_zona FROM direccion_cliente WHERE id_direccion = p_id_direccion;

    SELECT EXISTS (
        SELECT 1 FROM restaurante_zona
        WHERE id_restaurante = p_id_restaurante AND id_zona = v_zona
    ) INTO v_cubre;

    RETURN v_cubre;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_tasa_bcv: tasa del dia, o la ultima anterior si no hay
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tasa_bcv(p_fecha DATE)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
DECLARE
    v_tasa NUMERIC;
BEGIN
    SELECT tasa_usd INTO v_tasa
    FROM tasa_bcv
    WHERE fecha <= p_fecha
    ORDER BY fecha DESC
    LIMIT 1;

    IF v_tasa IS NULL THEN
        RAISE EXCEPTION 'TASA_BCV_NO_REGISTRADA: no hay ninguna tasa BCV cargada para % ni antes', p_fecha;
    END IF;

    RETURN v_tasa;
END;
$$;

-- --------------------------------------------------------------------------
-- fn_tiempo_estimado: preparacion + distancia / velocidad del vehiculo
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_tiempo_estimado(p_id_pedido INT)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_tiempo_prep    INT;
    v_distancia      NUMERIC;
    v_id_repartidor  INT;
    v_tipo_vehiculo  VARCHAR(12);
    v_velocidad      NUMERIC;
    v_minutos        NUMERIC;
BEGIN
    SELECT r.tiempo_prep_min, p.distancia_km, p.id_repartidor
    INTO v_tiempo_prep, v_distancia, v_id_repartidor
    FROM pedido p
    JOIN restaurante r ON r.id_restaurante = p.id_restaurante
    WHERE p.id_pedido = p_id_pedido;

    IF v_id_repartidor IS NOT NULL THEN
        SELECT tipo_vehiculo INTO v_tipo_vehiculo FROM repartidor WHERE id_repartidor = v_id_repartidor;
    END IF;

    -- Sin repartidor asignado todavia: se usa la velocidad de moto (roadmap_bd §5).
    v_velocidad := CASE COALESCE(v_tipo_vehiculo, 'moto')
        WHEN 'bicicleta' THEN fn_param_num('velocidad_bicicleta_kmh')
        WHEN 'auto'      THEN fn_param_num('velocidad_auto_kmh')
        ELSE                  fn_param_num('velocidad_moto_kmh')
    END;

    v_minutos := v_tiempo_prep + (v_distancia / v_velocidad) * 60;

    RETURN CEIL(v_minutos);
END;
$$;
