/*
===============================================================================
ORIGEN — Pruebas del flujo de estados y del trigger de sincronización
Fase 3 — Implementación SQL Server
===============================================================================
Pruebas dirigidas al cierre de la máquina de estados. Cobertura frente a
la lista de verificación pedida:

 1. INSERT de historial actualiza EstadoActualID — Caso A2 (inserción cruda
    con fecha HISTÓrica: comprueba que el trigger NO depende de
    MAX(FechaHora)).
 2. EstadoActualID no queda obsoleto tras cada operación — aserciones de
    estado tras cada transición de todos los bloques.
 3. Transiciones inválidas rechazadas — Casos A3a, A3b, A4b, A5, B1b, B3,
    B5, C1a, C1c, C1f, C2a, C2b, D3 (código de error esperado 51011 /
    51015 / 51041).
 4. Incidencia resuelta vuelve a Picking en proceso — Bloque B.
 5. Despacho llega a Completado — Bloque C1.
 6. Recojo llega a Completado — Bloque D.
 7. Vencimiento termina en Cancelado — verificado en
    09_pruebas_vencimiento_y_devolucion.sql (Bloque vencimiento completo,
    casos 1-6b), no se duplica aquí.
 8. Devolución no cambia el estado — verificado en
    09_pruebas_vencimiento_y_devolucion.sql (Caso 1b).
 9. Rollback correcto ante errores — Caso E1 (falla intermedia dentro de
    sp_CancelarPedido: nada debe quedar a medias).

Requisitos: 09_stock_sku_tienda.sql (pre-siembra),
03_actualizar_stock_sku_tienda.sql, 04_actualizar_estado_actual.sql,
datos semilla (DimEstado/DimArea/DimFecha) y los SP 01, 03-07 y 10-17.
===============================================================================
*/

USE OrigenDB;
GO

SET NOCOUNT ON;

DECLARE @ProductoID INT, @SKUID INT, @TiendaID INT, @ClienteID INT, @FechaID INT;
DECLARE @LineaA1 INT, @LineaA2 INT, @LineaB1 INT, @LineaC1 INT, @LineaC2 INT, @LineaD1 INT, @LineaE1 INT;
DECLARE @Resultado VARCHAR(20), @IncidenciaID INT;
DECLARE @MotivoVoluntariaID INT, @MotivoNoEncontradoID INT;
DECLARE @EstadoID_Asignado INT;

INSERT INTO dbo.DimProducto (NombreProducto, Categoria, Marca) VALUES (N'Producto flujo de estados', N'Categoria de prueba', NULL);
SET @ProductoID = SCOPE_IDENTITY();
INSERT INTO dbo.DimSKU (CodigoSKU, ProductoID, Talla, Color) VALUES (N'T00005', @ProductoID, N'M', N'Azul');
SET @SKUID = SCOPE_IDENTITY();
INSERT INTO dbo.DimTienda (NombreTienda, Distrito, Ciudad) VALUES (N'Tienda de prueba', NULL, N'Lima');
SET @TiendaID = SCOPE_IDENTITY();
INSERT INTO dbo.DimCliente (NombreCliente, Email) VALUES (N'Cliente de prueba', N'prueba5@origen.com');
SET @ClienteID = SCOPE_IDENTITY();

IF NOT EXISTS (SELECT 1 FROM dbo.DimFecha WHERE FechaID = 20260105)
    INSERT INTO dbo.DimFecha (FechaID, Fecha, Anio, Mes, NombreMes, Dia, DiaSemana, EsCampania, NombreCampania)
    VALUES (20260105, '2026-01-05', 2026, 1, N'Enero', 5, N'Lunes', 0, NULL);
SET @FechaID = 20260105;

-- Estados usados por este script (permanentes, no se borran al final)
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Pedido creado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Pedido creado', 0);
IF NOT EXISTS (SELECT 1 FROM dbo.DimEstado WHERE NombreEstado = N'Rechazado')
    INSERT INTO dbo.DimEstado (NombreEstado, EsFinal) VALUES (N'Rechazado', 1);
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

SELECT @EstadoID_Asignado = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Asignado a picking';

IF NOT EXISTS (SELECT 1 FROM dbo.DimArea WHERE NombreArea = N'Tienda / Picking')
    INSERT INTO dbo.DimArea (NombreArea) VALUES (N'Tienda / Picking');

INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'cancelacion', N'voluntaria');
SET @MotivoVoluntariaID = SCOPE_IDENTITY();
INSERT INTO dbo.DimMotivo (TipoMotivo, NombreMotivo) VALUES (N'incidencia', N'no_encontrado');
SET @MotivoNoEncontradoID = SCOPE_IDENTITY();

INSERT INTO dbo.StockSKUTienda (SKUID, TiendaID, StockSistema, StockReservado) VALUES (@SKUID, @TiendaID, 20, 0);

PRINT N'--- Datos de prueba creados. ---';
PRINT N'';

-- =============================================================================
-- BLOQUE A — Trigger de sincronización + validación de estados origen
-- =============================================================================

-- A1: creación → EstadoActualID = Pedido creado
EXEC dbo.sp_CrearPedido @PedidoID=930001, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=1, @LineaID=@LineaA1 OUTPUT, @Resultado=@Resultado OUTPUT;

IF EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
           WHERE fp.LineaID = @LineaA1 AND e.NombreEstado = N'Pedido creado')
    PRINT N'[OK]     A1 — Tras crear, EstadoActualID = Pedido creado.';
ELSE
    PRINT N'[FALLO]  A1 — EstadoActualID inesperado tras crear el pedido.';

-- A2 (checklist 1): INSERT crudo de historial con fecha HISTÓRICA (30 días
-- atrás). El trigger debe aplicar la fila INSERTADA, no la de FechaHora más
-- reciente — si dependiera de MAX(FechaHora), el estado volvería a quedar
-- en 'Pedido creado' y el test anterior fallaría.
INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
VALUES (@LineaA1, @EstadoID_Asignado, @FechaID, DATEADD(DAY, -30, SYSDATETIME()));

IF EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
           WHERE fp.LineaID = @LineaA1 AND e.NombreEstado = N'Asignado a picking')
    PRINT N'[OK]     A2 — Trigger sincronizó con fecha histórica (no depende de MAX(FechaHora)).';
ELSE
    PRINT N'[FALLO]  A2 — El trigger no actualizó EstadoActualID con la fila insertada.';

-- A3a: transición válida Asignar picking + sincronización
EXEC dbo.sp_CrearPedido @PedidoID=930002, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=1, @LineaID=@LineaA2 OUTPUT, @Resultado=@Resultado OUTPUT;
BEGIN TRY
    EXEC dbo.sp_AsignarPicking @LineaID=@LineaA2, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    IF @Resultado = N'ASIGNADO'
       AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
                   WHERE fp.LineaID = @LineaA2 AND e.NombreEstado = N'Asignado a picking')
        PRINT N'[OK]     A3a — Asignar picking exitoso y EstadoActualID sincronizado.';
    ELSE
        PRINT N'[FALLO]  A3a — Resultado o estado inesperado tras Asignar picking.';
END TRY
BEGIN CATCH PRINT N'[ERROR]  A3a no debía fallar: ' + ERROR_MESSAGE(); END CATCH;

-- A3b: transición inválida — reasignar una línea ya asignada
BEGIN TRY
    EXEC dbo.sp_AsignarPicking @LineaID=@LineaA2, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  A3b — Se permitió asignar dos veces.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51011
        PRINT N'[OK]     A3b — Segunda asignación rechazada (51011).';
    ELSE
        PRINT N'[ERROR]  A3b — Se esperaba 51011: ' + ERROR_MESSAGE();
END CATCH;

-- A4a: transición válida Iniciar picking + sincronización
BEGIN TRY
    EXEC dbo.sp_IniciarPicking @LineaID=@LineaA2, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    IF @Resultado = N'INICIADO'
       AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
                   WHERE fp.LineaID = @LineaA2 AND e.NombreEstado = N'Picking en proceso')
        PRINT N'[OK]     A4a — Iniciar picking exitoso y EstadoActualID sincronizado.';
    ELSE
        PRINT N'[FALLO]  A4a — Resultado o estado inesperado tras Iniciar picking.';
END TRY
BEGIN CATCH PRINT N'[ERROR]  A4a no debía fallar: ' + ERROR_MESSAGE(); END CATCH;

-- A4b: transición inválida — iniciar picking dos veces
BEGIN TRY
    EXEC dbo.sp_IniciarPicking @LineaID=@LineaA2, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  A4b — Se permitió iniciar picking dos veces.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51011
        PRINT N'[OK]     A4b — Segundo inicio rechazado (51011).';
    ELSE
        PRINT N'[ERROR]  A4b — Se esperaba 51011: ' + ERROR_MESSAGE();
