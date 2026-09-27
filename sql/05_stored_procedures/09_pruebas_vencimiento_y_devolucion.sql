/*
===============================================================================
ORIGEN — Pruebas de sp_ProcesarVencimientosRecojo y sp_RegistrarDevolucion
Fase 3 — Implementación SQL Server (2ª ronda, ampliadas)
===============================================================================
Vencimiento:
1. Ejecución normal (línea de 10 días vence).
2. Línea de 1 día no vence todavía.
3. Segunda ejecución sobre las MISMAS líneas → no debe reprocesar ni
   duplicar LIBERACION_RESERVA (prueba de idempotencia/repetición).
4. Concurrencia real (dos sesiones simultáneas) NO se puede simular dentro
   de un único script T-SQL de una sola conexión — se deja documentada
   como prueba manual: abrir dos pestañas de SSMS, colocar un breakpoint/
   WAITFOR en una justo después del SELECT ... WITH (UPDLOCK) y ejecutar
   la otra en paralelo para confirmar que espera. La corrección de diseño
   (relectura de estado bajo bloqueo) es la que garantiza la seguridad;
   esta prueba automatizada valida el caso equivalente de repetición
   secuencial (Caso 3), que ejercita la misma rama de código de forma
   determinística.
5. Verificación de que solo existe UNA fila LIBERACION_RESERVA por línea
   tras las dos ejecuciones.

Devolución:
- Casos 1-3 de la versión anterior (dentro de ventana, doble devolución,
  fuera de ventana).
- NUEVO: motivo de tipo incorrecto.
- NUEVO: línea que no está Completado.
===============================================================================
*/

USE OrigenDB;
GO

SET NOCOUNT ON;

DECLARE @ProductoID INT, @SKUID INT, @TiendaID INT, @ClienteID INT, @FechaID INT;
DECLARE @LineaVence INT, @LineaNoVence INT, @LineaDevolucion1 INT, @LineaDevolucion2 INT, @LineaDevolucion3 INT, @LineaNoCompletada INT;
DECLARE @Resultado VARCHAR(20), @LineasProcesadas INT, @DevolucionID INT;
DECLARE @MotivoVencimientoID INT, @MotivoDevolucionID INT, @MotivoIncidenciaID INT;
DECLARE @EstadoID_DisponibleRecojo INT, @EstadoID_Completado INT;
DECLARE @ConteoLiberaciones INT;

INSERT INTO dbo.DimProducto (NombreProducto, Categoria, Marca) VALUES (N'Producto de prueba', N'Categoria de prueba', NULL);
SET @ProductoID = SCOPE_IDENTITY();
INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'T00004', @ProductoID, N'M', N'Azul');
SET @SKUID = SCOPE_IDENTITY();
INSERT INTO dbo.DimTienda (NombreTienda, Distrito, Ciudad) VALUES (N'Tienda de prueba', NULL, N'Lima');
SET @TiendaID = SCOPE_IDENTITY();
INSERT INTO dbo.DimCliente (NombreCliente, Email) VALUES (N'Cliente de prueba', N'prueba4@origen.com');
SET @ClienteID = SCOPE_IDENTITY();

IF NOT EXISTS (SELECT 1 FROM dbo.DimFecha WHERE FechaID = 20260104)
    INSERT INTO dbo.DimFecha (FechaID, Fecha, Anio, Mes, NombreMes, Dia, DiaSemana, EsCampania, NombreCampania)
    VALUES (20260104, '2026-01-04', 2026, 1, N'Enero', 4, N'Domingo', 0, NULL);
SET @FechaID = 20260104;

IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Pedido creado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Pedido creado', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Disponible para recojo')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Disponible para recojo', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Vencido')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Vencido', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Cancelado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Cancelado', 1);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Completado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Completado', 1);

SELECT @EstadoID_DisponibleRecojo = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Disponible para recojo';
SELECT @EstadoID_Completado = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Completado';

INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'cancelacion', N'vencimiento');
SET @MotivoVencimientoID = SCOPE_IDENTITY();
INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'devolucion', N'talla_incorrecta');
SET @MotivoDevolucionID = SCOPE_IDENTITY();
INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'incidencia', N'no_encontrado');
SET @MotivoIncidenciaID = SCOPE_IDENTITY();

