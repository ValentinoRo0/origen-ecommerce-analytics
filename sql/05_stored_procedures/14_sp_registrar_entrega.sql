/*
===============================================================================
ORIGEN — Stored Procedure: sp_RegistrarEntrega
Fase 3 — Implementación SQL Server
===============================================================================
Transición: En tránsito → Entregado
Operación: "Registrar entrega".

Parte de la máquina de estados oficial de Origen (01_procesos_y_reglas.md,
secciones 3.1/3.2). Registra la entrega física al cliente en domicilio. Su
timestamp en el historial alimenta el KPI de tiempo de tránsito
(En tránsito → Entregado); el cierre del ciclo es una operación separada
(sp_CompletarPedido) para poder medir el tiempo de cierre por separado y
anclar en él la ventana de devolución (RN-027).

NO valida canal: 'En tránsito' solo puede alcanzarse por
sp_PrepararDespacho (que ya exige canal 'despacho'), así que el origen ya
determina el camino — repetir el chequeo sería redundante.

Validación: estado origen EXACTO 'En tránsito', leído de
FactHistorialEstadoLinea (fuente de verdad, RN-008). La sincronización de
FactPedidoDetalle.EstadoActualID la hace trg_ActualizarEstadoActual
(AFTER INSERT). Concurrencia: UPDLOCK+ROWLOCK+HOLDLOCK sobre la fila.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.sp_RegistrarEntrega', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_RegistrarEntrega;
GO

CREATE PROCEDURE dbo.sp_RegistrarEntrega
    @LineaID    INT,
    @FechaID    INT,
    @Resultado  VARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @EstadoID_Destino INT;
    DECLARE @NombreEstadoOrigen VARCHAR(40);

    SELECT @EstadoID_Destino = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Entregado';
    IF @EstadoID_Destino IS NULL
        THROW 51000, N'DimEstado no tiene cargado el estado "Entregado". Verificar datos semilla.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (
            SELECT 1 FROM dbo.FactPedidoDetalle WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
            WHERE LineaID = @LineaID
        )
            THROW 51010, N'La línea de pedido indicada no existe.', 1;

        -- Estado real = última fila del historial (fuente de verdad).
        SELECT TOP (1) @NombreEstadoOrigen = e.NombreEstado
        FROM dbo.FactHistorialEstadoLinea h
        INNER JOIN dbo.DimEstado e ON e.EstadoID = h.EstadoID
        WHERE h.LineaID = @LineaID
        ORDER BY h.HistorialID DESC;

        IF @NombreEstadoOrigen IS NULL OR @NombreEstadoOrigen <> N'En tránsito'
            THROW 51011, N'La línea no está en el estado origen de esta operación (debe ser En tránsito).', 1;

        INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
        VALUES (@LineaID, @EstadoID_Destino, @FechaID, SYSDATETIME());
        -- Dispara trg_ActualizarEstadoActual, que sincroniza EstadoActualID

        SET @Resultado = N'ENTREGADO';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
