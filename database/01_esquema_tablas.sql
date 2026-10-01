-- ==========================================================================
-- DeliverExpress - 01_esquema_tablas.sql
-- Integrante 1
-- Las 27 tablas del esquema (21 de nucleo + 6 de facturacion), en orden de
-- dependencia de FK. Nombres, tipos y restricciones = contrato de
-- roadmap_bd.txt seccion 3 (nucleo) y seccion 8b (facturacion). No renombrar
-- nada sin avisar al grupo.
-- ==========================================================================
SET search_path TO deliverexpress;

-- --------------------------------------------------------------------------
-- usuario
-- --------------------------------------------------------------------------
CREATE TABLE usuario (
    id_usuario      SERIAL,
    email           VARCHAR(120) NOT NULL,
    password_hash   TEXT NOT NULL,
    rol             VARCHAR(20) NOT NULL,
    activo          BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_registro  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_usuario PRIMARY KEY (id_usuario),
    CONSTRAINT uq_usuario_email UNIQUE (email),
    CONSTRAINT ck_usuario_rol CHECK (rol IN ('cliente','restaurante','repartidor','coordinador','admin'))
);

-- --------------------------------------------------------------------------
-- zona
-- --------------------------------------------------------------------------
CREATE TABLE zona (
    id_zona          SERIAL,
    nombre           VARCHAR(80) NOT NULL,
    descripcion      TEXT,
    latitud_centro   NUMERIC(9,6) NOT NULL,
    longitud_centro  NUMERIC(9,6) NOT NULL,
    CONSTRAINT pk_zona PRIMARY KEY (id_zona),
    CONSTRAINT uq_zona_nombre UNIQUE (nombre)
);

-- --------------------------------------------------------------------------
-- categoria
-- --------------------------------------------------------------------------
CREATE TABLE categoria (
    id_categoria  SERIAL,
    nombre        VARCHAR(60) NOT NULL,
    CONSTRAINT pk_categoria PRIMARY KEY (id_categoria),
    CONSTRAINT uq_categoria_nombre UNIQUE (nombre)
);

-- --------------------------------------------------------------------------
-- restaurante
-- --------------------------------------------------------------------------
CREATE TABLE restaurante (
    id_restaurante          SERIAL,
    id_usuario              INT NOT NULL,
    id_categoria            INT NOT NULL,
    nombre                  VARCHAR(100) NOT NULL,
    direccion               VARCHAR(200) NOT NULL,
    telefono                VARCHAR(20) NOT NULL,
    latitud                 NUMERIC(9,6) NOT NULL,
    longitud                NUMERIC(9,6) NOT NULL,
    tiempo_prep_min         INT NOT NULL,
    rif                     VARCHAR(12) NOT NULL,
    razon_social            VARCHAR(150) NOT NULL,
    direccion_fiscal        VARCHAR(250) NOT NULL,
    calificacion_promedio   NUMERIC(3,2) NOT NULL DEFAULT 0,
    total_calificaciones    INT NOT NULL DEFAULT 0,
    activo                  BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_restaurante PRIMARY KEY (id_restaurante),
    CONSTRAINT uq_restaurante_usuario UNIQUE (id_usuario),
    CONSTRAINT uq_restaurante_rif UNIQUE (rif),
    CONSTRAINT fk_restaurante_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario),
    CONSTRAINT fk_restaurante_categoria FOREIGN KEY (id_categoria) REFERENCES categoria(id_categoria),
    CONSTRAINT ck_restaurante_latitud CHECK (latitud BETWEEN -90 AND 90),
    CONSTRAINT ck_restaurante_longitud CHECK (longitud BETWEEN -180 AND 180),
    CONSTRAINT ck_restaurante_tiempo_prep CHECK (tiempo_prep_min > 0),
    CONSTRAINT ck_restaurante_rif CHECK (rif ~ '^[VEJPG]-[0-9]{8}-[0-9]$')
);

