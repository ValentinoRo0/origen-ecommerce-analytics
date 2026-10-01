/*
===============================================================================
ORIGEN — Datos maestros (Fase 4, Bloque 2 aprobado)
===============================================================================
Implementa literalmente el catálogo aprobado en Bloque 2. Idempotente: cada
INSERT está guardado con IF NOT EXISTS contra la clave de negocio
correspondiente (nunca contra un ID, que es IDENTITY y no es estable).

Nota sobre DimMotivo y DimProducto/DimTienda/DimCliente: estas tablas NO
tienen UNIQUE constraint sobre su nombre — a diferencia de DimEstado,
DimArea y DimSKU, que sí lo tienen. Por eso aquí el guard IF NOT EXISTS es
imprescindible para que este script sea seguro de re-ejecutar.
===============================================================================
*/

USE OrigenDB;
GO

-- -----------------------------------------------------------------------------
-- DimEstado — 14 estados exactos de 01_procesos_y_reglas.md, sección 3.2
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Rechazado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Rechazado', 1);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Pedido creado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Pedido creado', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Asignado a picking')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Asignado a picking', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Picking en proceso')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Picking en proceso', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Incidencia de picking')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Incidencia de picking', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Empaquetado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Empaquetado', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'En tránsito')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'En tránsito', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Entregado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Entregado', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Disponible para recojo')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Disponible para recojo', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Vencido')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Vencido', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Recojo por cliente')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Recojo por cliente', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Completado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Completado', 1);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Cancelado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Cancelado', 1);

-- 'Devolución' NO es un estado del flujo operativo: es un EVENTO posterior
-- a Completado (se registra en FactDevolucion vía sp_RegistrarDevolucion,
-- que jamás cambia EstadoActualID ni inserta en FactHistorialEstadoLinea).
-- El registro se conserva aquí solo por integridad referencial y por
-- mantener el catálogo completo de 14 estados — ningún procedimiento lo
-- usa como origen ni destino de una transición (decisión de diseño de la
-- máquina de estados de Origen: la devolución queda fuera del flujo).
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Devolución')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Devolución', 1);

-- -----------------------------------------------------------------------------
-- DimMotivo — 12 motivos, 4 tipos
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.DimMotivo WHERE NombreMotivo = N'voluntaria' AND TipoMotivo = N'cancelacion')
    INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'cancelacion', N'voluntaria');
IF NOT EXISTS (SELECT 1 FROM dbo.DimMotivo WHERE NombreMotivo = N'incidencia_picking' AND TipoMotivo = N'cancelacion')
    INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'cancelacion', N'incidencia_picking');
IF NOT EXISTS (SELECT 1 FROM dbo.DimMotivo WHERE NombreMotivo = N'vencimiento' AND TipoMotivo = N'cancelacion')
    INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'cancelacion', N'vencimiento');
IF NOT EXISTS (SELECT 1 FROM dbo.DimMotivo WHERE NombreMotivo = N'no_encontrado' AND TipoMotivo = N'incidencia')
    INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'incidencia', N'no_encontrado');
IF NOT EXISTS (SELECT 1 FROM dbo.DimMotivo WHERE NombreMotivo = N'cantidad_insuficiente' AND TipoMotivo = N'incidencia')
    INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'incidencia', N'cantidad_insuficiente');
IF NOT EXISTS (SELECT 1 FROM dbo.DimMotivo WHERE NombreMotivo = N'dañado' AND TipoMotivo = N'incidencia')
    INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'incidencia', N'dañado');
IF NOT EXISTS (SELECT 1 FROM dbo.DimMotivo WHERE NombreMotivo = N'recepcion_incompleta' AND TipoMotivo = N'incidencia')
    INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'incidencia', N'recepcion_incompleta');
IF NOT EXISTS (SELECT 1 FROM dbo.DimMotivo WHERE NombreMotivo = N'conteo_fisico' AND TipoMotivo = N'ajuste_stock')
    INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'ajuste_stock', N'conteo_fisico');
IF NOT EXISTS (
    SELECT 1
    FROM dbo.DimMotivo
    WHERE TipoMotivo = 'ajuste_stock'
      AND NombreMotivo = 'retorno_recojo_vencido'
)
BEGIN
    INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo)
    VALUES ('ajuste_stock', 'retorno_recojo_vencido');
