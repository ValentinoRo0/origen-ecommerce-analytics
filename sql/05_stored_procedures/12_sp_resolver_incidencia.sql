/*
===============================================================================
ORIGEN — Stored Procedure: sp_ResolverIncidencia
Fase 3 — Implementación SQL Server
===============================================================================
Transición: Incidencia de picking → Picking en proceso
Operación: "Resolver incidencia".

Referencia: RN-004, RN-019, RN-020 y sección 6.4 de 01_procesos_y_reglas.md.

Qué hace: la incidencia abierta de la línea pasa a 'resuelta' (con su
FechaResolucion) y la línea RETOMA el flujo en 'Picking en proceso', desde
donde puede continuar hacia Empaquetado o recibir otra incidencia.

Qué NO hace (deliberadamente):
- No libera la reserva de stock (RN-012: solo una cancelación libera).
- No cancela la línea — ese camino es sp_CancelarPedido con motivo
  'incidencia_picking' (Incidencia de picking → Cancelado).
- No cambia AreaEscaladaID: el escalamiento es un evento distinto
  (sección 6.4), no se simula aquí.

Validación doble y estricta:
1. Estado origen exacto 'Incidencia de picking', leído de
   FactHistorialEstadoLinea (fuente de verdad, RN-008).
2. La incidencia indicada debe existir, pertenecer a la línea y seguir
   abierta ('en_atencion' o 'escalada') — error 51015.

La sincronización de FactPedidoDetalle.EstadoActualID la hace
trg_ActualizarEstadoActual (AFTER INSERT). Concurrencia:
UPDLOCK+ROWLOCK+HOLDLOCK sobre la fila de la línea.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.sp_ResolverIncidencia', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ResolverIncidencia;
GO

CREATE PROCEDURE dbo.sp_ResolverIncidencia
    @LineaID      INT,
    @IncidenciaID INT,
    @FechaID      INT,
    @Resultado    VARCHAR(20) OUTPUT
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

        -- Estado real = última fila del historial (fuente de verdad).
        SELECT TOP (1) @NombreEstadoOrigen = e.NombreEstado
        FROM dbo.FactHistorialEstadoLinea h
        INNER JOIN dbo.DimEstado e ON e.EstadoID = h.EstadoID
        WHERE h.LineaID = @LineaID
        ORDER BY h.HistorialID DESC;

        IF @NombreEstadoOrigen IS NULL OR @NombreEstadoOrigen <> N'Incidencia de picking'
            THROW 51011, N'La línea no está en el estado origen de esta operación (debe ser Incidencia de picking).', 1;

        -- La incidencia debe existir, pertenecer a la línea y seguir abierta.
        IF NOT EXISTS (
            SELECT 1 FROM dbo.FactIncidencia
            WHERE IncidenciaID = @IncidenciaID AND LineaID = @LineaID
              AND EstadoResolucion IN (N'en_atencion', N'escalada')
        )
            THROW 51015, N'La incidencia indicada no existe, no pertenece a esta línea, o ya no está abierta.', 1;

        UPDATE dbo.FactIncidencia
        SET EstadoResolucion = N'resuelta', FechaResolucion = SYSDATETIME()
        WHERE IncidenciaID = @IncidenciaID;

        INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
        VALUES (@LineaID, @EstadoID_Destino, @FechaID, SYSDATETIME());
        -- Dispara trg_ActualizarEstadoActual, que sincroniza EstadoActualID

        SET @Resultado = N'RESUELTA';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