-- --------------------------------------------------------------------------
-- horario_restaurante
-- --------------------------------------------------------------------------
CREATE TABLE horario_restaurante (
    id_horario      SERIAL,
    id_restaurante  INT NOT NULL,
    dia_semana      SMALLINT NOT NULL,
    hora_apertura   TIME NOT NULL,
    hora_cierre     TIME NOT NULL,
    CONSTRAINT pk_horario_restaurante PRIMARY KEY (id_horario),
    CONSTRAINT fk_horario_restaurante_restaurante FOREIGN KEY (id_restaurante)
        REFERENCES restaurante(id_restaurante) ON DELETE CASCADE,
    CONSTRAINT uq_horario_restaurante_dia UNIQUE (id_restaurante, dia_semana),
    -- 0 = domingo, igual que EXTRACT(DOW FROM ...) (roadmap_bd §3).
    CONSTRAINT ck_horario_restaurante_dia CHECK (dia_semana BETWEEN 0 AND 6),
    -- No se manejan horarios que cruzan la medianoche.
    CONSTRAINT ck_horario_restaurante_horas CHECK (hora_cierre > hora_apertura)
);

-- --------------------------------------------------------------------------
-- restaurante_zona (N:M)
-- --------------------------------------------------------------------------
CREATE TABLE restaurante_zona (
    id_restaurante  INT NOT NULL,
    id_zona         INT NOT NULL,
    CONSTRAINT pk_restaurante_zona PRIMARY KEY (id_restaurante, id_zona),
    CONSTRAINT fk_restaurante_zona_restaurante FOREIGN KEY (id_restaurante)
        REFERENCES restaurante(id_restaurante) ON DELETE CASCADE,
    CONSTRAINT fk_restaurante_zona_zona FOREIGN KEY (id_zona) REFERENCES zona(id_zona)
);

-- --------------------------------------------------------------------------
-- producto
-- --------------------------------------------------------------------------
CREATE TABLE producto (
    id_producto     SERIAL,
    id_restaurante  INT NOT NULL,
    nombre          VARCHAR(100) NOT NULL,
    descripcion     TEXT,
    precio          NUMERIC(10,2) NOT NULL,
    exento_iva      BOOLEAN NOT NULL DEFAULT FALSE,
    disponible      BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_producto PRIMARY KEY (id_producto),
    CONSTRAINT fk_producto_restaurante FOREIGN KEY (id_restaurante) REFERENCES restaurante(id_restaurante),
    CONSTRAINT ck_producto_precio CHECK (precio > 0)
    -- Los productos no se borran: se ponen disponible = FALSE (roadmap_bd §3).
);

-- --------------------------------------------------------------------------
-- cliente
-- --------------------------------------------------------------------------
CREATE TABLE cliente (
    id_cliente             SERIAL,
    id_usuario             INT NOT NULL,
    nombre                 VARCHAR(100) NOT NULL,
    telefono               VARCHAR(20) NOT NULL,
    cedula_rif             VARCHAR(12),
    calificacion_promedio  NUMERIC(3,2) NOT NULL DEFAULT 0,
    total_calificaciones   INT NOT NULL DEFAULT 0,
    en_revision            BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_cliente PRIMARY KEY (id_cliente),
    CONSTRAINT uq_cliente_usuario UNIQUE (id_usuario),
    CONSTRAINT fk_cliente_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario),
    -- NULL = la factura sale a nombre del cliente sin RIF (roadmap_bd §3).
    CONSTRAINT ck_cliente_cedula_rif CHECK (
        cedula_rif IS NULL
        OR cedula_rif ~ '^[VE]-[0-9]{6,9}$'
        OR cedula_rif ~ '^[VEJPG]-[0-9]{8}-[0-9]$'
    )
);

-- --------------------------------------------------------------------------
-- direccion_cliente
-- --------------------------------------------------------------------------
CREATE TABLE direccion_cliente (
    id_direccion  SERIAL,
    id_cliente    INT NOT NULL,
    id_zona       INT NOT NULL,
    direccion     VARCHAR(200) NOT NULL,
    referencia    VARCHAR(200),
    latitud       NUMERIC(9,6) NOT NULL,
    longitud      NUMERIC(9,6) NOT NULL,
    principal     BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_direccion_cliente PRIMARY KEY (id_direccion),
    CONSTRAINT fk_direccion_cliente_cliente FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente),
    CONSTRAINT fk_direccion_cliente_zona FOREIGN KEY (id_zona) REFERENCES zona(id_zona)
);

