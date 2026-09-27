/*
===============================================================================
ORIGEN — Stored Procedure: sp_CrearPedido
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: RN-001, RN-002, RN-010.

VERSIÓN CORREGIDA tras revisión, con 3 cambios respecto a la primera versión:
1. Valida @Cantidad > 0 antes de iniciar la transacción — sin esto, un
   valor negativo podría "pasar" la comparación de disponibilidad y generar
   un movimiento RESERVA con cantidad negativa, rompiendo la semántica de
   Cantidad definida en 06_fact_movimiento_inventario.sql.
2. Si no existe fila en StockSKUTienda para el SKU+Tienda solicitado, ya
   NO se asume "stock 0" — con la pre-siembra como requisito de Fase 4,
   la ausencia de fila es un problema de datos/configuración y debe
   detener la operación con un error explícito.
3. Comentario de ROWLOCK corregido: no "garantiza" bloqueo de fila, sino
   que lo solicita — SQL Server puede escalar el bloqueo bajo ciertas
   condiciones. La protección real contra la condición de carrera la dan
   UPDLOCK + HOLDLOCK sobre la fila dentro de la transacción.

Implementa la reserva atómica de stock al crear una línea de pedido:
- Si hay stock disponible suficiente → crea la línea como "Pedido creado",
  registra el historial, y genera el movimiento RESERVA.
- Si no hay stock suficiente → crea la línea como "Rechazado" (demanda
  insatisfecha, sección 2.2 de 01_procesos_y_reglas.md), sin TiendaID ni
  movimiento de inventario.

Control de concurrencia (RN-002):
- UPDLOCK: reserva la fila para escritura desde el momento de la lectura.
- ROWLOCK: solicita a SQL Server usar bloqueo a nivel de fila cuando sea
  posible, para no bloquear innecesariamente otras filas de SKU/tienda
  distintos (no es una garantía absoluta de que nunca se escalará).
- HOLDLOCK: mantiene el bloqueo hasta el final de la transacción (equivale
  a aislamiento SERIALIZABLE para esta lectura puntual).
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.sp_CrearPedido', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CrearPedido;
GO

CREATE PROCEDURE dbo.sp_CrearPedido
    @PedidoID   INT,
    @ClienteID  INT,
    @SKUID      INT,
    @TiendaID   INT,
    @FechaID    INT,
    @Canal      VARCHAR(10),
    @Cantidad   INT,
    @LineaID    INT OUTPUT,
    @Resultado  VARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Validación de integridad de la operación (no es una RN nueva):
    -- una línea de pedido nunca puede solicitar 0 o menos unidades.
    IF @Cantidad <= 0
    BEGIN
        THROW 51001, N'@Cantidad debe ser mayor a 0.', 1;
        RETURN;
    END

    DECLARE @StockDisponible       INT;
    DECLARE @FilaStockExiste       BIT = 0;
    DECLARE @EstadoID_PedidoCreado INT;
    DECLARE @EstadoID_Rechazado    INT;

    SELECT @EstadoID_PedidoCreado = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Pedido creado';
    SELECT @EstadoID_Rechazado    = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Rechazado';

    IF @EstadoID_PedidoCreado IS NULL OR @EstadoID_Rechazado IS NULL
    BEGIN
        THROW 51000, N'DimEstado no tiene cargados los estados "Pedido creado" y/o "Rechazado". Verificar datos semilla.', 1;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Paso crítico de concurrencia: bloquea la fila de stock ANTES de
        -- decidir si hay disponibilidad.
        SELECT
            @StockDisponible = StockSistema - StockReservado,
            @FilaStockExiste = 1
        FROM dbo.StockSKUTienda WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
        WHERE SKUID = @SKUID AND TiendaID = @TiendaID;

        IF @FilaStockExiste = 0
        BEGIN
            -- Con pre-siembra obligatoria (Fase 4), esto NO es "stock 0":
            -- es una inconsistencia de datos/configuración que debe
            -- detener la operación, no resolverse en silencio.
            THROW 51002, N'No existe fila en StockSKUTienda para el SKU y Tienda indicados. Verificar pre-siembra de Fase 4.', 1;
        END

        IF @StockDisponible >= @Cantidad
        BEGIN
            -- ===== HAY STOCK: crear la línea y reservar =====
            INSERT INTO dbo.FactPedidoDetalle
                (PedidoID, ClienteID, SKUID, TiendaID, FechaID, Canal, Cantidad, EstadoActualID, MotivoCancelacionID)
            VALUES
                (@PedidoID, @ClienteID, @SKUID, @TiendaID, @FechaID, @Canal, @Cantidad, @EstadoID_PedidoCreado, NULL);

            SET @LineaID = SCOPE_IDENTITY();

            INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
            VALUES (@LineaID, @EstadoID_PedidoCreado, @FechaID, SYSDATETIME());

            -- Dispara trg_ActualizarStockSKUTienda, que incrementa StockReservado
            INSERT INTO dbo.FactMovimientoInventario
                (SKUID, TiendaID, FechaID, FechaHora, TipoMovimiento, Origen, Cantidad, LineaID)
            VALUES
                (@SKUID, @TiendaID, @FechaID, SYSDATETIME(), N'RESERVA', N'PEDIDO', @Cantidad, @LineaID);

            SET @Resultado = N'CREADO';
        END
        ELSE
        BEGIN
            -- ===== NO HAY STOCK: Rechazado, demanda insatisfecha =====
            INSERT INTO dbo.FactPedidoDetalle
                (PedidoID, ClienteID, SKUID, TiendaID, FechaID, Canal, Cantidad, EstadoActualID, MotivoCancelacionID)
            VALUES
                (@PedidoID, @ClienteID, @SKUID, NULL, @FechaID, @Canal, @Cantidad, @EstadoID_Rechazado, NULL);

            SET @LineaID = SCOPE_IDENTITY();

            INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
            VALUES (@LineaID, @EstadoID_Rechazado, @FechaID, SYSDATETIME());

            SET @Resultado = N'RECHAZADO';
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