INSERT INTO dbo.StockSKUTienda (SKUID, TiendaID, StockSistema, StockReservado) VALUES (@SKUID, @TiendaID, 10, 0);

PRINT N'--- Datos base creados. ---';
PRINT N'';

-- =============================================================================
-- BLOQUE VENCIMIENTO
-- =============================================================================

EXEC dbo.sp_CrearPedido @PedidoID=920001, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=1, @LineaID=@LineaVence OUTPUT, @Resultado=@Resultado OUTPUT;
INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
VALUES (@LineaVence, @EstadoID_DisponibleRecojo, @FechaID, DATEADD(DAY, -10, SYSDATETIME()));

EXEC dbo.sp_CrearPedido @PedidoID=920002, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=1, @LineaID=@LineaNoVence OUTPUT, @Resultado=@Resultado OUTPUT;
INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
VALUES (@LineaNoVence, @EstadoID_DisponibleRecojo, @FechaID, DATEADD(DAY, -1, SYSDATETIME()));

-- Caso 1 y 2: primera ejecución
BEGIN TRY
    EXEC dbo.sp_ProcesarVencimientosRecojo
        @FechaHoraActual = SYSDATETIME(), @DiasVentanaRecojo = 3, @FechaID = @FechaID,
        @MotivoVencimientoID = @MotivoVencimientoID, @LineasProcesadas = @LineasProcesadas OUTPUT;

    IF @LineasProcesadas = 1
       AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
                   WHERE fp.LineaID = @LineaVence AND e.NombreEstado = N'Cancelado')
       AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
                   WHERE fp.LineaID = @LineaNoVence AND e.NombreEstado = N'Disponible para recojo')
        PRINT N'[OK]     Casos 1-2 — La línea de 10 días venció; la de 1 día no fue tocada.';
    ELSE
        PRINT N'[FALLO]  Casos 1-2 — resultado inesperado. LineasProcesadas=' + CAST(@LineasProcesadas AS VARCHAR);
END TRY
BEGIN CATCH PRINT N'[ERROR]  Casos 1-2 no debían fallar: ' + ERROR_MESSAGE(); END CATCH;

-- Caso 3: segunda ejecución sobre las mismas líneas → no debe reprocesar
BEGIN TRY
    EXEC dbo.sp_ProcesarVencimientosRecojo
        @FechaHoraActual = SYSDATETIME(), @DiasVentanaRecojo = 3, @FechaID = @FechaID,
        @MotivoVencimientoID = @MotivoVencimientoID, @LineasProcesadas = @LineasProcesadas OUTPUT;

    IF @LineasProcesadas = 0
        PRINT N'[OK]     Caso 3 — La segunda ejecución no reprocesó ninguna línea (ya no están Disponible para recojo).';
    ELSE
        PRINT N'[FALLO]  Caso 3 — La segunda ejecución procesó ' + CAST(@LineasProcesadas AS VARCHAR) + N' líneas, se esperaba 0.';
END TRY
BEGIN CATCH PRINT N'[ERROR]  Caso 3 no debía fallar: ' + ERROR_MESSAGE(); END CATCH;

-- Caso 5: verificar que no hay LIBERACION_RESERVA duplicada
SELECT @ConteoLiberaciones = COUNT(*)
FROM dbo.FactMovimientoInventario
WHERE LineaID = @LineaVence AND TipoMovimiento = N'LIBERACION_RESERVA';

IF @ConteoLiberaciones = 1
    PRINT N'[OK]     Caso 5 — Exactamente 1 LIBERACION_RESERVA registrada para la línea vencida (no duplicada).';
ELSE
    PRINT N'[FALLO]  Caso 5 — Se encontraron ' + CAST(@ConteoLiberaciones AS VARCHAR) + N' LIBERACION_RESERVA, se esperaba 1.';

-- -----------------------------------------------------------------------------
-- CASO 6 (NUEVO — Escenario C de la auditoría): la línea vence pero
-- sp_CancelarPedido falla (se fuerza pasando un MotivoID inválido/inexistente,
-- forma controlada y no invasiva de simular la falla). Verificamos que la
-- línea queda "huérfana" en Vencido con reserva activa, y que una SEGUNDA
-- ejecución (ahora con el motivo correcto) la resuelve vía la Parte 2.
-- -----------------------------------------------------------------------------
DECLARE @LineaFallaRecuperacion INT, @MotivoInvalido INT = -999;

