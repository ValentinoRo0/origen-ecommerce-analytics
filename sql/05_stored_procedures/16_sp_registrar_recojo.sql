/*
===============================================================================
ORIGEN — Stored Procedure: sp_RegistrarRecojo
Fase 3 — Implementación SQL Server
===============================================================================
Transición: Disponible para recojo → Recojo por cliente
Operación: "Registrar recojo".

Parte de la máquina de estados oficial de Origen (01_procesos_y_reglas.md,
secciones 3.1/3.2). Registra que el cliente retiró el pedido en tienda.
Evento distinto de la entrega a domicilio (sp_RegistrarEntrega): los KPI de
cada canal se calculan por separado, y solo este evento detiene la ventana
de vencimiento (RN-006).

NO valida canal: 'Disponible para recojo' solo puede alcanzarse por
sp_PrepararRecojo (que ya exige canal 'recojo'), así que el origen ya
determina el camino.

Validación: estado origen EXACTO 'Disponible para recojo', leído de
FactHistorialEstadoLinea (fuente de verdad, RN-008). La sincronización de
FactPedidoDetalle.EstadoActualID la hace trg_ActualizarEstadoActual
(AFTER INSERT). Concurrencia: UPDLOCK+ROWLOCK+HOLDLOCK sobre la fila.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.sp_RegistrarRecojo', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_RegistrarRecojo;
GO

CREATE PROCEDURE dbo.sp_RegistrarRecojo
    @LineaID    INT,
    @FechaID    INT,
    @Resultado  VARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @EstadoID_Destino INT;
    DECLARE @NombreEstadoOrigen VARCHAR(40);

    SELECT @EstadoID_Destino = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Recojo por cliente';
    IF @EstadoID_Destino IS NULL
        THROW 51000, N'DimEstado no tiene cargado el estado "Recojo por cliente". Verificar datos semilla.', 1;

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

        IF @NombreEstadoOrigen IS NULL OR @NombreEstadoOrigen <> N'Disponible para recojo'
            THROW 51011, N'La línea no está en el estado origen de esta operación (debe ser Disponible para recojo).', 1;

        INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
        VALUES (@LineaID, @EstadoID_Destino, @FechaID, SYSDATETIME());
        -- Dispara trg_ActualizarEstadoActual, que sincroniza EstadoActualID

        SET @Resultado = N'RECOGIDO';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
