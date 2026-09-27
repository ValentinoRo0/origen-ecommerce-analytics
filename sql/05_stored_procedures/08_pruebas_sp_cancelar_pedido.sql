/*
===============================================================================
ORIGEN — Pruebas de sp_CancelarPedido (ampliadas, 2ª ronda)
Fase 3 — Implementación SQL Server
===============================================================================
Casos 1-5: igual que la versión anterior (voluntaria exitosa, doble
cancelación, motivo incorrecto, incidencia_picking exitosa, IncidenciaID
incorrecto).

NUEVOS:
6. Cancelación voluntaria desde Empaquetado → debe fallar con el error
   51019 (DECISIÓN PENDIENTE), y se reporta como tal, no como fallo técnico.
7. Reserva activa distinta de Cantidad (inconsistencia simulada
   insertando manualmente una LIBERACION_RESERVA parcial) → debe
   rechazarse, no liberar parcialmente.
===============================================================================
*/

USE OrigenDB;
GO

SET NOCOUNT ON;

DECLARE @ProductoID INT, @SKUID INT, @TiendaID INT, @ClienteID INT, @FechaID INT;
DECLARE @LineaID1 INT, @LineaID2 INT, @LineaID3 INT, @LineaID4 INT;
DECLARE @Resultado VARCHAR(20), @IncidenciaID INT;
DECLARE @MotivoVoluntariaID INT, @MotivoIncidenciaPickingID INT, @MotivoNoEncontradoID INT;
DECLARE @StockReservado INT;

INSERT INTO dbo.DimProducto (NombreProducto, Categoria, Marca) VALUES (N'Producto de prueba', N'Categoria de prueba', NULL);
SET @ProductoID = SCOPE_IDENTITY();
INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'T00003', @ProductoID, N'M', N'Azul');
SET @SKUID = SCOPE_IDENTITY();
INSERT INTO dbo.DimTienda (NombreTienda, Distrito, Ciudad) VALUES (N'Tienda de prueba', NULL, N'Lima');
SET @TiendaID = SCOPE_IDENTITY();
INSERT INTO dbo.DimCliente (NombreCliente, Email) VALUES (N'Cliente de prueba', N'prueba3@origen.com');
SET @ClienteID = SCOPE_IDENTITY();

IF NOT EXISTS (SELECT 1 FROM dbo.DimFecha WHERE FechaID = 20260103)
    INSERT INTO dbo.DimFecha (FechaID, Fecha, Anio, Mes, NombreMes, Dia, DiaSemana, EsCampania, NombreCampania)
    VALUES (20260103, '2026-01-03', 2026, 1, N'Enero', 3, N'Sábado', 0, NULL);
SET @FechaID = 20260103;

IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Pedido creado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Pedido creado', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Incidencia de picking')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Incidencia de picking', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Empaquetado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Empaquetado', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Cancelado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Cancelado', 1);

IF NOT EXISTS (SELECT 1 FROM dbo.DimArea WHERE NombreArea = N'Tienda / Picking')
    INSERT INTO dbo.DimArea (NombreArea) VALUES (N'Tienda / Picking');

INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'cancelacion', N'voluntaria');
SET @MotivoVoluntariaID = SCOPE_IDENTITY();
INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'cancelacion', N'incidencia_picking');
SET @MotivoIncidenciaPickingID = SCOPE_IDENTITY();
INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'incidencia', N'no_encontrado');
SET @MotivoNoEncontradoID = SCOPE_IDENTITY();

-- Stock: 4 unidades, para las 4 líneas de prueba
INSERT INTO dbo.StockSKUTienda (SKUID, TiendaID, StockSistema, StockReservado) VALUES (@SKUID, @TiendaID, 4, 0);

PRINT N'--- Datos de prueba creados. ---';
PRINT N'';

-- CASO 1: Cancelación voluntaria exitosa
EXEC dbo.sp_CrearPedido @PedidoID=910001, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=1, @LineaID=@LineaID1 OUTPUT, @Resultado=@Resultado OUTPUT;
BEGIN TRY
    EXEC dbo.sp_CancelarPedido @LineaID=@LineaID1, @MotivoID=@MotivoVoluntariaID, @FechaID=@FechaID,
        @IncidenciaID=NULL, @Resultado=@Resultado OUTPUT;
    IF @Resultado = N'CANCELADO' PRINT N'[OK]     Caso 1 — Cancelación voluntaria exitosa.';
    ELSE PRINT N'[FALLO]  Caso 1 — Resultado: ' + @Resultado;
END TRY
BEGIN CATCH PRINT N'[ERROR]  Caso 1 no debía fallar: ' + ERROR_MESSAGE(); END CATCH;

-- CASO 2: Doble cancelación
BEGIN TRY
    EXEC dbo.sp_CancelarPedido @LineaID=@LineaID1, @MotivoID=@MotivoVoluntariaID, @FechaID=@FechaID,
        @IncidenciaID=NULL, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  Caso 2 — Se permitió cancelar dos veces.';
END TRY
BEGIN CATCH PRINT N'[OK]     Caso 2 — Rechazado correctamente: ' + ERROR_MESSAGE(); END CATCH;

-- CASO 3: Motivo de tipo incorrecto
EXEC dbo.sp_CrearPedido @PedidoID=910002, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=1, @LineaID=@LineaID2 OUTPUT, @Resultado=@Resultado OUTPUT;
BEGIN TRY
    EXEC dbo.sp_CancelarPedido @LineaID=@LineaID2, @MotivoID=@MotivoNoEncontradoID, @FechaID=@FechaID,
        @IncidenciaID=NULL, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  Caso 3 — Se permitió un motivo de tipo incorrecto.';