EXEC dbo.sp_CrearPedido @PedidoID=920007, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=1, @LineaID=@LineaFallaRecuperacion OUTPUT, @Resultado=@Resultado OUTPUT;
INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
VALUES (@LineaFallaRecuperacion, @EstadoID_DisponibleRecojo, @FechaID, DATEADD(DAY, -10, SYSDATETIME()));

-- Primera ejecución: la línea vence, pero el MotivoID inválido hace fallar
-- sp_CancelarPedido dentro de la Parte 1. Debe quedar en Vencido, sin cancelar.
EXEC dbo.sp_ProcesarVencimientosRecojo
    @FechaHoraActual = SYSDATETIME(), @DiasVentanaRecojo = 3, @FechaID = @FechaID,
    @MotivoVencimientoID = @MotivoInvalido, @LineasProcesadas = @LineasProcesadas OUTPUT;

IF EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
           WHERE fp.LineaID = @LineaFallaRecuperacion AND e.NombreEstado = N'Vencido')
    PRINT N'[OK]     Caso 6a — Tras la falla simulada, la línea quedó correctamente huérfana en Vencido (no corrupta, solo pendiente).';
ELSE
    PRINT N'[FALLO]  Caso 6a — La línea no quedó en el estado esperado (Vencido) tras la falla simulada.';

-- Segunda ejecución: ahora con el motivo CORRECTO. La Parte 2 debe detectar
-- la línea huérfana (Vencido + reserva activa) y completarla.
EXEC dbo.sp_ProcesarVencimientosRecojo
    @FechaHoraActual = SYSDATETIME(), @DiasVentanaRecojo = 3, @FechaID = @FechaID,
    @MotivoVencimientoID = @MotivoVencimientoID, @LineasProcesadas = @LineasProcesadas OUTPUT;

IF EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
           WHERE fp.LineaID = @LineaFallaRecuperacion AND e.NombreEstado = N'Cancelado')
    PRINT N'[OK]     Caso 6b — La Parte 2 recuperó la línea huérfana y la canceló correctamente en el reintento.';
ELSE
    PRINT N'[FALLO]  Caso 6b — La línea huérfana no fue recuperada por la Parte 2.';

-- =============================================================================
-- BLOQUE DEVOLUCIÓN
-- =============================================================================

EXEC dbo.sp_CrearPedido @PedidoID=920003, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=1, @LineaID=@LineaDevolucion1 OUTPUT, @Resultado=@Resultado OUTPUT;
INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
VALUES (@LineaDevolucion1, @EstadoID_Completado, @FechaID, DATEADD(DAY, -5, SYSDATETIME()));

-- Caso 1: dentro de ventana → OK
BEGIN TRY
    EXEC dbo.sp_RegistrarDevolucion @LineaID=@LineaDevolucion1, @MotivoID=@MotivoDevolucionID, @FechaID=@FechaID,
        @FechaDevolucion=SYSDATETIME(), @DiasVentanaDevolucion=7, @DevolucionID=@DevolucionID OUTPUT;
    PRINT N'[OK]     Devolución Caso 1 — Registrada dentro de la ventana.';
END TRY
BEGIN CATCH PRINT N'[ERROR]  Devolución Caso 1 no debía fallar: ' + ERROR_MESSAGE(); END CATCH;

-- Caso 2: segunda devolución sobre la misma línea → falla
BEGIN TRY
    EXEC dbo.sp_RegistrarDevolucion @LineaID=@LineaDevolucion1, @MotivoID=@MotivoDevolucionID, @FechaID=@FechaID,
        @FechaDevolucion=SYSDATETIME(), @DiasVentanaDevolucion=7, @DevolucionID=@DevolucionID OUTPUT;
    PRINT N'[FALLO]  Devolución Caso 2 — Se permitió una segunda devolución.';
END TRY
BEGIN CATCH PRINT N'[OK]     Devolución Caso 2 — Rechazada correctamente: ' + ERROR_MESSAGE(); END CATCH;

