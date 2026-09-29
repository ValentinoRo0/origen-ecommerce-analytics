/*
===============================================================================
ORIGEN — Stored Procedure: sp_PrepararRecojo
Fase 3 — Implementación SQL Server
===============================================================================
Transición: Empaquetado → Disponible para recojo
Operación: "Preparar recojo".

Parte de la máquina de estados oficial de Origen (01_procesos_y_reglas.md,
secciones 3.1/3.2). Marca que el pedido quedó listo en tienda esperando al
cliente. Su timestamp en el historial es el que mide la ventana de recojo
(RN-006) — sp_ProcesarVencimientosRecojo vence a partir de AHÍ.

Validación:
1. Estado origen EXACTO 'Empaquetado', leído de FactHistorialEstadoLinea
   (fuente de verdad, RN-008).
2. Canal 'recojo' (error 51041). Es el otro lado de la bifurcación desde
   Empaquetado (ver sp_PrepararDespacho): el canal se exige solo aquí,
   porque los estados posteriores del flujo de recojo ya quedan
   determinados por su origen.

No genera movimientos de inventario: el descuento definitivo ya ocurrió en
sp_ConfirmarPicking (RN-011).

La sincronización de FactPedidoDetalle.EstadoActualID la hace
trg_ActualizarEstadoActual (AFTER INSERT). Concurrencia:
UPDLOCK+ROWLOCK+HOLDLOCK sobre la fila de la línea.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.sp_PrepararRecojo', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_PrepararRecojo;
GO

CREATE PROCEDURE dbo.sp_PrepararRecojo
    @LineaID    INT,
    @FechaID    INT,
    @Resultado  VARCHAR(20) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @EstadoID_Destino INT;
    DECLARE @NombreEstadoOrigen VARCHAR(40);
    DECLARE @Canal VARCHAR(10);

    SELECT @EstadoID_Destino = EstadoID FROM dbo.DimEstado WHERE NombreEstado = N'Disponible para recojo';
    IF @EstadoID_Destino IS NULL
        THROW 51000, N'DimEstado no tiene cargado el estado "Disponible para recojo". Verificar datos semilla.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT @Canal = Canal
        FROM dbo.FactPedidoDetalle WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
        WHERE LineaID = @LineaID;

        IF @Canal IS NULL
            THROW 51010, N'La línea de pedido indicada no existe.', 1;

        -- Estado real = última fila del historial (fuente de verdad).
        SELECT TOP (1) @NombreEstadoOrigen = e.NombreEstado
        FROM dbo.FactHistorialEstadoLinea h
        INNER JOIN dbo.DimEstado e ON e.EstadoID = h.EstadoID
        WHERE h.LineaID = @LineaID
        ORDER BY h.HistorialID DESC;

        IF @NombreEstadoOrigen IS NULL OR @NombreEstadoOrigen <> N'Empaquetado'
            THROW 51011, N'La línea no está en el estado origen de esta operación (debe ser Empaquetado).', 1;

        IF @Canal <> N'recojo'
            THROW 51041, N'Preparar recojo solo aplica a líneas de canal ''recojo'' (la bifurcación desde Empaquetado depende del canal).', 1;

        INSERT INTO dbo.FactHistorialEstadoLinea (LineaID, EstadoID, FechaID, FechaHora)
        VALUES (@LineaID, @EstadoID_Destino, @FechaID, SYSDATETIME());
        -- Dispara trg_ActualizarEstadoActual, que sincroniza EstadoActualID

        SET @Resultado = N'DISPONIBLE';

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO
