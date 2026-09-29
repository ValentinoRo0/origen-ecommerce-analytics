/*
===============================================================================
ORIGEN — Stored Procedure: sp_ProcesarVencimientosRecojo
Fase 3 — Implementación SQL Server (versión final)
===============================================================================
Referencia: RN-006.

CORRECCIONES respecto a la versión anterior (2 puntuales, sin cambiar el
diseño de fondo):

1. Justificación de SET XACT_ABORT ON corregida. El hecho técnico es real:
   XACT_ABORT es una configuración de sesión, y SQL Server NO la restaura
   automáticamente al retornar de un procedimiento llamado — si
   sp_CancelarPedido la enciende, queda encendida para el resto de la
   conexión. Pero la razón para tenerla ON aquí NO debe apoyarse en ese
   efecto colateral de una llamada anidada: se establece explícitamente
   porque ESTE procedimiento, por sí mismo, usa transacciones + TRY/CATCH
   y necesita ese comportamiento independientemente de qué haga cualquier
   procedimiento que invoque.

2. Parte 2 (reintento de líneas huérfanas): el criterio de selección pasa
   de "reserva activa > 0" a "reserva activa = Cantidad de la línea". Con
   ">0" se podían seleccionar líneas con una reserva PARCIAL (inconsistencia
   de datos), que sp_CancelarPedido rechaza de todas formas por su propio
   chequeo de igualdad exacta — pero esta versión ya no genera ese intento
   fallido innecesario: simplemente no las selecciona como candidatas.

Concurrencia de la Parte 2 (verificada, sin cambios de diseño): si dos
sesiones detectan la misma línea huérfana, ambas llaman a sp_CancelarPedido,
pero el UPDLOCK+ROWLOCK+HOLDLOCK que YA tiene ese procedimiento sobre
FactPedidoDetalle serializa el acceso — la segunda sesión, al obtener el
lock después de que la primera ya canceló, encuentra el estado actual en
'Cancelado' (no 'Vencido') y su propia validación de estado la rechaza
(error 51013) antes de intentar liberar nada. No se necesita ningún
bloqueo adicional en este procedimiento: la protección crítica ya vive en
sp_CancelarPedido, que es el único punto de escritura sobre la reserva.
Prueba de concurrencia real (dos sesiones simultáneas) no es simulable en
un único script de una sola conexión — queda como prueba manual: abrir
dos pestañas de SSMS, cada una con una llamada a sp_CancelarPedido sobre
la misma línea, ejecutar simultáneamente, y confirmar que solo una tiene
éxito y la otra recibe 51013.

CORRECCIÓN (3ª ronda — cierre del flujo de estados): la relectura de
estado dentro de la Parte 1 (la que decide si la línea pasa a Vencido) se
hace ahora desde FactHistorialEstadoLinea (fuente de verdad, RN-008), no
desde la copia EstadoActualID — mismo criterio que el resto de SP de
transición, y tomando el bloqueo de la línea ANTES de leer el historial.
Los barridos de candidatos de las Partes 1 y 2 SÍ siguen usando
EstadoActualID: para eso existe la copia denormalizada (evita recorrer el
historial en cada barrido) y trg_ActualizarEstadoActual la mantiene fresca
— sin ese trigger las Partes 1 y 2 no encontraban ninguna candidata.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.sp_ProcesarVencimientosRecojo', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ProcesarVencimientosRecojo;
GO

CREATE PROCEDURE dbo.sp_ProcesarVencimientosRecojo
    @FechaHoraActual     DATETIME2(0),
    @DiasVentanaRecojo   INT,
    @FechaID             INT,
    @MotivoVencimientoID INT,
    @LineasProcesadas    INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    -- Se establece explícitamente por las necesidades de ESTE procedimiento
    -- (transacciones + TRY/CATCH), no por lo que haga sp_CancelarPedido.
    SET XACT_ABORT ON;

    DECLARE @EstadoID_DisponibleRecojo INT, @EstadoID_Vencido INT;
    DECLARE @LineaID INT, @ResultadoCancelacion VARCHAR(20);
    DECLARE @EstadoActualLinea INT, @YaVencioAhora BIT;

    SELECT @EstadoID_DisponibleRecojo = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Disponible para recojo';
    SELECT @EstadoID_Vencido = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Vencido';

    IF @EstadoID_DisponibleRecojo IS NULL OR @EstadoID_Vencido IS NULL
        THROW 51000, N'DimEstado no tiene cargados "Disponible para recojo" y/o "Vencido". Verificar datos semilla.', 1;

    SET @LineasProcesadas = 0;

    -- ==========================================================================
    -- PARTE 1: transición Disponible para recojo → Vencido → Cancelado
    -- ==========================================================================
    DECLARE @LineasVencidas TABLE (LineaID INT PRIMARY KEY);

    INSERT INTO @LineasVencidas (LineaID)
    SELECT fp.LineaID
    FROM dbo.FactPedidoDetalle fp
    INNER JOIN dbo.FactHistorialEstadoLinea h
        ON h.LineaID = fp.LineaID AND h.EstadoID = @EstadoID_DisponibleRecojo
    WHERE fp.EstadoActualID = @EstadoID_DisponibleRecojo
      AND h.FechaHora = (
            SELECT MAX(h2.FechaHora) FROM dbo.FactHistorialEstadoLinea h2
            WHERE h2.LineaID = fp.LineaID AND h2.EstadoID = @EstadoID_DisponibleRecojo
          )
      AND DATEDIFF(DAY, h.FechaHora, @FechaHoraActual) >= @DiasVentanaRecojo;

    DECLARE cur1 CURSOR LOCAL FAST_FORWARD FOR SELECT LineaID FROM @LineasVencidas;
    OPEN cur1;
    FETCH NEXT FROM cur1 INTO @LineaID;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @YaVencioAhora = 0;

        BEGIN TRY
            BEGIN TRANSACTION;

            -- Bloquea la fila de la línea (serialización contra otros SP,
            -- mismo criterio que sp_CancelarPedido) y DESPUÉS lee el estado
            -- real desde el historial (fuente de verdad, RN-008), no desde
            -- la copia denormalizada EstadoActualID.
            SET @EstadoActualLinea = NULL;
            IF EXISTS (
                SELECT 1 FROM dbo.FactPedidoDetalle WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
                WHERE LineaID = @LineaID
            )
                SELECT TOP (1) @EstadoActualLinea = EstadoID
                FROM dbo.FactHistorialEstadoLinea
                WHERE LineaID = @LineaID
                ORDER BY HistorialID DESC;

            IF @EstadoActualLinea = @EstadoID_DisponibleRecojo
            BEGIN
                INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
                VALUES (@LineaID, @EstadoID_Vencido, @FechaID, @FechaHoraActual);
                SET @YaVencioAhora = 1;
            END

            COMMIT TRANSACTION;
        END TRY
        BEGIN CATCH
            IF @@TRANCOUNT > 0
                ROLLBACK TRANSACTION;
            PRINT N'[AVISO] No se pudo transicionar a Vencido la línea ' + CAST(@LineaID AS VARCHAR) + N': ' + ERROR_MESSAGE();
            SET @YaVencioAhora = 0;
        END CATCH

        IF @YaVencioAhora = 1
        BEGIN
            BEGIN TRY
                EXEC dbo.sp_CancelarPedido
                    @LineaID = @LineaID, @MotivoID = @MotivoVencimientoID, @FechaID = @FechaID,
                    @IncidenciaID = NULL, @Resultado = @ResultadoCancelacion OUTPUT;

                SET @LineasProcesadas = @LineasProcesadas + 1;
            END TRY
            BEGIN CATCH
                -- La línea queda Vencida con reserva activa; la Parte 2 la
                -- recuperará en una futura ejecución de este procedimiento.
                PRINT N'[AVISO] La línea ' + CAST(@LineaID AS VARCHAR) + N' transicionó a Vencido pero no pudo cancelarse (candidata para la Parte 2): ' + ERROR_MESSAGE();
            END CATCH
        END

        FETCH NEXT FROM cur1 INTO @LineaID;
    END

    CLOSE cur1;
    DEALLOCATE cur1;

    -- ==========================================================================
    -- PARTE 2: reintento de líneas huérfanas — ya en Vencido, con reserva
    -- activa EXACTAMENTE igual a su Cantidad (nunca reservas parciales).
    -- ==========================================================================
    DECLARE @LineasHuerfanas TABLE (LineaID INT PRIMARY KEY);

    INSERT INTO @LineasHuerfanas (LineaID)
    SELECT fp.LineaID
    FROM dbo.FactPedidoDetalle fp
    WHERE fp.EstadoActualID = @EstadoID_Vencido
      AND fp.Cantidad = (
            SELECT ISNULL(SUM(m.Cantidad), 0)
            FROM dbo.FactMovimientoInventario m
            WHERE m.LineaID = fp.LineaID
              AND m.TipoMovimiento IN (N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO')
          );

    DECLARE cur2 CURSOR LOCAL FAST_FORWARD FOR SELECT LineaID FROM @LineasHuerfanas;
    OPEN cur2;
    FETCH NEXT FROM cur2 INTO @LineaID;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        BEGIN TRY
            EXEC dbo.sp_CancelarPedido
                @LineaID = @LineaID, @MotivoID = @MotivoVencimientoID, @FechaID = @FechaID,
                @IncidenciaID = NULL, @Resultado = @ResultadoCancelacion OUTPUT;

            SET @LineasProcesadas = @LineasProcesadas + 1;
            PRINT N'[OK] Reintento exitoso: línea huérfana ' + CAST(@LineaID AS VARCHAR) + N' finalmente cancelada.';
        END TRY
        BEGIN CATCH
            -- Cubre también el caso de concurrencia: si otra sesión ya la
            -- canceló entre que se detectó como candidata y esta llamada,
            -- sp_CancelarPedido la rechaza aquí (estado ya no es Vencido)
            -- sin liberar la reserva por segunda vez.
            PRINT N'[AVISO] Reintento de línea huérfana ' + CAST(@LineaID AS VARCHAR) + N' falló: ' + ERROR_MESSAGE();
        END CATCH

        FETCH NEXT FROM cur2 INTO @LineaID;
    END

    CLOSE cur2;
    DEALLOCATE cur2;
END
GO
