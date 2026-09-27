/*
===============================================================================
ORIGEN — Stored Procedure: sp_ConfirmarPicking
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: RN-011.

VERSIÓN CORREGIDA tras revisión, con 2 cambios respecto a la primera versión:

1. "Reserva activa" ahora se calcula como la SUMA NETA de los tres tipos de
   movimiento que la afectan: RESERVA (+) + LIBERACION_RESERVA (-) +
   DESCUENTO_DEFINITIVO (-). La versión anterior solo miraba SUM(RESERVA),
   lo cual NO detectaba que la reserva ya había sido liberada o ya había
   sido descontada — permitiendo, por ejemplo, confirmar picking dos veces
   sobre la misma línea. Como LIBERACION_RESERVA y DESCUENTO_DEFINITIVO ya
   vienen con signo negativo (CK_MovInventario_SignoCantidad), sumar los
   tres tipos junto da directamente el remanente real.

2. Todas las lecturas de validación (línea, estado, reserva activa) se
   movieron DENTRO de la transacción, con UPDLOCK sobre la fila de
   FactPedidoDetalle. Esto serializa cualquier operación concurrente sobre
   la misma línea (ej. alguien intentando confirmar picking y cancelar el
   mismo pedido casi al mismo tiempo) — mismo principio de concurrencia
   que ya se aplicó en sp_CrearPedido, pero aquí la fila que se bloquea es
   la línea de pedido, no el resumen de stock.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.sp_ConfirmarPicking', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ConfirmarPicking;
GO

CREATE PROCEDURE dbo.sp_ConfirmarPicking
    @LineaID    INT,
    @FechaID    INT,
    @Resultado  VARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @SKUID INT, @TiendaID INT, @Cantidad INT, @EstadoActualID INT;
    DECLARE @NombreEstadoActual VARCHAR(40);
    DECLARE @EstadoID_Empaquetado INT;
    DECLARE @ReservaActiva INT;

    SELECT @EstadoID_Empaquetado = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Empaquetado';
    IF @EstadoID_Empaquetado IS NULL
    BEGIN
        THROW 51000, N'DimEstado no tiene cargado el estado "Empaquetado". Verificar datos semilla.', 1;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Bloquea la línea antes de leer nada: evita que otra transacción
        -- (ej. una cancelación concurrente) cambie el estado o genere
        -- movimientos mientras decidimos si se puede confirmar picking.
        SELECT
            @SKUID = SKUID,
            @TiendaID = TiendaID,
            @Cantidad = Cantidad,
            @EstadoActualID = EstadoActualID
        FROM dbo.FactPedidoDetalle WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
        WHERE LineaID = @LineaID;

        IF @SKUID IS NULL
        BEGIN
            THROW 51010, N'La línea de pedido indicada no existe.', 1;
        END

        SELECT @NombreEstadoActual = NombreEstado FROM dbo.DimEstado WHERE EstadoID = @EstadoActualID;

        IF @NombreEstadoActual NOT IN (N'Pedido creado', N'Asignado a picking', N'Picking en proceso')
        BEGIN
            THROW 51011, N'La línea no está en un estado válido para confirmar picking (debe estar Pedido creado, Asignado a picking o Picking en proceso).', 1;
        END

        -- Reserva activa neta: RESERVA + LIBERACION_RESERVA + DESCUENTO_DEFINITIVO.
        -- Los dos últimos ya vienen en negativo, así que restan naturalmente
        -- al sumarlos — si ya se liberó o ya se descontó, esto da 0, no @Cantidad.
        SELECT @ReservaActiva = ISNULL(SUM(Cantidad), 0)
        FROM dbo.FactMovimientoInventario
        WHERE LineaID = @LineaID
          AND TipoMovimiento IN (N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO');

        IF @ReservaActiva <> @Cantidad
        BEGIN
            THROW 51012, N'No existe una reserva activa que coincida con la cantidad de la línea. No se puede confirmar picking.', 1;
        END

        -- Descuento definitivo (RN-011): misma cantidad, en negativo —
        -- afecta StockSistema y StockReservado por igual (ver
        -- trg_ActualizarStockSKUTienda).
        INSERT INTO dbo.FactMovimientoInventario
            (SKUID, TiendaID, FechaID, FechaHora, TipoMovimiento, Origen, Cantidad, LineaID)
        VALUES
            (@SKUID, @TiendaID, @FechaID, SYSDATETIME(), N'DESCUENTO_DEFINITIVO', N'PICKING', -@Cantidad, @LineaID);

        INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
        VALUES (@LineaID, @EstadoID_Empaquetado, @FechaID, SYSDATETIME());
        -- Dispara trg_ActualizarEstadoActual, que sincroniza EstadoActualID = Empaquetado

        SET @Resultado = N'EMPAQUETADO';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