-- --------------------------------------------------------------------------
-- repartidor
-- --------------------------------------------------------------------------
CREATE TABLE repartidor (
    id_repartidor             SERIAL,
    id_usuario                INT NOT NULL,
    id_zona                   INT NOT NULL,
    nombre                    VARCHAR(100) NOT NULL,
    telefono                  VARCHAR(20) NOT NULL,
    cedula                    VARCHAR(12) NOT NULL,
    tipo_vehiculo             VARCHAR(12) NOT NULL,
    disponibilidad            VARCHAR(12) NOT NULL DEFAULT 'desconectado',
    prioridad                 VARCHAR(8) NOT NULL DEFAULT 'normal',
    latitud_actual            NUMERIC(9,6),
    longitud_actual           NUMERIC(9,6),
    ubicacion_actualizada_en  TIMESTAMPTZ,
    calificacion_promedio     NUMERIC(3,2) NOT NULL DEFAULT 0,
    total_calificaciones      INT NOT NULL DEFAULT 0,
    en_revision               BOOLEAN NOT NULL DEFAULT FALSE,
    activo                    BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT pk_repartidor PRIMARY KEY (id_repartidor),
    CONSTRAINT uq_repartidor_usuario UNIQUE (id_usuario),
    CONSTRAINT uq_repartidor_cedula UNIQUE (cedula),
    CONSTRAINT fk_repartidor_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario),
    CONSTRAINT fk_repartidor_zona FOREIGN KEY (id_zona) REFERENCES zona(id_zona),
    CONSTRAINT ck_repartidor_cedula CHECK (cedula ~ '^[VE]-[0-9]{6,9}$'),
    CONSTRAINT ck_repartidor_tipo_vehiculo CHECK (tipo_vehiculo IN ('bicicleta','moto','auto')),
    CONSTRAINT ck_repartidor_disponibilidad CHECK (disponibilidad IN ('libre','ocupado','desconectado')),
    CONSTRAINT ck_repartidor_prioridad CHECK (prioridad IN ('normal','baja'))
);

-- --------------------------------------------------------------------------
-- coordinador
-- --------------------------------------------------------------------------
CREATE TABLE coordinador (
    id_coordinador  SERIAL,
    id_usuario      INT NOT NULL,
    nombre          VARCHAR(100) NOT NULL,
    telefono        VARCHAR(20) NOT NULL,
    CONSTRAINT pk_coordinador PRIMARY KEY (id_coordinador),
    CONSTRAINT uq_coordinador_usuario UNIQUE (id_usuario),
    CONSTRAINT fk_coordinador_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario)
);

-- --------------------------------------------------------------------------
-- estado_pedido (catalogo de IDs FIJOS, no SERIAL; se llena en 02_catalogos.sql)
-- --------------------------------------------------------------------------
CREATE TABLE estado_pedido (
    id_estado  SMALLINT,
    codigo     VARCHAR(30) NOT NULL,
    nombre     VARCHAR(40) NOT NULL,
    orden      SMALLINT NOT NULL,
    CONSTRAINT pk_estado_pedido PRIMARY KEY (id_estado),
    CONSTRAINT uq_estado_pedido_codigo UNIQUE (codigo)
);

