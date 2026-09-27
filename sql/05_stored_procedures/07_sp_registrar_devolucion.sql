/*
===============================================================================
ORIGEN — Stored Procedure: sp_RegistrarDevolucion
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: RN-026, RN-027.

@DiasVentanaDevolucion se recibe como parámetro OBLIGATORIO, sin valor por
defecto — mismo criterio que @DiasVentanaRecojo en sp_ProcesarVencimientosRecojo.

[RIESGO/INCONSISTENCIA DETECTADA — ver entrega]: ni 01_procesos_y_reglas.md
ni 02_modelo_de_datos.md especifican si una devolución debe generar algún
movimiento de inventario (reingreso de stock). Este procedimiento NO genera
ningún movimiento en FactMovimientoInventario — solo registra el evento,
tal como está definido. Si el negocio requiere reingreso de stock, es una
regla nueva que debe definirse antes de implementarla (no se decide aquí).

Salvaguarda adicional (no es una RN nueva, es integridad operativa del
mismo tipo que ya se usa en otros SP): no se permite más de una devolución
por línea.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.sp_RegistrarDevolucion', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_RegistrarDevolucion;
GO

CREATE PROCEDURE dbo.sp_RegistrarDevolucion
    @LineaID               INT,
    @MotivoID              INT,
    @FechaID               INT,
    @FechaDevolucion       DATETIME2(0),
    @DiasVentanaDevolucion INT,
    @DevolucionID          INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TipoMotivoEncontrado VARCHAR(20);
    DECLARE @EstadoID_Completado INT;
    DECLARE @FechaCompletado DATETIME2(0);

    SELECT @TipoMotivoEncontrado = TipoMotivo FROM dbo.DimMotivo WHERE MotivoID = @MotivoID;
    IF @TipoMotivoEncontrado IS NULL OR @TipoMotivoEncontrado <> N'devolucion'
        THROW 51040, N'MotivoID debe referenciar un motivo de TipoMotivo = ''devolucion''.', 1;

    SELECT @EstadoID_Completado = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Completado';
    IF @EstadoID_Completado IS NULL
        THROW 51000, N'DimEstado no tiene cargado el estado "Completado". Verificar datos semilla.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (
            SELECT 1 FROM dbo.FactPedidoDetalle WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
            WHERE LineaID = @LineaID
        )
            THROW 51010, N'La línea de pedido indicada no existe.', 1;

        IF NOT EXISTS (
            SELECT 1 FROM dbo.FactPedidoDetalle fp
            INNER JOIN dbo.DimEstado e ON e.EstadoID = fp.EstadoActualID
            WHERE fp.LineaID = @LineaID AND e.NombreEstado = N'Completado'
        )
            THROW 51016, N'Solo se puede registrar una devolución sobre una línea en estado Completado (RN-026).', 1;

        SELECT @FechaCompletado = MAX(FechaHora)
        FROM dbo.FactHistorialEstadoLinea
        WHERE LineaID = @LineaID AND EstadoID = @EstadoID_Completado;

        IF DATEDIFF(DAY, @FechaCompletado, @FechaDevolucion) > @DiasVentanaDevolucion
            THROW 51017, N'La fecha de devolución excede la ventana permitida desde el completado (RN-027).', 1;

        IF EXISTS (SELECT 1 FROM dbo.FactDevolucion WHERE LineaID = @LineaID)
            THROW 51018, N'Ya existe una devolución registrada para esta línea.', 1;

        INSERT INTO dbo.FactDevolucion (LineaID, MotivoID, FechaID, FechaDevolucion)
        VALUES (@LineaID, @MotivoID, @FechaID, @FechaDevolucion);

        SET @DevolucionID = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
