/*
===============================================================================
ORIGEN — Stored Procedure: sp_CompletarPedido
Fase 3 — Implementación SQL Server
===============================================================================
Transiciones: Entregado → Completado  Y  Recojo por cliente → Completado
Operación: "Completar pedido" (cierre del ciclo de vida de la línea).

Parte de la máquina de estados oficial de Origen (01_procesos_y_reglas.md,
secciones 3.1/3.2). Es UNA sola operación de cierre con DOS orígenes
legales — las dos aristas terminales del flujo (domicilio y recojo en
tienda), tal como las define el contrato funcional.

DISEÑO (por qué es un SP aparte y no se fusionó con entrega/recojo):
- El contrato funcional lista "Completar pedido" como operación propia en
  ambas aristas.
- RN-027 ancla la ventana de devolución en la FECHA DE COMPLETADO: se
  necesita su propio timestamp, distinto del de entrega/recojo.
- KPI: el tiempo Entregado → Completado (cierre administrativo) y
  Recojo → Completado son medibles por separado; fusionarlos perdería ese
  evento del historial.

Validación: estado origen EXACTO, en la lista corta y cerrada de los dos
orígenes permitidos (Entregado o Recojo por cliente), leído de
FactHistorialEstadoLinea (fuente de verdad, RN-008). 'Completado' es
estado final (EsFinal = 1): ninguna operación sale de él.

NO cambia EstadoActualID a 'Devolución' ni registra devoluciones: la
devolución es un EVENTO posterior a Completado (sp_RegistrarDevolucion,
FactDevolucion) — el estado 'Devolución' de DimEstado queda fuera del
flujo operativo.

La sincronización de FactPedidoDetalle.EstadoActualID la hace
trg_ActualizarEstadoActual (AFTER INSERT). Concurrencia:
UPDLOCK+ROWLOCK+HOLDLOCK sobre la fila de la línea.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.sp_CompletarPedido', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CompletarPedido;
GO

CREATE PROCEDURE dbo.sp_CompletarPedido
    @LineaID    INT,
    @FechaID    INT,
    @Resultado  VARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @EstadoID_Destino INT;
    DECLARE @NombreEstadoOrigen VARCHAR(40);

    SELECT @EstadoID_Destino = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Completado';
    IF @EstadoID_Destino IS NULL
        THROW 51000, N'DimEstado no tiene cargado el estado "Completado". Verificar datos semilla.', 1;

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

        -- Lista corta y cerrada: los ÚNICOS dos orígenes del contrato.
        IF @NombreEstadoOrigen IS NULL
           OR @NombreEstadoOrigen NOT IN (N'Entregado', N'Recojo por cliente')
            THROW 51011, N'La línea no está en el estado origen de esta operación (debe ser Entregado o Recojo por cliente).', 1;

        INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
        VALUES (@LineaID, @EstadoID_Destino, @FechaID, SYSDATETIME());
        -- Dispara trg_ActualizarEstadoActual, que sincroniza EstadoActualID

        SET @Resultado = N'COMPLETADO';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