-- --------------------------------------------------------------------------
-- pedido
-- --------------------------------------------------------------------------
CREATE TABLE pedido (
    id_pedido             SERIAL,
    id_cliente            INT NOT NULL,
    id_restaurante        INT NOT NULL,
    id_direccion          INT NOT NULL,
    id_repartidor         INT,
    id_estado             SMALLINT NOT NULL DEFAULT 1,
    distancia_km          NUMERIC(6,2) NOT NULL,
    subtotal              NUMERIC(10,2) NOT NULL,
    costo_envio           NUMERIC(10,2) NOT NULL,
    propina               NUMERIC(10,2) NOT NULL DEFAULT 0,
    iva_total             NUMERIC(10,2) NOT NULL DEFAULT 0,
    igtf                  NUMERIC(10,2) NOT NULL DEFAULT 0,
    comision_plataforma   NUMERIC(10,2) NOT NULL,
    monto_restaurante     NUMERIC(10,2) NOT NULL,
    total                 NUMERIC(10,2) NOT NULL,           -- en USD
    moneda_pago           CHAR(3) NOT NULL DEFAULT 'USD',
    tasa_bcv_aplicada     NUMERIC(14,4) NOT NULL,            -- Bs por 1 USD, del dia del pedido
    total_ves             NUMERIC(14,2) NOT NULL,
    tiempo_estimado_min   INT,
    motivo_cancelacion    VARCHAR(200),
    fecha_creacion        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_pedido PRIMARY KEY (id_pedido),
    CONSTRAINT fk_pedido_cliente FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente),
    CONSTRAINT fk_pedido_restaurante FOREIGN KEY (id_restaurante) REFERENCES restaurante(id_restaurante),
    CONSTRAINT fk_pedido_direccion FOREIGN KEY (id_direccion) REFERENCES direccion_cliente(id_direccion),
    CONSTRAINT fk_pedido_repartidor FOREIGN KEY (id_repartidor) REFERENCES repartidor(id_repartidor),
    CONSTRAINT fk_pedido_estado FOREIGN KEY (id_estado) REFERENCES estado_pedido(id_estado),
    CONSTRAINT ck_pedido_distancia CHECK (distancia_km >= 0),
    CONSTRAINT ck_pedido_subtotal CHECK (subtotal >= 0),
    CONSTRAINT ck_pedido_costo_envio CHECK (costo_envio >= 0),
    CONSTRAINT ck_pedido_propina CHECK (propina >= 0),
    CONSTRAINT ck_pedido_iva_total CHECK (iva_total >= 0),
    CONSTRAINT ck_pedido_igtf CHECK (igtf >= 0),
    CONSTRAINT ck_pedido_comision CHECK (comision_plataforma >= 0),
    CONSTRAINT ck_pedido_monto_restaurante CHECK (monto_restaurante >= 0),
    CONSTRAINT ck_pedido_moneda_pago CHECK (moneda_pago IN ('USD','VES')),
    CONSTRAINT ck_pedido_tasa_bcv CHECK (tasa_bcv_aplicada > 0),
    CONSTRAINT ck_pedido_total CHECK (total = subtotal + costo_envio + propina + iva_total + igtf),
    CONSTRAINT ck_pedido_comision_monto CHECK (comision_plataforma + monto_restaurante = subtotal),
    CONSTRAINT ck_pedido_igtf_moneda CHECK (moneda_pago = 'USD' OR igtf = 0)
);

-- --------------------------------------------------------------------------
-- detalle_pedido
-- --------------------------------------------------------------------------
CREATE TABLE detalle_pedido (
    id_pedido        INT NOT NULL,
    id_producto      INT NOT NULL,
    cantidad         INT NOT NULL,
    precio_unitario  NUMERIC(10,2) NOT NULL,   -- copia del precio al momento del pedido
    subtotal         NUMERIC(10,2) NOT NULL,
    CONSTRAINT pk_detalle_pedido PRIMARY KEY (id_pedido, id_producto),
    CONSTRAINT fk_detalle_pedido_pedido FOREIGN KEY (id_pedido)
        REFERENCES pedido(id_pedido) ON DELETE CASCADE,
    CONSTRAINT fk_detalle_pedido_producto FOREIGN KEY (id_producto) REFERENCES producto(id_producto),
    CONSTRAINT ck_detalle_pedido_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_detalle_pedido_subtotal CHECK (subtotal = cantidad * precio_unitario)
);