-- Caso 3: fuera de ventana → falla
EXEC dbo.sp_CrearPedido @PedidoID=920004, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=1, @LineaID=@LineaDevolucion2 OUTPUT, @Resultado=@Resultado OUTPUT;
INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
VALUES (@LineaDevolucion2, @EstadoID_Completado, @FechaID, DATEADD(DAY, -20, SYSDATETIME()));

BEGIN TRY
    EXEC dbo.sp_RegistrarDevolucion @LineaID=@LineaDevolucion2, @MotivoID=@MotivoDevolucionID, @FechaID=@FechaID,
        @FechaDevolucion=SYSDATETIME(), @DiasVentanaDevolucion=7, @DevolucionID=@DevolucionID OUTPUT;
    PRINT N'[FALLO]  Devolución Caso 3 — Se permitió fuera de la ventana.';
END TRY
BEGIN CATCH PRINT N'[OK]     Devolución Caso 3 — Rechazada correctamente: ' + ERROR_MESSAGE(); END CATCH;

-- CASO 4 (NUEVO): motivo de tipo incorrecto (es 'incidencia', no 'devolucion')
EXEC dbo.sp_CrearPedido @PedidoID=920005, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=1, @LineaID=@LineaDevolucion3 OUTPUT, @Resultado=@Resultado OUTPUT;
INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
VALUES (@LineaDevolucion3, @EstadoID_Completado, @FechaID, SYSDATETIME());

BEGIN TRY
    EXEC dbo.sp_RegistrarDevolucion @LineaID=@LineaDevolucion3, @MotivoID=@MotivoIncidenciaID, @FechaID=@FechaID,
        @FechaDevolucion=SYSDATETIME(), @DiasVentanaDevolucion=7, @DevolucionID=@DevolucionID OUTPUT;
    PRINT N'[FALLO]  Devolución Caso 4 — Se permitió un motivo de tipo incorrecto.';
END TRY
BEGIN CATCH PRINT N'[OK]     Devolución Caso 4 — Rechazada correctamente: ' + ERROR_MESSAGE(); END CATCH;

-- CASO 5 (NUEVO): línea que no está Completado
EXEC dbo.sp_CrearPedido @PedidoID=920006, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=1, @LineaID=@LineaNoCompletada OUTPUT, @Resultado=@Resultado OUTPUT;

BEGIN TRY
    EXEC dbo.sp_RegistrarDevolucion @LineaID=@LineaNoCompletada, @MotivoID=@MotivoDevolucionID, @FechaID=@FechaID,
        @FechaDevolucion=SYSDATETIME(), @DiasVentanaDevolucion=7, @DevolucionID=@DevolucionID OUTPUT;
    PRINT N'[FALLO]  Devolución Caso 5 — Se permitió sobre una línea no Completada.';
END TRY
BEGIN CATCH PRINT N'[OK]     Devolución Caso 5 — Rechazada correctamente: ' + ERROR_MESSAGE(); END CATCH;

PRINT N'';
PRINT N'--- Limpiando datos de prueba ---';

DELETE FROM dbo.FactDevolucion WHERE LineaID IN (@LineaDevolucion1, @LineaDevolucion2, @LineaDevolucion3, @LineaNoCompletada);
DELETE FROM dbo.FactMovimientoInventario WHERE SKUID = @SKUID;
DELETE fh FROM dbo.FactHistorialEstadoLinea fh
    INNER JOIN dbo.FactPedidoDetalle fp ON fp.LineaID = fh.LineaID
    WHERE fp.PedidoID IN (920001, 920002, 920003, 920004, 920005, 920006, 920007);
DELETE FROM dbo.FactPedidoDetalle WHERE PedidoID IN (920001, 920002, 920003, 920004, 920005, 920006, 920007);
DELETE FROM dbo.StockSKUTienda WHERE SKUID = @SKUID;
DELETE FROM dbo.DimMotivo WHERE MotivoID IN (@MotivoVencimientoID, @MotivoDevolucionID, @MotivoIncidenciaID);
DELETE FROM dbo.DimCliente WHERE ClienteID = @ClienteID;
DELETE FROM dbo.DimSKU WHERE SKUID = @SKUID;
DELETE FROM dbo.DimProducto WHERE ProductoID = @ProductoID;
DELETE FROM dbo.DimTienda WHERE TiendaID = @TiendaID;

PRINT N'--- Limpieza completada. ---';
GO