END CATCH;

-- A5: transición inválida — preparar despacho sin haber empaquetado
BEGIN TRY
    EXEC dbo.sp_PrepararDespacho @LineaID=@LineaA2, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  A5 — Se permitió preparar despacho desde Picking en proceso.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51011
        PRINT N'[OK]     A5 — Preparar despacho rechazado sin pasar por Empaquetado (51011).';
    ELSE
        PRINT N'[ERROR]  A5 — Se esperaba 51011: ' + ERROR_MESSAGE();
END CATCH;

-- =============================================================================
-- BLOQUE B — Una incidencia resuelta vuelve a Picking en proceso
-- =============================================================================

EXEC dbo.sp_CrearPedido @PedidoID=930003, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=1, @LineaID=@LineaB1 OUTPUT, @Resultado=@Resultado OUTPUT;
EXEC dbo.sp_AsignarPicking @LineaID=@LineaB1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
EXEC dbo.sp_IniciarPicking @LineaID=@LineaB1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;

BEGIN TRY
    EXEC dbo.sp_RegistrarIncidenciaPicking @LineaID=@LineaB1, @TipoIncidencia=N'no_encontrado',
        @MotivoID=@MotivoNoEncontradoID, @FechaID=@FechaID, @IncidenciaID=@IncidenciaID OUTPUT;

    IF EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
               WHERE fp.LineaID = @LineaB1 AND e.NombreEstado = N'Incidencia de picking')
        PRINT N'[OK]     B1 — Incidencia registrada y EstadoActualID = Incidencia de picking.';
    ELSE
        PRINT N'[FALLO]  B1 — Estado inesperado tras registrar la incidencia.';
END TRY
BEGIN CATCH PRINT N'[ERROR]  B1 no debía fallar: ' + ERROR_MESSAGE(); END CATCH;

-- B1b: estado correcto pero incidencia inexistente → 51015 (comprueba el
-- segundo nivel de validación ANTES de resolver de verdad).
BEGIN TRY
    EXEC dbo.sp_ResolverIncidencia @LineaID=@LineaB1, @IncidenciaID=-1,
        @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  B1b — Se aceptó un IncidenciaID inexistente.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51015
        PRINT N'[OK]     B1b — Rechazada por incidencia inexistente (51015).';
    ELSE
        PRINT N'[ERROR]  B1b — Se esperaba 51015: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    EXEC dbo.sp_ResolverIncidencia @LineaID=@LineaB1, @IncidenciaID=@IncidenciaID,
        @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;

    IF @Resultado = N'RESUELTA'
       AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
                   WHERE fp.LineaID = @LineaB1 AND e.NombreEstado = N'Picking en proceso')
       AND EXISTS (SELECT 1 FROM dbo.FactIncidencia WHERE IncidenciaID = @IncidenciaID AND EstadoResolucion = N'resuelta')
        PRINT N'[OK]     B2 — Incidencia resuelta: la línea volvió a Picking en proceso.';
    ELSE
        PRINT N'[FALLO]  B2 — Estado o incidencia inesperados tras resolver.';
END TRY
BEGIN CATCH PRINT N'[ERROR]  B2 no debía fallar: ' + ERROR_MESSAGE(); END CATCH;

-- B3: resolver dos veces → la línea YA SALIÓ de Incidencia de picking al
-- resolverse, así que el control de estado la rechaza primero (51011);
-- el chequeo de incidencia (51015) ni siquiera se alcanza.
BEGIN TRY
    EXEC dbo.sp_ResolverIncidencia @LineaID=@LineaB1, @IncidenciaID=@IncidenciaID,
        @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  B3 — Se permitió resolver una incidencia ya cerrada.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51011
        PRINT N'[OK]     B3 — Segundo resolver rechazado por estado origen (51011).';
    ELSE
        PRINT N'[ERROR]  B3 — Se esperaba 51011: ' + ERROR_MESSAGE();
END CATCH;

-- B4: tras resolver, la línea retoma el flujo y puede empaquetarse
BEGIN TRY
    EXEC dbo.sp_ConfirmarPicking @LineaID=@LineaB1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    IF EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
               WHERE fp.LineaID = @LineaB1 AND e.NombreEstado = N'Empaquetado')
        PRINT N'[OK]     B4 — La línea retomó el flujo y llegó a Empaquetado.';
    ELSE
        PRINT N'[FALLO]  B4 — Estado inesperado tras confirmar picking.';
