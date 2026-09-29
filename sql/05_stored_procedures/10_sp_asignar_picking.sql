/*
===============================================================================
ORIGEN — Stored Procedure: sp_AsignarPicking
Fase 3 — Implementación SQL Server
===============================================================================
Transición: Pedido creado → Asignado a picking
Operación: "Asignar picking".

Parte de la máquina de estados oficial de Origen (01_procesos_y_reglas.md,
secciones 3.1/3.2 — contrato funcional de transiciones). "Asignado a
picking" marca que la línea entró a la cola de preparación de su tienda; no
recibe parámetros adicionales porque la tienda ya viene asignada en la
creación de la línea (TiendaID, solo NULL en líneas Rechazadas, que nunca
llegan aquí).

Validación: estado origen EXACTO, leído de FactHistorialEstadoLinea (la
fuente de verdad de la trayectoria, RN-008) — no de la copia denormalizada
EstadoActualID. Cada SP valida su único origen y produce su único destino;
no hay tabla genérica de transiciones ni framework de workflow.

El registro del cambio lo hace este SP en FactHistorialEstadoLinea; la
sincronización de FactPedidoDetalle.EstadoActualID la hace
trg_ActualizarEstadoActual (AFTER INSERT) — ver
04_triggers/04_actualizar_estado_actual.sql.

Concurrencia: UPDLOCK+ROWLOCK+HOLDLOCK sobre la fila de la línea (mismo
criterio que sp_CrearPedido / sp_ConfirmarPicking) para serializar
operaciones concurrentes sobre la misma línea.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.sp_AsignarPicking', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_AsignarPicking;
GO

CREATE PROCEDURE dbo.sp_AsignarPicking
    @LineaID    INT,
    @FechaID    INT,
    @Resultado  VARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @EstadoID_Destino INT;
    DECLARE @NombreEstadoOrigen VARCHAR(40);

    SELECT @EstadoID_Destino = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Asignado a picking';
    IF @EstadoID_Destino IS NULL
        THROW 51000, N'DimEstado no tiene cargado el estado "Asignado a picking". Verificar datos semilla.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Bloquea la línea antes de leer nada: serializa contra cualquier
        -- otra operación concurrente sobre la misma línea.
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

        IF @NombreEstadoOrigen IS NULL OR @NombreEstadoOrigen <> N'Pedido creado'
            THROW 51011, N'La línea no está en el estado origen de esta operación (debe ser Pedido creado).', 1;

        INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
        VALUES (@LineaID, @EstadoID_Destino, @FechaID, SYSDATETIME());
        -- Dispara trg_ActualizarEstadoActual, que sincroniza EstadoActualID

        SET @Resultado = N'ASIGNADO';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
