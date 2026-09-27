/*
===============================================================================
ORIGEN — Pruebas básicas de sp_CrearPedido
Fase 3 — Implementación SQL Server
===============================================================================
CORRECCIONES respecto a la versión anterior:
1. Código de SKU cambiado de 'TEST02' a 'T00002' para respetar el formato
   documentado en 02_modelo_de_datos.md (1 letra + 5 dígitos). No había
   ningún CHECK que lo hiciera fallar técnicamente, pero mantener la
   convención evita inconsistencia en los propios datos de prueba.
2. El Caso 4 ahora usa una SEGUNDA TIENDA REAL (existe en DimTienda) que
   simplemente no tiene fila presembrada en StockSKUTienda para este SKU —
   en vez de una TiendaID inventada (999999). Esto prueba el escenario
   real que nos interesa: "la tienda existe, el SKU existe, pero esa
   combinación específica no fue presembrada", no una tienda que no existe
   en absoluto.

No se envuelve en una transacción externa (ver versión anterior y la
corrección sobre XACT_ABORT) — cada EXEC corre de forma independiente,
igual que en el uso real, y la limpieza al final es con DELETE explícito.

Requisito: haber ejecutado ya 09_stock_sku_tienda.sql,
03_actualizar_stock_sku_tienda.sql y 01_sp_crear_pedido.sql.
===============================================================================
*/

USE OrigenDB;
GO

SET NOCOUNT ON;

DECLARE @ProductoID INT, @SKUID INT, @TiendaID1 INT, @TiendaID2 INT, @ClienteID INT, @FechaID INT;
DECLARE @LineaID INT, @Resultado VARCHAR(20);
DECLARE @StockSistema INT, @StockReservado INT;

-- -----------------------------------------------------------------------------
-- Datos mínimos: 1 producto/SKU, DOS tiendas (una con stock presembrado,
-- otra sin), 1 cliente, 1 fecha, y los estados 'Pedido creado' / 'Rechazado'.
-- -----------------------------------------------------------------------------
INSERT INTO dbo.DimProducto (NombreProducto, Categoria, Marca)
VALUES (N'Producto de prueba', N'Categoria de prueba', NULL);
SET @ProductoID = SCOPE_IDENTITY();

INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color)
VALUES (N'T00002', @ProductoID, N'M', N'Azul');
SET @SKUID = SCOPE_IDENTITY();

INSERT INTO dbo.DimTienda (NombreTienda, Distrito, Ciudad)
VALUES (N'Tienda de prueba 1', NULL, N'Lima');
SET @TiendaID1 = SCOPE_IDENTITY();

INSERT INTO dbo.DimTienda (NombreTienda, Distrito, Ciudad)
VALUES (N'Tienda de prueba 2', NULL, N'Lima');
SET @TiendaID2 = SCOPE_IDENTITY();

INSERT INTO dbo.DimCliente (NombreCliente, Email)
VALUES (N'Cliente de prueba', N'prueba2@origen.com');
SET @ClienteID = SCOPE_IDENTITY();

IF NOT EXISTS (SELECT 1 FROM dbo.DimFecha WHERE FechaID = 20260102)
BEGIN
    INSERT INTO dbo.DimFecha (FechaID, Fecha, Anio, Mes, NombreMes, Dia, DiaSemana, EsCampania, NombreCampania)
    VALUES (20260102, '2026-01-02', 2026, 1, N'Enero', 2, N'Viernes', 0, NULL);
END
SET @FechaID = 20260102;

-- Estos dos estados son PERMANENTES (parte del diseño real), no se borran al final
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Pedido creado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Pedido creado', 0);

IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Rechazado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Rechazado', 1);

-- Pre-siembra SOLO para Tienda 1: 1 unidad disponible.
-- Tienda 2 existe en DimTienda, pero deliberadamente NO tiene fila aquí.
INSERT INTO dbo.StockSKUTienda (SKUID, TiendaID, StockSistema, StockReservado)
VALUES (@SKUID, @TiendaID1, 1, 0);

PRINT N'--- Datos de prueba creados. Tienda 1: 1 unidad presembrada. Tienda 2: sin presiembra. ---';
PRINT N'';

-- -----------------------------------------------------------------------------
-- CASO 1: Stock suficiente en Tienda 1 → debe crear la línea (CREADO)
-- -----------------------------------------------------------------------------
BEGIN TRY
    EXEC dbo.sp_CrearPedido
        @PedidoID = 900001, @ClienteID = @ClienteID, @SKUID = @SKUID,
        @TiendaID = @TiendaID1, @FechaID = @FechaID, @Canal = N'recojo',
        @Cantidad = 1, @LineaID = @LineaID OUTPUT, @Resultado = @Resultado OUTPUT;

    SELECT @StockSistema = StockSistema, @StockReservado = StockReservado
    FROM dbo.StockSKUTienda WHERE SKUID = @SKUID AND TiendaID = @TiendaID1;

    IF @Resultado = N'CREADO' AND @StockReservado = 1
        PRINT N'[OK]     Caso 1 — Pedido creado, StockReservado ahora en 1 (esperado).';
    ELSE
        PRINT N'[FALLO]  Caso 1 — Resultado: ' + @Resultado + N', StockReservado: ' + CAST(@StockReservado AS VARCHAR);