END TRY
BEGIN CATCH PRINT N'[ERROR]  B4 no debía fallar: ' + ERROR_MESSAGE(); END CATCH;

-- B5: resolver incidencia sobre una línea que NO está en Incidencia
BEGIN TRY
    EXEC dbo.sp_ResolverIncidencia @LineaID=@LineaA2, @IncidenciaID=@IncidenciaID,
        @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  B5 — Se permitió resolver sobre una línea sin incidencia.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51011
        PRINT N'[OK]     B5 — Resolver rechazado: la línea no está en Incidencia de picking (51011).';
    ELSE
        PRINT N'[ERROR]  B5 — Se esperaba 51011: ' + ERROR_MESSAGE();
END CATCH;

-- =============================================================================
-- BLOQUE C1 — Flujo de despacho completo hasta Completado (checklist 5)
-- =============================================================================

EXEC dbo.sp_CrearPedido @PedidoID=930004, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'despacho', @Cantidad=1, @LineaID=@LineaC1 OUTPUT, @Resultado=@Resultado OUTPUT;
EXEC dbo.sp_AsignarPicking @LineaID=@LineaC1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
EXEC dbo.sp_IniciarPicking @LineaID=@LineaC1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
EXEC dbo.sp_ConfirmarPicking @LineaID=@LineaC1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;

-- C1a: bifurcación de canal — preparar recojo en una línea de despacho
BEGIN TRY
    EXEC dbo.sp_PrepararRecojo @LineaID=@LineaC1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  C1a — Se permitió preparar recojo en canal despacho.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51041
        PRINT N'[OK]     C1a — Preparar recojo rechazado por canal (51041).';
    ELSE
        PRINT N'[ERROR]  C1a — Se esperaba 51041: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    EXEC dbo.sp_PrepararDespacho @LineaID=@LineaC1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    IF @Resultado = N'EN_TRANSITO'
       AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
                   WHERE fp.LineaID = @LineaC1 AND e.NombreEstado = N'En tránsito')
        PRINT N'[OK]     C1b — Preparar despacho exitoso y EstadoActualID = En tránsito.';
    ELSE
        PRINT N'[FALLO]  C1b — Resultado o estado inesperado tras Preparar despacho.';
END TRY
BEGIN CATCH PRINT N'[ERROR]  C1b no debía fallar: ' + ERROR_MESSAGE(); END CATCH;

-- C1c: completar desde En tránsito (falta registrar la entrega)
BEGIN TRY
    EXEC dbo.sp_CompletarPedido @LineaID=@LineaC1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  C1c — Se permitió completar sin registrar la entrega.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51011
        PRINT N'[OK]     C1c — Completar rechazado desde En tránsito (51011).';
    ELSE
        PRINT N'[ERROR]  C1c — Se esperaba 51011: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    EXEC dbo.sp_RegistrarEntrega @LineaID=@LineaC1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    IF @Resultado = N'ENTREGADO'
       AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
                   WHERE fp.LineaID = @LineaC1 AND e.NombreEstado = N'Entregado')
        PRINT N'[OK]     C1d — Registrar entrega exitoso y EstadoActualID = Entregado.';
    ELSE
        PRINT N'[FALLO]  C1d — Resultado o estado inesperado tras Registrar entrega.';
END TRY
BEGIN CATCH PRINT N'[ERROR]  C1d no debía fallar: ' + ERROR_MESSAGE(); END CATCH;

BEGIN TRY
    EXEC dbo.sp_CompletarPedido @LineaID=@LineaC1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    IF @Resultado = N'COMPLETADO'
       AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
                   WHERE fp.LineaID = @LineaC1 AND e.NombreEstado = N'Completado')
        PRINT N'[OK]     C1e — Flujo de despacho completo hasta Completado (checklist 5).';
    ELSE
        PRINT N'[FALLO]  C1e — Estado inesperado al completar el flujo de despacho.';
END TRY
BEGIN CATCH PRINT N'[ERROR]  C1e no debía fallar: ' + ERROR_MESSAGE(); END CATCH;

