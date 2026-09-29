/*
===============================================================================
ORIGEN — Stored Procedure: sp_IniciarPicking
Fase 3 — Implementación SQL Server
===============================================================================
Transición: Asignado a picking → Picking en proceso
Operación: "Iniciar picking".

Parte de la máquina de estados oficial de Origen (01_procesos_y_reglas.md,
secciones 3.1/3.2). Separa dos eventos operativos distintos y medibles para
KPI: el tiempo en cola (Asignado → Inicio) frente al tiempo de ejecución
del picking (Inicio → Confirmar/Incidencia). Por eso NO se fusiona con
sp_AsignarPicking ni con sp_ConfirmarPicking.

Validación: estado origen EXACTO (Asignado a picking), leído de
FactHistorialEstadoLinea (fuente de verdad, RN-008). El registro del cambio
lo hace este SP; la sincronización de FactPedidoDetalle.EstadoActualID la
hace trg_ActualizarEstadoActual (AFTER INSERT).

Concurrencia: UPDLOCK+ROWLOCK+HOLDLOCK sobre la fila de la línea.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.sp_IniciarPicking', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_IniciarPicking;
GO

CREATE PROCEDURE dbo.sp_IniciarPicking
    @LineaID    INT,
    @FechaID    INT,
    @Resultado  VARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @EstadoID_Destino INT;
    DECLARE @NombreEstadoOrigen VARCHAR(40);

    SELECT @EstadoID_Destino = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Picking en proceso';
    IF @EstadoID_Destino IS NULL
        THROW 51000, N'DimEstado no tiene cargado el estado "Picking en proceso". Verificar datos semilla.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (
            SELECT 1 FROM dbo.FactPedidoDetalle WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
            WHERE LineaID = @LineaID
        )
            THROW 51010, N'La línea de pedido indicada no existe.', 1;

        -- Estado real = última fila del historial (fuente de verdad),
        -- no la copia denormalizada EstadoActualID.
        SELECT TOP (1) @NombreEstadoOrigen = e.NombreEstado
        FROM dbo.FactHistorialEstadoLinea h
        INNER JOIN dbo.DimEstado e ON e.EstadoID = h.EstadoID
        WHERE h.LineaID = @LineaID
        ORDER BY h.HistorialID DESC;

        IF @NombreEstadoOrigen IS NULL OR @NombreEstadoOrigen <> N'Asignado a picking'
            THROW 51011, N'La línea no está en el estado origen de esta operación (debe ser Asignado a picking).', 1;

        INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
        VALUES (@LineaID, @EstadoID_Destino, @FechaID, SYSDATETIME());
        -- Dispara trg_ActualizarEstadoActual, que sincroniza EstadoActualID

        SET @Resultado = N'INICIADO';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
