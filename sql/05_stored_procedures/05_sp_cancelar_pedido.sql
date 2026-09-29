/*
===============================================================================
ORIGEN — Stored Procedure: sp_CancelarPedido
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: RN-005, RN-009, RN-012, RN-021.

VERSIÓN CORREGIDA (2ª ronda), 2 cambios:

1. [DECISIÓN PENDIENTE — CANCELACIÓN VOLUNTARIA EN EMPAQUETADO]
   RN-009 permite cancelar voluntariamente desde Empaquetado, pero en ese
   estado la reserva activa neta ya es 0 (DESCUENTO_DEFINITIVO ya canceló
   la RESERVA) — no hay nada que RN-012 pueda liberar. Esto es una
   contradicción real entre ambas reglas, no un bug de este procedimiento.
   Se bloquea explícitamente con el error 51019, describiendo la decisión
   pendiente, en vez de inventar una solución (ver análisis completo en la
   entrega de esta sesión: reingreso automático de stock vs. dejar el
   producto "perdido" hasta conteo físico vs. no permitir la transición).
   El resto de estados de cancelación voluntaria SIGUEN funcionando.

2. La reserva activa ahora debe ser EXACTAMENTE igual a Cantidad, no
   simplemente mayor a cero. Antes, una línea con Cantidad=5 y
   ReservaActiva=3 (una inconsistencia real de datos) se cancelaba
   liberando solo 3, ocultando la discrepancia. Ahora se rechaza y se
   reporta la inconsistencia explícitamente.

3ª RONDA — cierre del flujo de estados, 2 cambios adicionales:

3. El estado real de la línea ya NO se lee de la copia denormalizada
   EstadoActualID (que quedaba obsoleta: solo sp_CrearPedido la escribía
   y el trigger trg_ActualizarEstadoActual no existía — esa era la causa
   directa del fallo 51033 de siempre). Ahora se lee de la última fila de
   FactHistorialEstadoLinea (fuente de verdad, RN-008) bajo el bloqueo de
   la línea. La verificación final SÍ consulta EstadoActualID: pasa a
   validar que el trigger dejó la copia sincronizada tras el INSERT.

4. Orígenes de la cancelación voluntaria exactos según el contrato
   funcional: Pedido creado, Asignado a picking o Picking en proceso.
   'Empaquetado' sigue bloqueado con 51019 (decisión pendiente 1, sin
   cambio) — RN-009 lo permite pero contradice RN-012 sobre el stock ya
   descontado; la contradicción se mantiene documentada, no se resuelve en
   silencio. Incidencia y vencimiento ya validaban origen exacto: sin
   cambios.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.sp_CancelarPedido', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CancelarPedido;
GO

CREATE PROCEDURE dbo.sp_CancelarPedido
    @LineaID      INT,
    @MotivoID     INT,
    @FechaID      INT,
    @IncidenciaID INT = NULL,
    @Resultado    VARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NombreMotivo VARCHAR(50), @TipoMotivoEncontrado VARCHAR(20);
    DECLARE @SKUID INT, @TiendaID INT, @Cantidad INT;
    DECLARE @NombreEstadoActual VARCHAR(40);
    DECLARE @EstadoID_Cancelado INT;
    DECLARE @ReservaActiva INT;
    DECLARE @EstadoFinalID INT, @MotivoFinalID INT;

    SELECT @NombreMotivo = NombreMotivo, @TipoMotivoEncontrado = TipoMotivo
    FROM dbo.DimMotivo WHERE MotivoID = @MotivoID;

    IF @TipoMotivoEncontrado IS NULL OR @TipoMotivoEncontrado <> N'cancelacion'
        THROW 51030, N'MotivoID debe referenciar un motivo de TipoMotivo = ''cancelacion''.', 1;

    IF @NombreMotivo NOT IN (N'voluntaria', N'incidencia_picking', N'vencimiento')
        THROW 51031, N'NombreMotivo de cancelación no reconocido por este procedimiento.', 1;

    IF @NombreMotivo = N'incidencia_picking' AND @IncidenciaID IS NULL
        THROW 51032, N'@IncidenciaID es obligatorio cuando el motivo es incidencia_picking.', 1;
    IF @NombreMotivo <> N'incidencia_picking' AND @IncidenciaID IS NOT NULL
        THROW 51032, N'@IncidenciaID solo debe indicarse cuando el motivo es incidencia_picking.', 1;

    SELECT @EstadoID_Cancelado = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Cancelado';
    IF @EstadoID_Cancelado IS NULL
        THROW 51000, N'DimEstado no tiene cargado el estado "Cancelado". Verificar datos semilla.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @SKUID = SKUID, @TiendaID = TiendaID, @Cantidad = Cantidad
        FROM dbo.FactPedidoDetalle WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
        WHERE LineaID = @LineaID;

        IF @SKUID IS NULL
            THROW 51010, N'La línea de pedido indicada no existe.', 1;

        -- Estado real = última fila del historial (fuente de verdad,
        -- RN-008). NO se lee EstadoActualID: esa copia podía quedar
        -- obsoleta (ver cabecera, punto 3) y de ahí salían cancelaciones
        -- decididas sobre un estado que la línea ya no tenía.
        SELECT TOP (1) @NombreEstadoActual = e.NombreEstado
        FROM dbo.FactHistorialEstadoLinea h
        INNER JOIN dbo.DimEstado e ON e.EstadoID = h.EstadoID
        WHERE h.LineaID = @LineaID
        ORDER BY h.HistorialID DESC;

        -- [DECISIÓN PENDIENTE — ver cabecera del archivo]: no se permite
        -- cancelar voluntariamente una línea Empaquetada hasta que se
        -- decida cómo tratar el stock ya descontado.
        IF @NombreMotivo = N'voluntaria' AND @NombreEstadoActual = N'Empaquetado'
            THROW 51019, N'[DECISIÓN PENDIENTE] Cancelación voluntaria desde Empaquetado requiere definir el tratamiento del stock ya descontado (RN-009 vs RN-012). No implementado hasta esa decisión.', 1;

        -- Orígenes EXACTOS de la cancelación voluntaria según el contrato
        -- funcional (la lista no incluye Empaquetado: ese caso lo cubre
        -- el 51019 de arriba).
        IF @NombreMotivo = N'voluntaria'
           AND ISNULL(@NombreEstadoActual, N'') NOT IN (N'Pedido creado', N'Asignado a picking', N'Picking en proceso')
            THROW 51013, N'Cancelación voluntaria no permitida en el estado actual de la línea (RN-009: solo Pedido creado, Asignado a picking o Picking en proceso).', 1;

        IF @NombreMotivo = N'incidencia_picking' AND ISNULL(@NombreEstadoActual, N'') <> N'Incidencia de picking'
            THROW 51013, N'Cancelación por incidencia solo es válida si la línea está en Incidencia de picking.', 1;

        IF @NombreMotivo = N'vencimiento' AND ISNULL(@NombreEstadoActual, N'') <> N'Vencido'
            THROW 51013, N'Cancelación por vencimiento solo es válida si la línea está en Vencido.', 1;

        SELECT @ReservaActiva = ISNULL(SUM(Cantidad), 0)
        FROM dbo.FactMovimientoInventario
        WHERE LineaID = @LineaID
          AND TipoMovimiento IN (N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO');

        -- CORRECCIÓN: exige coincidencia EXACTA, no solo "> 0". Una reserva
        -- parcial (ReservaActiva <> Cantidad) es una inconsistencia de
        -- datos que debe rechazarse, no liberarse a medias.
        IF @ReservaActiva <> @Cantidad
            THROW 51014, N'Inconsistencia de reserva: se esperaba liberar una reserva activa igual a la cantidad de la línea, pero no coinciden. No se libera una reserva parcial.', 1;

        IF @NombreMotivo = N'incidencia_picking'
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM dbo.FactIncidencia
                WHERE IncidenciaID = @IncidenciaID AND LineaID = @LineaID
                  AND EstadoResolucion IN (N'en_atencion', N'escalada')
            )
                THROW 51015, N'La incidencia indicada no existe, no pertenece a esta línea, o ya no está abierta.', 1;
        END

        INSERT INTO dbo.FactMovimientoInventario
            (SKUID, TiendaID, FechaID, FechaHora, TipoMovimiento, Origen, Cantidad, LineaID)
        VALUES
            (@SKUID, @TiendaID, @FechaID, SYSDATETIME(), N'LIBERACION_RESERVA', N'CANCELACION', -@ReservaActiva, @LineaID);

        UPDATE dbo.FactPedidoDetalle
        SET MotivoCancelacionID = @MotivoID
        WHERE LineaID = @LineaID;

        INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
        VALUES (@LineaID, @EstadoID_Cancelado, @FechaID, SYSDATETIME());

        IF @NombreMotivo = N'incidencia_picking'
        BEGIN
            UPDATE dbo.FactIncidencia
            SET EstadoResolucion = N'no_resuelta', FechaResolucion = SYSDATETIME()
            WHERE IncidenciaID = @IncidenciaID;
        END

        -- Verificación de síntesis: el estado del HISTORIAL ya es Cancelado
        -- (de ahí salió la validación de origen), así que esta comprobación
        -- sobre EstadoActualID valida que trg_ActualizarEstadoActual
        -- sincronizó la copia denormalizada en ESTA misma transacción.
        SELECT @EstadoFinalID = EstadoActualID, @MotivoFinalID = MotivoCancelacionID
        FROM dbo.FactPedidoDetalle WHERE LineaID = @LineaID;

        IF @EstadoFinalID <> @EstadoID_Cancelado OR @MotivoFinalID IS NULL
            THROW 51033, N'Verificación final: EstadoActualID no quedó sincronizado a Cancelado por trg_ActualizarEstadoActual (o el motivo no quedó poblado).', 1;

        SET @Resultado = N'CANCELADO';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