-- C1f: completar dos veces → Completado es estado final
BEGIN TRY
    EXEC dbo.sp_CompletarPedido @LineaID=@LineaC1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  C1f — Se permitió completar dos veces.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51011
        PRINT N'[OK]     C1f — Segundo completado rechazado (51011).';
    ELSE
        PRINT N'[ERROR]  C1f — Se esperaba 51011: ' + ERROR_MESSAGE();
END CATCH;

-- =============================================================================
-- BLOQUE C2 — Línea de recojo en Empaquetado: forks de canal inválidos
-- =============================================================================

EXEC dbo.sp_CrearPedido @PedidoID=930005, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=1, @LineaID=@LineaC2 OUTPUT, @Resultado=@Resultado OUTPUT;
EXEC dbo.sp_AsignarPicking @LineaID=@LineaC2, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
EXEC dbo.sp_IniciarPicking @LineaID=@LineaC2, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
EXEC dbo.sp_ConfirmarPicking @LineaID=@LineaC2, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;

-- C2a: preparar despacho en una línea de recojo
BEGIN TRY
    EXEC dbo.sp_PrepararDespacho @LineaID=@LineaC2, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  C2a — Se permitió preparar despacho en canal recojo.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51041
        PRINT N'[OK]     C2a — Preparar despacho rechazado por canal (51041).';
    ELSE
        PRINT N'[ERROR]  C2a — Se esperaba 51041: ' + ERROR_MESSAGE();
END CATCH;

-- C2b: completar directamente desde Empaquetado (sin recorrer la arista)
BEGIN TRY
    EXEC dbo.sp_CompletarPedido @LineaID=@LineaC2, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  C2b — Se permitió completar desde Empaquetado.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51011
        PRINT N'[OK]     C2b — Completar rechazado desde Empaquetado (51011).';
    ELSE
        PRINT N'[ERROR]  C2b — Se esperaba 51011: ' + ERROR_MESSAGE();
END CATCH;

-- =============================================================================
-- BLOQUE D — Flujo de recojo completo hasta Completado (checklist 6)
-- =============================================================================

EXEC dbo.sp_CrearPedido @PedidoID=930006, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=1, @LineaID=@LineaD1 OUTPUT, @Resultado=@Resultado OUTPUT;
EXEC dbo.sp_AsignarPicking @LineaID=@LineaD1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
EXEC dbo.sp_IniciarPicking @LineaID=@LineaD1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
EXEC dbo.sp_ConfirmarPicking @LineaID=@LineaD1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;

BEGIN TRY
    EXEC dbo.sp_PrepararRecojo @LineaID=@LineaD1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    IF @Resultado = N'DISPONIBLE'
       AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
                   WHERE fp.LineaID = @LineaD1 AND e.NombreEstado = N'Disponible para recojo')
        PRINT N'[OK]     D1 — Preparar recojo exitoso y EstadoActualID = Disponible para recojo.';
    ELSE
        PRINT N'[FALLO]  D1 — Resultado o estado inesperado tras Preparar recojo.';
END TRY
BEGIN CATCH PRINT N'[ERROR]  D1 no debía fallar: ' + ERROR_MESSAGE(); END CATCH;

BEGIN TRY
    EXEC dbo.sp_RegistrarRecojo @LineaID=@LineaD1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    IF @Resultado = N'RECOGIDO'
       AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
                   WHERE fp.LineaID = @LineaD1 AND e.NombreEstado = N'Recojo por cliente')
        PRINT N'[OK]     D2 — Registrar recojo exitoso y EstadoActualID = Recojo por cliente.';
    ELSE
        PRINT N'[FALLO]  D2 — Resultado o estado inesperado tras Registrar recojo.';
END TRY
BEGIN CATCH PRINT N'[ERROR]  D2 no debía fallar: ' + ERROR_MESSAGE(); END CATCH;

-- D3: registrar entrega (ruta de domicilio) sobre una línea de recojo
BEGIN TRY
    EXEC dbo.sp_RegistrarEntrega @LineaID=@LineaD1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  D3 — Se permitió registrar entrega en una línea de recojo.';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 51011
        PRINT N'[OK]     D3 — Registrar entrega rechazado en arista de recojo (51011).';
    ELSE
        PRINT N'[ERROR]  D3 — Se esperaba 51011: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    EXEC dbo.sp_CompletarPedido @LineaID=@LineaD1, @FechaID=@FechaID, @Resultado=@Resultado OUTPUT;
    IF @Resultado = N'COMPLETADO'
       AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
                   WHERE fp.LineaID = @LineaD1 AND e.NombreEstado = N'Completado')
        PRINT N'[OK]     D4 — Flujo de recojo completo hasta Completado (checklist 6).';
    ELSE
        PRINT N'[FALLO]  D4 — Estado inesperado al completar el flujo de recojo.';