END;
IF NOT EXISTS (SELECT 1 FROM dbo.DimMotivo WHERE NombreMotivo = N'talla_incorrecta' AND TipoMotivo = N'devolucion')
    INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'devolucion', N'talla_incorrecta');
IF NOT EXISTS (SELECT 1 FROM dbo.DimMotivo WHERE NombreMotivo = N'no_cumple_expectativa' AND TipoMotivo = N'devolucion')
    INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'devolucion', N'no_cumple_expectativa');
IF NOT EXISTS (SELECT 1 FROM dbo.DimMotivo WHERE NombreMotivo = N'producto_dañado' AND TipoMotivo = N'devolucion')
    INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'devolucion', N'producto_dañado');

-- -----------------------------------------------------------------------------
-- DimArea — 4 áreas
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.DimArea WHERE NombreArea = N'Tienda / Picking')
    INSERT INTO dbo.DimArea (NombreArea) VALUES (N'Tienda / Picking');
IF NOT EXISTS (SELECT 1 FROM dbo.DimArea WHERE NombreArea = N'Operaciones E-commerce')
    INSERT INTO dbo.DimArea (NombreArea) VALUES (N'Operaciones E-commerce');
IF NOT EXISTS (SELECT 1 FROM dbo.DimArea WHERE NombreArea = N'Abastecimiento')
    INSERT INTO dbo.DimArea (NombreArea) VALUES (N'Abastecimiento');
IF NOT EXISTS (SELECT 1 FROM dbo.DimArea WHERE NombreArea = N'CD')
    INSERT INTO dbo.DimArea (NombreArea) VALUES (N'CD');

-- -----------------------------------------------------------------------------
-- DimTienda — 4 tiendas
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.DimTienda WHERE NombreTienda = N'Web Nacional')
    INSERT INTO dbo.DimTienda (NombreTienda, Distrito, Ciudad) VALUES (N'Web Nacional', NULL, N'Nacional');
IF NOT EXISTS (SELECT 1 FROM dbo.DimTienda WHERE NombreTienda = N'Jockey Plaza')
    INSERT INTO dbo.DimTienda (NombreTienda, Distrito, Ciudad) VALUES (N'Jockey Plaza', N'Surco', N'Lima');
IF NOT EXISTS (SELECT 1 FROM dbo.DimTienda WHERE NombreTienda = N'Real Plaza Arequipa')
    INSERT INTO dbo.DimTienda (NombreTienda, Distrito, Ciudad) VALUES (N'Real Plaza Arequipa', NULL, N'Arequipa');
IF NOT EXISTS (SELECT 1 FROM dbo.DimTienda WHERE NombreTienda = N'Mall Aventura Trujillo')
    INSERT INTO dbo.DimTienda (NombreTienda, Distrito, Ciudad) VALUES (N'Mall Aventura Trujillo', NULL, N'Trujillo');

-- -----------------------------------------------------------------------------
-- DimCliente — 6 clientes ficticios
-- -----------------------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.DimCliente WHERE Email = N'ana.torres@correo.com')
    INSERT INTO dbo.DimCliente (NombreCliente, Email) VALUES (N'Ana Torres', N'ana.torres@correo.com');
IF NOT EXISTS (SELECT 1 FROM dbo.DimCliente WHERE Email = N'luis.mamani@correo.com')
    INSERT INTO dbo.DimCliente (NombreCliente, Email) VALUES (N'Luis Mamani', N'luis.mamani@correo.com');
IF NOT EXISTS (SELECT 1 FROM dbo.DimCliente WHERE Email = N'carla.rojas@correo.com')
    INSERT INTO dbo.DimCliente (NombreCliente, Email) VALUES (N'Carla Rojas', N'carla.rojas@correo.com');
IF NOT EXISTS (SELECT 1 FROM dbo.DimCliente WHERE Email = N'jorge.paredes@correo.com')
    INSERT INTO dbo.DimCliente (NombreCliente, Email) VALUES (N'Jorge Paredes', N'jorge.paredes@correo.com');