END TRY
BEGIN CATCH PRINT N'[OK]     Caso 3 — Rechazado correctamente: ' + ERROR_MESSAGE(); END CATCH;

-- CASO 4: Cancelación por incidencia_picking
BEGIN TRY
    EXEC dbo.sp_RegistrarIncidenciaPicking @LineaID=@LineaID2, @TipoIncidencia=N'no_encontrado',
        @MotivoID=@MotivoNoEncontradoID, @FechaID=@FechaID, @IncidenciaID=@IncidenciaID OUTPUT;
    EXEC dbo.sp_CancelarPedido @LineaID=@LineaID2, @MotivoID=@MotivoIncidenciaPickingID, @FechaID=@FechaID,
        @IncidenciaID=@IncidenciaID, @Resultado=@Resultado OUTPUT;
    IF @Resultado = N'CANCELADO' AND EXISTS (SELECT 1 FROM dbo.FactIncidencia WHERE IncidenciaID=@IncidenciaID AND EstadoResolucion=N'no_resuelta')
        PRINT N'[OK]     Caso 4 — Cancelación por incidencia exitosa, incidencia no_resuelta.';
    ELSE PRINT N'[FALLO]  Caso 4 — Resultado inesperado.';
END TRY
BEGIN CATCH PRINT N'[ERROR]  Caso 4 no debía fallar: ' + ERROR_MESSAGE(); END CATCH;

-- CASO 5: IncidenciaID que no corresponde
BEGIN TRY
    EXEC dbo.sp_CancelarPedido @LineaID=@LineaID1, @MotivoID=@MotivoIncidenciaPickingID, @FechaID=@FechaID,
        @IncidenciaID=@IncidenciaID, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  Caso 5 — Se aceptó un IncidenciaID que no corresponde.';
END TRY
BEGIN CATCH PRINT N'[OK]     Caso 5 — Rechazado correctamente: ' + ERROR_MESSAGE(); END CATCH;

-- CASO 6 (NUEVO): Cancelación voluntaria desde Empaquetado → DECISIÓN PENDIENTE
EXEC dbo.sp_CrearPedido @PedidoID=910003, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=1, @LineaID=@LineaID3 OUTPUT, @Resultado=@Resultado OUTPUT;
EXEC dbo.sp_ConfirmarPicking @LineaID=@LineaID3, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
BEGIN TRY
    EXEC dbo.sp_CancelarPedido @LineaID=@LineaID3, @MotivoID=@MotivoVoluntariaID, @FechaID=@FechaID,
        @IncidenciaID=NULL, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  Caso 6 — Se permitió cancelar una línea Empaquetada sin resolver la decisión pendiente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51019
        PRINT N'[DECISIÓN PENDIENTE]  Caso 6 — Bloqueado correctamente como pendiente, no como error técnico: ' + ERROR_MESSAGE();
    ELSE
        PRINT N'[ERROR]  Caso 6 — Falló con un error distinto al esperado (51019): ' + ERROR_MESSAGE();
END CATCH;

-- CASO 7 (NUEVO): Reserva activa distinta de Cantidad (inconsistencia simulada)
EXEC dbo.sp_CrearPedido @PedidoID=910004, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=2, @LineaID=@LineaID4 OUTPUT, @Resultado=@Resultado OUTPUT;

-- Simulamos una inconsistencia externa: alguien liberó 1 unidad manualmente
-- (fuera del flujo normal) dejando la reserva activa en 1, no en 2.
INSERT INTO dbo.FactMovimientoInventario (SKUID, TiendaID, FechaID, FechaHora, TipoMovimiento, Origen, Cantidad, LineaID)
VALUES (@SKUID, @TiendaID, @FechaID, SYSDATETIME(), N'LIBERACION_RESERVA', N'CANCELACION', -1, @LineaID4);

BEGIN TRY
    EXEC dbo.sp_CancelarPedido @LineaID=@LineaID4, @MotivoID=@MotivoVoluntariaID, @FechaID=@FechaID,
        @IncidenciaID=NULL, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  Caso 7 — Se permitió cancelar con una reserva inconsistente (1 en vez de 2).';
END TRY
BEGIN CATCH PRINT N'[OK]     Caso 7 — Rechazado correctamente por inconsistencia: ' + ERROR_MESSAGE(); END CATCH;

PRINT N'';
PRINT N'--- Limpiando datos de prueba ---';

DELETE FROM dbo.FactIncidencia WHERE LineaID IN (@LineaID1, @LineaID2, @LineaID3, @LineaID4);
DELETE FROM dbo.FactMovimientoInventario WHERE SKUID = @SKUID;
DELETE fh FROM dbo.FactHistorialEstadoLinea fh
    INNER JOIN dbo.FactPedidoDetalle fp ON fp.LineaID = fh.LineaID
    WHERE fp.PedidoID IN (910001, 910002, 910003, 910004);
DELETE FROM dbo.FactPedidoDetalle WHERE PedidoID IN (910001, 910002, 910003, 910004);
DELETE FROM dbo.StockSKUTienda WHERE SKUID = @SKUID;
DELETE FROM dbo.DimMotivo WHERE MotivoID IN (@MotivoVoluntariaID, @MotivoIncidenciaPickingID, @MotivoNoEncontradoID);
DELETE FROM dbo.DimCliente WHERE ClienteID = @ClienteID;
DELETE FROM dbo.DimSKU WHERE SKUID = @SKUID;
DELETE FROM dbo.DimProducto WHERE ProductoID = @ProductoID;
DELETE FROM dbo.DimTienda WHERE TiendaID = @TiendaID;

PRINT N'--- Limpieza completada. ---';
GO