END TRY
BEGIN CATCH PRINT N'[ERROR]  D4 no debía fallar: ' + ERROR_MESSAGE(); END CATCH;

-- =============================================================================
-- BLOQUE E — Rollback correcto ante un error a mitad de transacción (checklist 9)
-- =============================================================================

EXEC dbo.sp_CrearPedido @PedidoID=930007, @ClienteID=@ClienteID, @SKUID=@SKUID, @TiendaID=@TiendaID,
    @FechaID=@FechaID, @Canal=N'recojo', @Cantidad=2, @LineaID=@LineaE1 OUTPUT, @Resultado=@Resultado OUTPUT;

-- Inconsistencia externa simulada: liberación manual parcial (1 de 2).
INSERT INTO dbo.FactMovimientoInventario (SKUID, TiendaID, FechaID, FechaHora, TipoMovimiento, Origen, Cantidad, LineaID)
VALUES (@SKUID, @TiendaID, @FechaID, SYSDATETIME(), N'LIBERACION_RESERVA', N'CANCELACION', -1, @LineaE1);

BEGIN TRY
    EXEC dbo.sp_CancelarPedido @LineaID=@LineaE1, @MotivoID=@MotivoVoluntariaID, @FechaID=@FechaID,
        @IncidenciaID=NULL, @Resultado=@Resultado OUTPUT;
    PRINT N'[FALLO]  E1 — Se permitió cancelar con reserva inconsistente (1 en vez de 2).';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 51014
        PRINT N'[ERROR]  E1 — Se esperaba 51014, se obtuvo (' + CAST(ERROR_NUMBER() AS VARCHAR) + N'): ' + ERROR_MESSAGE();
    ELSE IF EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle fp INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
                    WHERE fp.LineaID = @LineaE1 AND e.NombreEstado = N'Pedido creado')
        AND NOT EXISTS (SELECT 1 FROM dbo.FactHistorialEstadoLinea h INNER JOIN dbo.DimEstado e ON e.EstadoID = h.EstadoID
                        WHERE h.LineaID = @LineaE1 AND e.NombreEstado = N'Cancelado')
        AND NOT EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle WHERE LineaID = @LineaE1 AND MotivoCancelacionID IS NOT NULL)
        AND (SELECT COUNT(*) FROM dbo.FactMovimientoInventario WHERE LineaID = @LineaE1) = 2
        PRINT N'[OK]     E1 — Rechazado con 51014 y ROLLBACK completo: EstadoActualID, historial, motivo y movimientos intactos.';
    ELSE
        PRINT N'[FALLO]  E1 — El error ocurrió pero el ROLLBACK no dejó todo intacto (algo quedó a medias).';
END CATCH;

PRINT N'';
PRINT N'--- Limpiando datos de prueba ---';

DELETE FROM dbo.FactIncidencia WHERE LineaID IN (@LineaA1, @LineaA2, @LineaB1, @LineaC1, @LineaC2, @LineaD1, @LineaE1);
DELETE FROM dbo.FactMovimientoInventario WHERE SKUID = @SKUID;
DELETE fh FROM dbo.FactHistorialEstadoLinea fh
    INNER JOIN dbo.FactPedidoDetalle fp ON fp.LineaID = fh.LineaID
    WHERE fp.PedidoID IN (930001, 930002, 930003, 930004, 930005, 930006, 930007);
DELETE FROM dbo.FactPedidoDetalle WHERE PedidoID IN (930001, 930002, 930003, 930004, 930005, 930006, 930007);
DELETE FROM dbo.StockSKUTienda WHERE SKUID = @SKUID;
DELETE FROM dbo.DimMotivo WHERE MotivoID IN (@MotivoVoluntariaID, @MotivoNoEncontradoID);
DELETE FROM dbo.DimCliente WHERE ClienteID = @ClienteID;
DELETE FROM dbo.DimSKU WHERE SKUID = @SKUID;
DELETE FROM dbo.DimProducto WHERE ProductoID = @ProductoID;
DELETE FROM dbo.DimTienda WHERE TiendaID = @TiendaID;

PRINT N'--- Limpieza completada. ---';
GO
