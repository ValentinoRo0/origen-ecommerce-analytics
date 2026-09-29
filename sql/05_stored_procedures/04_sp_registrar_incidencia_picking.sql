/*
===============================================================================
ORIGEN — Stored Procedure: sp_RegistrarIncidenciaPicking
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: RN-003, RN-004, RN-019, RN-020. Sección 6 de 01_procesos_y_reglas.md.

CORRECCIÓN (3ª ronda — cierre del flujo de estados): el estado origen se
valida ahora de forma ESTRICTA, solo 'Picking en proceso' (transición
oficial del contrato funcional). Antes se aceptaban también 'Pedido creado'
y 'Asignado a picking', lo que permitía registrar incidencias sobre líneas
que aún no habían entrado al picking. El estado real se lee de
FactHistorialEstadoLinea (fuente de verdad, RN-008), no de la copia
EstadoActualID. El camino inverso (resolver y retomar el flujo) es
sp_ResolverIncidencia; el camino de cancelación es sp_CancelarPedido con
motivo 'incidencia_picking'.

Registra una incidencia detectada durante el picking (producto no
encontrado, cantidad insuficiente, o dañado — NO recepcion_incompleta, que
nace de un movimiento, no de una línea de pedido) y mueve la línea al
estado 'Incidencia de picking'.

DELIBERADAMENTE NO hace lo siguiente (ver discusión sobre filosofía del
proyecto: "operacionalmente correcto, pero analíticamente honesto"):
- No cancela el pedido automáticamente.
- No libera la reserva de stock.
- No ajusta el stock del sistema.
Una incidencia es una observación registrada, no una conclusión. La
resolución (¿se encontró después? ¿hubo que escalar? ¿terminó en
cancelación?) es un evento posterior y separado — ver sección 6.4 de
01_procesos_y_reglas.md.

El primer respondedor (AreaAtencionID) siempre es 'Tienda / Picking', tal
como se confirmó explícitamente en Fase 1, sección 6.1 — no es un
parámetro del procedimiento, es una regla fija del diseño.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.sp_RegistrarIncidenciaPicking', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_RegistrarIncidenciaPicking;
GO

CREATE PROCEDURE dbo.sp_RegistrarIncidenciaPicking
    @LineaID        INT,
    @TipoIncidencia VARCHAR(25),   -- no_encontrado / cantidad_insuficiente / dañado
    @MotivoID       INT,
    @FechaID        INT,
    @IncidenciaID   INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Cantidad INT;
    DECLARE @NombreEstadoOrigen VARCHAR(40);
    DECLARE @EstadoID_Incidencia INT;
    DECLARE @AreaAtencionID INT;
    DECLARE @ReservaActiva INT;
    DECLARE @TipoMotivoEncontrado VARCHAR(20);

    -- Validaciones que no dependen del estado de la línea (se hacen antes
    -- de bloquear nada, para fallar rápido si el llamador se equivocó de
    -- parámetros)
    IF @TipoIncidencia NOT IN (N'no_encontrado', N'cantidad_insuficiente', N'dañado')
    BEGIN
        THROW 51020, N'TipoIncidencia debe ser no_encontrado, cantidad_insuficiente o dañado para una incidencia de picking.', 1;
    END

    SELECT @TipoMotivoEncontrado = TipoMotivo FROM dbo.DimMotivo WHERE MotivoID = @MotivoID;
    IF @TipoMotivoEncontrado IS NULL OR @TipoMotivoEncontrado <> N'incidencia'
    BEGIN
        THROW 51021, N'MotivoID debe referenciar un motivo de TipoMotivo = ''incidencia''.', 1;
    END

    SELECT @EstadoID_Incidencia = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Incidencia de picking';
    IF @EstadoID_Incidencia IS NULL
    BEGIN
        THROW 51000, N'DimEstado no tiene cargado el estado "Incidencia de picking". Verificar datos semilla.', 1;
    END

    SELECT @AreaAtencionID = AreaID FROM dbo.DimArea WHERE NombreArea = N'Tienda / Picking';
    IF @AreaAtencionID IS NULL
    BEGIN
        THROW 51000, N'DimArea no tiene cargada el área "Tienda / Picking". Verificar datos semilla.', 1;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Bloquea la línea antes de validar su estado y su reserva, mismo
        -- criterio que sp_ConfirmarPicking.
        SELECT
            @Cantidad = Cantidad
        FROM dbo.FactPedidoDetalle WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
        WHERE LineaID = @LineaID;

        IF @Cantidad IS NULL
        BEGIN
            THROW 51010, N'La línea de pedido indicada no existe.', 1;
        END

        -- Estado real = última fila del historial (fuente de verdad,
        -- RN-008), no la copia denormalizada EstadoActualID.
        SELECT TOP (1) @NombreEstadoOrigen = e.NombreEstado
        FROM dbo.FactHistorialEstadoLinea h
        INNER JOIN dbo.DimEstado e ON e.EstadoID = h.EstadoID
        WHERE h.LineaID = @LineaID
        ORDER BY h.HistorialID DESC;

        -- Origen EXACTO: solo una línea que está en picking puede tener
        -- incidencia de picking.
        IF @NombreEstadoOrigen IS NULL OR @NombreEstadoOrigen <> N'Picking en proceso'
        BEGIN
            THROW 51011, N'La línea no está en el estado origen de esta operación (debe ser Picking en proceso).', 1;
        END

        -- La incidencia solo tiene sentido si existe una reserva activa
        -- sobre la que hubo un intento de picking (mismo cálculo que en
        -- sp_ConfirmarPicking).
        SELECT @ReservaActiva = ISNULL(SUM(Cantidad), 0)
        FROM dbo.FactMovimientoInventario
        WHERE LineaID = @LineaID
          AND TipoMovimiento IN (N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO');

        IF @ReservaActiva <> @Cantidad
        BEGIN
            THROW 51012, N'No existe una reserva activa que coincida con la cantidad de la línea. No se puede registrar la incidencia.', 1;
        END

        -- Registro de la incidencia: sin tocar stock ni cancelar nada.
        INSERT INTO dbo.FactIncidencia
            (TipoIncidencia, LineaID, MovimientoID, MotivoID, AreaAtencionID, AreaEscaladaID,
             FechaID, FechaDeteccion, EstadoResolucion, FechaResolucion)
        VALUES
            (@TipoIncidencia, @LineaID, NULL, @MotivoID, @AreaAtencionID, NULL,
             @FechaID, SYSDATETIME(), N'en_atencion', NULL);

        SET @IncidenciaID = SCOPE_IDENTITY();

        INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
        VALUES (@LineaID, @EstadoID_Incidencia, @FechaID, SYSDATETIME());
        -- Dispara trg_ActualizarEstadoActual, que sincroniza EstadoActualID = Incidencia de picking

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