-- --------------------------------------------------------------------------
-- historial_estado_pedido
-- --------------------------------------------------------------------------
CREATE TABLE historial_estado_pedido (
    id_historial  SERIAL,
    id_pedido     INT NOT NULL,
    id_estado     SMALLINT NOT NULL,
    fecha_hora    TIMESTAMPTZ NOT NULL DEFAULT now(),
    id_usuario    INT,                          -- quien hizo el cambio
    CONSTRAINT pk_historial_estado_pedido PRIMARY KEY (id_historial),
    CONSTRAINT fk_historial_estado_pedido_pedido FOREIGN KEY (id_pedido)
        REFERENCES pedido(id_pedido) ON DELETE CASCADE,
    CONSTRAINT fk_historial_estado_pedido_estado FOREIGN KEY (id_estado) REFERENCES estado_pedido(id_estado),
    CONSTRAINT fk_historial_estado_pedido_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario)
);

-- --------------------------------------------------------------------------
-- oferta_asignacion
-- --------------------------------------------------------------------------
CREATE TABLE oferta_asignacion (
    id_oferta        SERIAL,
    id_pedido        INT NOT NULL,
    id_repartidor    INT NOT NULL,
    distancia_km     NUMERIC(6,2) NOT NULL,     -- del repartidor al restaurante
    fecha_oferta     TIMESTAMPTZ NOT NULL DEFAULT now(),
    respuesta        VARCHAR(10) NOT NULL DEFAULT 'pendiente',
    fecha_respuesta  TIMESTAMPTZ,
    CONSTRAINT pk_oferta_asignacion PRIMARY KEY (id_oferta),
    CONSTRAINT fk_oferta_asignacion_pedido FOREIGN KEY (id_pedido) REFERENCES pedido(id_pedido),
    CONSTRAINT fk_oferta_asignacion_repartidor FOREIGN KEY (id_repartidor) REFERENCES repartidor(id_repartidor),
    CONSTRAINT ck_oferta_asignacion_respuesta CHECK (respuesta IN ('pendiente','aceptada','rechazada','expirada'))
);

-- --------------------------------------------------------------------------
-- ubicacion_repartidor
-- --------------------------------------------------------------------------
CREATE TABLE ubicacion_repartidor (
    id_ubicacion   BIGSERIAL,
    id_repartidor  INT NOT NULL,
    id_pedido      INT,
    latitud        NUMERIC(9,6) NOT NULL,
    longitud       NUMERIC(9,6) NOT NULL,
    fecha_hora     TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_ubicacion_repartidor PRIMARY KEY (id_ubicacion),
    CONSTRAINT fk_ubicacion_repartidor_repartidor FOREIGN KEY (id_repartidor) REFERENCES repartidor(id_repartidor),
    CONSTRAINT fk_ubicacion_repartidor_pedido FOREIGN KEY (id_pedido) REFERENCES pedido(id_pedido)
);

-- --------------------------------------------------------------------------
-- tarifa_envio
-- --------------------------------------------------------------------------
CREATE TABLE tarifa_envio (
    id_tarifa  SERIAL,
    km_desde   NUMERIC(6,2) NOT NULL,
    km_hasta   NUMERIC(6,2) NOT NULL,
    precio     NUMERIC(10,2) NOT NULL,
    CONSTRAINT pk_tarifa_envio PRIMARY KEY (id_tarifa),
    CONSTRAINT ck_tarifa_envio_precio CHECK (precio > 0),
    CONSTRAINT ck_tarifa_envio_rango CHECK (km_hasta > km_desde)
);