IF NOT EXISTS (SELECT 1 FROM dbo.DimCliente WHERE Email = N'maria.quispe@correo.com')
    INSERT INTO dbo.DimCliente (NombreCliente, Email) VALUES (N'María Quispe', N'maria.quispe@correo.com');
IF NOT EXISTS (SELECT 1 FROM dbo.DimCliente WHERE Email = N'diego.flores@correo.com')
    INSERT INTO dbo.DimCliente (NombreCliente, Email) VALUES (N'Diego Flores', N'diego.flores@correo.com');

-- -----------------------------------------------------------------------------
-- DimProducto + DimSKU — 6 productos, 14 SKU (formato [A-Z][0-9]{5})
-- -----------------------------------------------------------------------------
DECLARE @PID INT;

IF NOT EXISTS (SELECT 1 FROM dbo.DimProducto WHERE NombreProducto = N'Polo básico')
    INSERT INTO dbo.DimProducto (NombreProducto, Categoria, Marca) VALUES (N'Polo básico', N'Ropa', N'Origen');
SELECT @PID = ProductoID FROM dbo.DimProducto WHERE NombreProducto = N'Polo básico';
IF NOT EXISTS (SELECT 1 FROM dbo.DimSKU WHERE CodigoSKU = N'A10001')
    INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'A10001', @PID, N'M', N'Negro');
IF NOT EXISTS (SELECT 1 FROM dbo.DimSKU WHERE CodigoSKU = N'A10002')
    INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'A10002', @PID, N'L', N'Negro');
IF NOT EXISTS (SELECT 1 FROM dbo.DimSKU WHERE CodigoSKU = N'A10003')
    INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'A10003', @PID, N'M', N'Blanco');

IF NOT EXISTS (SELECT 1 FROM dbo.DimProducto WHERE NombreProducto = N'Camisa Oxford')
    INSERT INTO dbo.DimProducto (NombreProducto, Categoria, Marca) VALUES (N'Camisa Oxford', N'Ropa', N'Origen');
SELECT @PID = ProductoID FROM dbo.DimProducto WHERE NombreProducto = N'Camisa Oxford';
IF NOT EXISTS (SELECT 1 FROM dbo.DimSKU WHERE CodigoSKU = N'A20001')
    INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'A20001', @PID, N'M', N'Azul');
IF NOT EXISTS (SELECT 1 FROM dbo.DimSKU WHERE CodigoSKU = N'A20002')
    INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'A20002', @PID, N'L', N'Azul');

IF NOT EXISTS (SELECT 1 FROM dbo.DimProducto WHERE NombreProducto = N'Jean slim')
    INSERT INTO dbo.DimProducto (NombreProducto, Categoria, Marca) VALUES (N'Jean slim', N'Ropa', N'Origen');
SELECT @PID = ProductoID FROM dbo.DimProducto WHERE NombreProducto = N'Jean slim';
IF NOT EXISTS (SELECT 1 FROM dbo.DimSKU WHERE CodigoSKU = N'A30001')
    INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'A30001', @PID, N'32', N'Azul');
IF NOT EXISTS (SELECT 1 FROM dbo.DimSKU WHERE CodigoSKU = N'A30002')
    INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'A30002', @PID, N'34', N'Azul');

IF NOT EXISTS (SELECT 1 FROM dbo.DimProducto WHERE NombreProducto = N'Zapatilla urbana')
    INSERT INTO dbo.DimProducto (NombreProducto, Categoria, Marca) VALUES (N'Zapatilla urbana', N'Calzado', N'Origen');
SELECT @PID = ProductoID FROM dbo.DimProducto WHERE NombreProducto = N'Zapatilla urbana';
IF NOT EXISTS (SELECT 1 FROM dbo.DimSKU WHERE CodigoSKU = N'A40001')
    INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'A40001', @PID, N'40', N'Blanco');
IF NOT EXISTS (SELECT 1 FROM dbo.DimSKU WHERE CodigoSKU = N'A40002')
    INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'A40002', @PID, N'42', N'Blanco');
IF NOT EXISTS (SELECT 1 FROM dbo.DimSKU WHERE CodigoSKU = N'A40003')
    INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'A40003', @PID, N'44', N'Blanco');