END TRY
BEGIN CATCH
    PRINT N'[ERROR]  Caso 1 no debía fallar: ' + ERROR_MESSAGE();
END CATCH;

-- -----------------------------------------------------------------------------
-- CASO 2: Ya no queda disponible en Tienda 1 (1 sistema, 1 reservado) →
-- debe RECHAZAR
-- -----------------------------------------------------------------------------
BEGIN TRY
    EXEC dbo.sp_CrearPedido
        @PedidoID = 900002, @ClienteID = @ClienteID, @SKUID = @SKUID,
        @TiendaID = @TiendaID1, @FechaID = @FechaID, @Canal = N'recojo',
        @Cantidad = 1, @LineaID = @LineaID OUTPUT, @Resultado = @Resultado OUTPUT;

    IF @Resultado = N'RECHAZADO'
        PRINT N'[OK]     Caso 2 — Segundo pedido correctamente RECHAZADO (sin stock disponible).';
    ELSE
        PRINT N'[FALLO]  Caso 2 — Se esperaba RECHAZADO, se obtuvo: ' + @Resultado;
END TRY
BEGIN CATCH
    PRINT N'[ERROR]  Caso 2 no debía fallar con excepción: ' + ERROR_MESSAGE();
END CATCH;

-- -----------------------------------------------------------------------------
-- CASO 3: Cantidad inválida (0) → debe lanzar el error 51001
-- -----------------------------------------------------------------------------
BEGIN TRY
    EXEC dbo.sp_CrearPedido
        @PedidoID = 900003, @ClienteID = @ClienteID, @SKUID = @SKUID,
        @TiendaID = @TiendaID1, @FechaID = @FechaID, @Canal = N'recojo',
        @Cantidad = 0, @LineaID = @LineaID OUTPUT, @Resultado = @Resultado OUTPUT;

    PRINT N'[FALLO]  Caso 3 — Se permitió Cantidad = 0, y NO debía permitirse.';
END TRY
BEGIN CATCH
    PRINT N'[OK]     Caso 3 — Rechazado correctamente: ' + ERROR_MESSAGE();
END CATCH;

-- -----------------------------------------------------------------------------
-- CASO 4: Tienda 2 EXISTE, SKU EXISTE, pero esa combinación no fue
-- presembrada en StockSKUTienda → debe lanzar el error 51002
-- -----------------------------------------------------------------------------
BEGIN TRY
    EXEC dbo.sp_CrearPedido
        @PedidoID = 900004, @ClienteID = @ClienteID, @SKUID = @SKUID,
        @TiendaID = @TiendaID2, @FechaID = @FechaID, @Canal = N'recojo',
        @Cantidad = 1, @LineaID = @LineaID OUTPUT, @Resultado = @Resultado OUTPUT;

    PRINT N'[FALLO]  Caso 4 — Se permitió operar sin fila de stock presembrada, y NO debía permitirse.';
END TRY
BEGIN CATCH
    PRINT N'[OK]     Caso 4 — Rechazado correctamente: ' + ERROR_MESSAGE();
END CATCH;

PRINT N'';
PRINT N'--- Verificación de estado final antes de limpiar ---';

SELECT * FROM dbo.StockSKUTienda WHERE SKUID = @SKUID;
SELECT * FROM dbo.FactPedidoDetalle WHERE PedidoID IN (900001, 900002, 900003, 900004);
SELECT * FROM dbo.FactMovimientoInventario WHERE SKUID = @SKUID;

PRINT N'';
PRINT N'--- Limpiando datos de prueba (DELETE explícito, sin ROLLBACK) ---';

DELETE FROM dbo.FactMovimientoInventario WHERE SKUID = @SKUID;

DELETE fh
FROM dbo.FactHistorialEstadoLinea fh
INNER JOIN dbo.FactPedidoDetalle fp ON fp.LineaID = fh.LineaID
WHERE fp.PedidoID IN (900001, 900002, 900003, 900004);

DELETE FROM dbo.FactPedidoDetalle WHERE PedidoID IN (900001, 900002, 900003, 900004);

DELETE FROM dbo.StockSKUTienda WHERE SKUID = @SKUID;

DELETE FROM dbo.DimCliente WHERE ClienteID = @ClienteID;
DELETE FROM dbo.DimSKU WHERE SKUID = @SKUID;
DELETE FROM dbo.DimProducto WHERE ProductoID = @ProductoID;
DELETE FROM dbo.DimTienda WHERE TiendaID IN (@TiendaID1, @TiendaID2);

-- DimFecha y DimEstado NO se borran: son datos legítimos y reutilizables.

PRINT N'--- Limpieza completada. ---';
GO