-- --------------------------------------------------------------------------
-- pago
-- --------------------------------------------------------------------------
CREATE TABLE pago (
    id_pago     SERIAL,
    id_pedido   INT NOT NULL,
    monto       NUMERIC(10,2) NOT NULL,         -- en USD, igual a pedido.total
    moneda      CHAR(3) NOT NULL,
    metodo      VARCHAR(20) NOT NULL DEFAULT 'tarjeta_credito',
    ultimos4    CHAR(4) NOT NULL,
    referencia  VARCHAR(40) NOT NULL,
    estado      VARCHAR(12) NOT NULL DEFAULT 'aprobado',
    fecha       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_pago PRIMARY KEY (id_pago),
    CONSTRAINT uq_pago_pedido UNIQUE (id_pedido),
    CONSTRAINT uq_pago_referencia UNIQUE (referencia),
    CONSTRAINT fk_pago_pedido FOREIGN KEY (id_pedido) REFERENCES pedido(id_pedido),
    CONSTRAINT ck_pago_monto CHECK (monto > 0),
    CONSTRAINT ck_pago_moneda CHECK (moneda IN ('USD','VES')),
    CONSTRAINT ck_pago_ultimos4 CHECK (ultimos4 ~ '^[0-9]{4}$'),
    CONSTRAINT ck_pago_estado CHECK (estado IN ('aprobado','rechazado','reembolsado'))
);

-- --------------------------------------------------------------------------
-- calificacion
-- --------------------------------------------------------------------------
CREATE TABLE calificacion (
    id_calificacion  SERIAL,
    id_pedido        INT NOT NULL,
    tipo             VARCHAR(25) NOT NULL,
    puntaje          SMALLINT NOT NULL,
    comentario       VARCHAR(300),
    fecha            TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_calificacion PRIMARY KEY (id_calificacion),
    CONSTRAINT fk_calificacion_pedido FOREIGN KEY (id_pedido) REFERENCES pedido(id_pedido),
    CONSTRAINT ck_calificacion_tipo CHECK (
        tipo IN ('cliente_a_repartidor','cliente_a_restaurante','repartidor_a_cliente')
    ),
    CONSTRAINT ck_calificacion_puntaje CHECK (puntaje BETWEEN 1 AND 5),
    CONSTRAINT uq_calificacion_pedido_tipo UNIQUE (id_pedido, tipo)
);

-- --------------------------------------------------------------------------
-- parametro_sistema
-- --------------------------------------------------------------------------
CREATE TABLE parametro_sistema (
    clave        VARCHAR(50),
    valor        VARCHAR(100) NOT NULL,
    descripcion  TEXT,
    CONSTRAINT pk_parametro_sistema PRIMARY KEY (clave)
);

-- ==========================================================================
-- Tablas de facturacion (roadmap_bd.txt seccion 8b)
-- ==========================================================================

-- --------------------------------------------------------------------------
-- tasa_bcv (la carga el admin, una por dia)
-- --------------------------------------------------------------------------
CREATE TABLE tasa_bcv (
    id_tasa         SERIAL,
    fecha           DATE NOT NULL,
    tasa_usd        NUMERIC(14,4) NOT NULL,     -- Bs por 1 USD
    id_usuario      INT,                        -- quien la cargo
    fecha_registro  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_tasa_bcv PRIMARY KEY (id_tasa),
    CONSTRAINT uq_tasa_bcv_fecha UNIQUE (fecha),
    CONSTRAINT fk_tasa_bcv_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario),
    CONSTRAINT ck_tasa_bcv_valor CHECK (tasa_usd > 0)
);

-- --------------------------------------------------------------------------
-- correlativo (numeracion SIN huecos; ver 08_facturacion.sql)
-- --------------------------------------------------------------------------
CREATE TABLE correlativo (
    punto_venta     SMALLINT,
    ultimo_numero   INT NOT NULL DEFAULT 0,
    ultimo_control  INT NOT NULL DEFAULT 0,
    CONSTRAINT pk_correlativo PRIMARY KEY (punto_venta),
    CONSTRAINT ck_correlativo_numero CHECK (ultimo_numero >= 0),
    CONSTRAINT ck_correlativo_control CHECK (ultimo_control >= 0)
);