IF NOT EXISTS (SELECT 1 FROM dbo.DimProducto WHERE NombreProducto = N'Mochila urbana')
    INSERT INTO dbo.DimProducto (NombreProducto, Categoria, Marca) VALUES (N'Mochila urbana', N'Accesorios', N'Origen');
SELECT @PID = ProductoID FROM dbo.DimProducto WHERE NombreProducto = N'Mochila urbana';
IF NOT EXISTS (SELECT 1 FROM dbo.DimSKU WHERE CodigoSKU = N'A50001')
    INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'A50001', @PID, N'Única', N'Negro');
IF NOT EXISTS (SELECT 1 FROM dbo.DimSKU WHERE CodigoSKU = N'A50002')
    INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'A50002', @PID, N'Única', N'Gris');

IF NOT EXISTS (SELECT 1 FROM dbo.DimProducto WHERE NombreProducto = N'Perfume Origen Signature')
    INSERT INTO dbo.DimProducto (NombreProducto, Categoria, Marca) VALUES (N'Perfume Origen Signature', N'Perfumería', N'Origen');
SELECT @PID = ProductoID FROM dbo.DimProducto WHERE NombreProducto = N'Perfume Origen Signature';
IF NOT EXISTS (SELECT 1 FROM dbo.DimSKU WHERE CodigoSKU = N'A60001')
    INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'A60001', @PID, N'50ml', N'—');
IF NOT EXISTS (SELECT 1 FROM dbo.DimSKU WHERE CodigoSKU = N'A60002')
    INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'A60002', @PID, N'100ml', N'—');

-- -----------------------------------------------------------------------------
-- DimFecha — 1 ene al 31 mar 2026 (90 días), generado, no manual.
-- Campaña 'Cyber Origen' marcada del 15 al 21 de marzo (única, no arbitraria:
-- responde a la pregunta de negocio de la sección 7 de 00_contexto_y_alcance.md
-- sobre impacto de campañas en incidencias/cancelaciones).
-- -----------------------------------------------------------------------------
;WITH Fechas AS (
    SELECT CAST('2026-01-01' AS DATE) AS Fecha
    UNION ALL
    SELECT DATEADD(DAY, 1, Fecha) FROM Fechas WHERE Fecha < '2026-03-31'
)
INSERT INTO dbo.DimFecha (FechaID, Fecha, Anio, Mes, NombreMes, Dia, DiaSemana, EsCampania, NombreCampania)
SELECT
    CONVERT(INT, FORMAT(Fecha, 'yyyyMMdd')),
    Fecha,
    YEAR(Fecha),
    MONTH(Fecha),
    DATENAME(MONTH, Fecha),
    DAY(Fecha),
    DATENAME(WEEKDAY, Fecha),
    CASE WHEN Fecha BETWEEN '2026-03-15' AND '2026-03-21' THEN 1 ELSE 0 END,
    CASE WHEN Fecha BETWEEN '2026-03-15' AND '2026-03-21' THEN N'Cyber Origen' ELSE NULL END
FROM Fechas
WHERE NOT EXISTS (SELECT 1 FROM dbo.DimFecha df WHERE df.Fecha = Fechas.Fecha)
OPTION (MAXRECURSION 100);
GO

-- Verificación de conteos
SELECT 'DimEstado' AS Tabla, COUNT(*) AS Filas FROM dbo.DimEstado
UNION ALL SELECT 'DimMotivo', COUNT(*) FROM dbo.DimMotivo
UNION ALL SELECT 'DimArea', COUNT(*) FROM dbo.DimArea
UNION ALL SELECT 'DimTienda', COUNT(*) FROM dbo.DimTienda
UNION ALL SELECT 'DimCliente', COUNT(*) FROM dbo.DimCliente
UNION ALL SELECT 'DimProducto', COUNT(*) FROM dbo.DimProducto
UNION ALL SELECT 'DimSKU', COUNT(*) FROM dbo.DimSKU
UNION ALL SELECT 'DimFecha', COUNT(*) FROM dbo.DimFecha;
-- Esperado: DimEstado=14, DimMotivo=12, DimArea=4, DimTienda=4, DimCliente=6,
-- DimProducto=6, DimSKU=14, DimFecha=90
GO
