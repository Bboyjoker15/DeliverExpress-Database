-- ==========================================================================
-- DeliverExpress - 02_catalogos.sql
-- Datos de catalogo: estados, parametros, correlativo, tarifas, categorias
-- y zonas. roadmap_bd.txt seccion 4. Estos valores son el contrato que
-- asumen el backend y el frontend: mismos codigos, claves e IDs.
-- ==========================================================================
SET search_path TO deliverexpress;

-- --------------------------------------------------------------------------
-- estado_pedido (IDs fijos, iguales a los que usa fn_cambiar_estado)
-- --------------------------------------------------------------------------
INSERT INTO estado_pedido (id_estado, codigo, nombre, orden) VALUES
    (1, 'recibido',           'Recibido',            1),
    (2, 'en_preparacion',     'En preparacion',      2),
    (3, 'listo_para_retirar', 'Listo para retirar',  3),
    (4, 'en_camino',          'En camino',           4),
    (5, 'entregado',          'Entregado',           5),
    (6, 'cancelado',          'Cancelado',           6);

-- --------------------------------------------------------------------------
-- parametro_sistema (comision, umbrales, velocidades, IVA/IGTF, datos del
-- emisor de facturas). Nada de esto se escribe en el codigo del backend.
-- --------------------------------------------------------------------------
INSERT INTO parametro_sistema (clave, valor, descripcion) VALUES
    ('comision_plataforma',      '0.15', 'Porcentaje de comision de la plataforma sobre el subtotal de productos'),
    ('rechazo_umbral',           '0.30', 'Tasa de rechazo de ofertas que baja la prioridad del repartidor'),
    ('rechazo_ventana',          '20',   'Cantidad de ofertas recientes que se evaluan para la tasa de rechazo'),
    ('rechazo_minimo',           '5',    'Ofertas minimas respondidas antes de evaluar la tasa de rechazo'),
    ('calificacion_minima',      '3.0',  'Calificacion promedio minima antes de marcar en_revision'),
    ('calificaciones_minimas',   '10',   'Calificaciones minimas antes de evaluar el promedio'),
    ('oferta_expira_seg',        '60',   'Segundos que tiene un repartidor para aceptar una oferta'),
    ('velocidad_bicicleta_kmh',  '15',   'Velocidad promedio de bicicleta, en km/h'),
    ('velocidad_moto_kmh',       '30',   'Velocidad promedio de moto, en km/h'),
    ('velocidad_auto_kmh',       '25',   'Velocidad promedio de auto, en km/h'),
    ('iva_general',              '0.16', 'IVA de productos no exentos, envio y comision de la plataforma'),
    ('igtf',                     '0.03', 'IGTF sobre el total (con IVA y propina) si el pago es en USD'),
    ('punto_venta',              '1',    'Punto de venta usado para el correlativo de facturas'),
    ('emisor_rif',               'J-12345678-9', 'RIF ficticio del emisor de las facturas'),
    ('emisor_razon_social',      'DeliverExpress C.A.', 'Razon social del emisor de las facturas'),
    ('emisor_direccion_fiscal',  'Av. Guayana, Alta Vista, Puerto Ordaz, estado Bolivar', 'Direccion fiscal ficticia del emisor');

-- --------------------------------------------------------------------------
-- correlativo: una sola fila para el punto de venta 1 (coincide con el
-- parametro punto_venta de arriba)
-- --------------------------------------------------------------------------
INSERT INTO correlativo (punto_venta, ultimo_numero, ultimo_control) VALUES (1, 0, 0);

-- --------------------------------------------------------------------------
-- tarifa_envio (USD). Mas de 20 km = FUERA_DE_COBERTURA (no hay rango).
-- --------------------------------------------------------------------------
INSERT INTO tarifa_envio (km_desde, km_hasta, precio) VALUES
    (0.00,  2.00,  1.50),
    (2.00,  5.00,  2.50),
    (5.00,  10.00, 4.00),
    (10.00, 20.00, 6.00);

-- --------------------------------------------------------------------------
-- categoria
-- --------------------------------------------------------------------------
INSERT INTO categoria (nombre) VALUES
    ('Rapida'),
    ('Pizzeria'),
    ('Parrilla'),
    ('Comida criolla'),
    ('Sushi'),
    ('Pollo'),
    ('Arepera'),
    ('Postres');

-- --------------------------------------------------------------------------
-- zona (Puerto Ordaz, estado Bolivar). Coordenadas del centro de cada sector
-- tomadas de OpenStreetMap/Nominatim (roadmap_bd §4).
-- --------------------------------------------------------------------------
INSERT INTO zona (nombre, descripcion, latitud_centro, longitud_centro) VALUES
    ('Alta Vista',      'Sector Alta Vista, Parroquia Unare, Puerto Ordaz',           8.295521, -62.733559),
    ('Castillito',      'Sector Castillito, Parroquia Universidad, Puerto Ordaz',      8.315300, -62.709811),
    ('Unare',           'Sector Unare, Parroquia Unare, Puerto Ordaz',                 8.279810, -62.763738),
    ('Villa Asia',      'Sector Villa Asia, Parroquia Universidad, Puerto Ordaz',      8.282497, -62.723201),
    ('Los Olivos',      'Sector Los Olivos, Puerto Ordaz',                             8.279932, -62.716588),
    ('Villa Colombia',  'Sector Villa Colombia, Puerto Ordaz',                         8.308264, -62.714357),
    ('Core 8',          'Sector Core 8, Parroquia Unare, Puerto Ordaz',                8.232894, -62.821023),
    ('Chilemex',        'Sector Chilemex, Parroquia Cachamay, Puerto Ordaz',           8.307007, -62.724913);