-- --------------------------------------------------------------------------
-- factura (facturas al cliente, de comision y notas de credito)
-- --------------------------------------------------------------------------
CREATE TABLE factura (
    id_factura                  SERIAL,
    tipo                        VARCHAR(20) NOT NULL,
    numero_factura              VARCHAR(13) NOT NULL,   -- PPPP-NNNNNNNN
    numero_control              VARCHAR(9) NOT NULL,    -- PP-NNNNNN
    punto_venta                 SMALLINT NOT NULL,
    estado                      VARCHAR(10) NOT NULL DEFAULT 'emitida',
    id_cliente                  INT,
    id_restaurante               INT,
    id_pedido                   INT,                    -- solo factura_cliente
    id_factura_afectada         INT,                    -- solo nota_credito
    -- Copia de los datos del emisor/receptor al momento de emitir: la factura
    -- no se puede modificar aunque esos datos cambien despues (RN inmutabilidad).
    rif_emisor                  VARCHAR(12) NOT NULL,
    razon_social_emisor         VARCHAR(150) NOT NULL,
    direccion_fiscal_emisor     VARCHAR(250) NOT NULL,
    rif_receptor                 VARCHAR(12),
    razon_social_receptor       VARCHAR(150) NOT NULL,
    direccion_fiscal_receptor   VARCHAR(250),
    periodo_desde                DATE,                  -- solo factura_comision
    periodo_hasta                DATE,
    moneda                       CHAR(3) NOT NULL,
    tasa_bcv                     NUMERIC(14,4) NOT NULL,
    base_imponible_16            NUMERIC(10,2) NOT NULL DEFAULT 0,
    base_exenta                  NUMERIC(10,2) NOT NULL DEFAULT 0,
    monto_no_sujeto               NUMERIC(10,2) NOT NULL DEFAULT 0,   -- la propina
    iva_16                        NUMERIC(10,2) NOT NULL DEFAULT 0,
    igtf                          NUMERIC(10,2) NOT NULL DEFAULT 0,
    total                         NUMERIC(10,2) NOT NULL,             -- en USD
    total_ves                     NUMERIC(14,2) NOT NULL,
    observaciones                 VARCHAR(300),          -- motivo de la nota de credito
    id_usuario                    INT,                   -- quien la genero; NULL = sistema
    fecha_emision                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_factura PRIMARY KEY (id_factura),
    CONSTRAINT uq_factura_numero_factura UNIQUE (numero_factura),
    CONSTRAINT uq_factura_numero_control UNIQUE (numero_control),
    CONSTRAINT fk_factura_correlativo FOREIGN KEY (punto_venta) REFERENCES correlativo(punto_venta),
    CONSTRAINT fk_factura_cliente FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente),
    CONSTRAINT fk_factura_restaurante FOREIGN KEY (id_restaurante) REFERENCES restaurante(id_restaurante),
    CONSTRAINT fk_factura_pedido FOREIGN KEY (id_pedido) REFERENCES pedido(id_pedido),
    CONSTRAINT fk_factura_factura_afectada FOREIGN KEY (id_factura_afectada) REFERENCES factura(id_factura),
    CONSTRAINT fk_factura_usuario FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario),
    CONSTRAINT ck_factura_tipo CHECK (tipo IN ('factura_cliente','factura_comision','nota_credito')),
    CONSTRAINT ck_factura_estado CHECK (estado IN ('emitida','anulada')),
    CONSTRAINT ck_factura_moneda CHECK (moneda IN ('USD','VES')),
    CONSTRAINT ck_factura_tasa_bcv CHECK (tasa_bcv > 0),
    -- Un solo receptor, con FK real (no un id generico).
    CONSTRAINT ck_factura_receptor_unico CHECK (num_nonnulls(id_cliente, id_restaurante) = 1),
    CONSTRAINT ck_factura_cliente_campos CHECK (
        tipo <> 'factura_cliente' OR (id_cliente IS NOT NULL AND id_pedido IS NOT NULL)
    ),
    CONSTRAINT ck_factura_comision_campos CHECK (
        tipo <> 'factura_comision' OR (id_restaurante IS NOT NULL AND periodo_desde IS NOT NULL)
    ),
    CONSTRAINT ck_factura_nota_credito_campos CHECK (
        tipo <> 'nota_credito' OR id_factura_afectada IS NOT NULL
    ),
    CONSTRAINT ck_factura_totales CHECK (
        total = base_imponible_16 + base_exenta + monto_no_sujeto + iva_16 + igtf
    )
);

-- Un pedido solo tiene una factura_cliente (indice unico parcial).
CREATE UNIQUE INDEX uq_factura_pedido ON factura(id_pedido) WHERE tipo = 'factura_cliente';

-- --------------------------------------------------------------------------
-- detalle_factura
-- --------------------------------------------------------------------------
CREATE TABLE detalle_factura (
    id_detalle        SERIAL,
    id_factura        INT NOT NULL,
    id_pedido         INT,                     -- en factura_comision: una linea por pedido
    descripcion       VARCHAR(200) NOT NULL,
    cantidad          NUMERIC(10,2) NOT NULL,
    precio_unitario   NUMERIC(10,2) NOT NULL,
    alicuota_iva      NUMERIC(5,2) NOT NULL,
    no_sujeto         BOOLEAN NOT NULL DEFAULT FALSE,   -- TRUE solo para la propina
    base_item         NUMERIC(10,2) NOT NULL,           -- cantidad * precio_unitario
    iva_item          NUMERIC(10,2) NOT NULL,
    subtotal_item     NUMERIC(10,2) NOT NULL,           -- base_item + iva_item
    CONSTRAINT pk_detalle_factura PRIMARY KEY (id_detalle),
    CONSTRAINT fk_detalle_factura_factura FOREIGN KEY (id_factura) REFERENCES factura(id_factura),
    CONSTRAINT fk_detalle_factura_pedido FOREIGN KEY (id_pedido) REFERENCES pedido(id_pedido),
    CONSTRAINT ck_detalle_factura_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_detalle_factura_precio CHECK (precio_unitario >= 0),
    CONSTRAINT ck_detalle_factura_alicuota CHECK (alicuota_iva IN (0, 16))
);

-- --------------------------------------------------------------------------
-- liquidacion_repartidor (pago periodico al repartidor; no es factura fiscal)
-- --------------------------------------------------------------------------
CREATE TABLE liquidacion_repartidor (
    id_liquidacion  SERIAL,
    numero          VARCHAR(12) NOT NULL,       -- LIQ-NNNNNNNN
    id_repartidor   INT NOT NULL,
    periodo_desde   DATE NOT NULL,
    periodo_hasta   DATE NOT NULL,
    viajes          INT NOT NULL,
    total_envios    NUMERIC(10,2) NOT NULL,
    total_propinas  NUMERIC(10,2) NOT NULL,
    total           NUMERIC(10,2) NOT NULL,
    fecha_emision   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_liquidacion_repartidor PRIMARY KEY (id_liquidacion),
    CONSTRAINT uq_liquidacion_repartidor_numero UNIQUE (numero),
    CONSTRAINT fk_liquidacion_repartidor_repartidor FOREIGN KEY (id_repartidor) REFERENCES repartidor(id_repartidor),
    CONSTRAINT ck_liquidacion_repartidor_viajes CHECK (viajes >= 0),
    CONSTRAINT ck_liquidacion_repartidor_periodo CHECK (periodo_hasta >= periodo_desde),
    CONSTRAINT ck_liquidacion_repartidor_total CHECK (total = total_envios + total_propinas)
);

-- --------------------------------------------------------------------------
-- detalle_liquidacion
-- --------------------------------------------------------------------------
CREATE TABLE detalle_liquidacion (
    id_liquidacion  INT NOT NULL,
    id_pedido       INT NOT NULL,               -- un pedido no se liquida dos veces
    costo_envio     NUMERIC(10,2) NOT NULL,
    propina         NUMERIC(10,2) NOT NULL,
    CONSTRAINT pk_detalle_liquidacion PRIMARY KEY (id_liquidacion, id_pedido),
    CONSTRAINT uq_detalle_liquidacion_pedido UNIQUE (id_pedido),
    CONSTRAINT fk_detalle_liquidacion_liquidacion FOREIGN KEY (id_liquidacion)
        REFERENCES liquidacion_repartidor(id_liquidacion),
    CONSTRAINT fk_detalle_liquidacion_pedido FOREIGN KEY (id_pedido) REFERENCES pedido(id_pedido)
);
