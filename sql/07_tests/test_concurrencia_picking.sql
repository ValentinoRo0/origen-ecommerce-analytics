/*
    OrigenDB
    Test: Transiciones de estado y concurrencia en picking

    Objetivo:
    Validar:
    1. Creación correcta de una línea de pedido.
    2. Reserva de stock.
    3. Registro del historial de estados.
    4. Transición Pedido creado -> Asignado a picking.
    5. Transición Asignado a picking -> Picking en proceso.
    6. Sincronización de EstadoActualID.
    7. Protección contra ejecución concurrente de sp_IniciarPicking.

    Datos utilizados:
    ClienteID = 4
    SKUID     = 4
    TiendaID  = 6
    FechaID   = 20260102
    PedidoID  = 990001
    LineaID   = 53

    Resultado esperado de concurrencia:
    - Sesión A: INICIADO
    - Sesión B: error 51011
*/

USE OrigenDB;
GO


/* ============================================================
   1. VERIFICAR LÍNEA CREADA
   ============================================================ */

SELECT
    LineaID,
    PedidoID,
    ClienteID,
    SKUID,
    TiendaID,
    FechaID,
    Canal,
    Cantidad,
    EstadoActualID,
    MotivoCancelacionID
FROM dbo.FactPedidoDetalle
WHERE LineaID = 53;
GO


/* ============================================================
   2. VERIFICAR HISTORIAL INICIAL
   ============================================================ */

SELECT
    h.HistorialID,
    h.LineaID,
    h.EstadoID,
    e.NombreEstado,
    h.FechaID,
    h.FechaHora
FROM dbo.FactHistorialEstadoLinea h
INNER JOIN dbo.DimEstado e
    ON e.EstadoID = h.EstadoID
WHERE h.LineaID = 53
ORDER BY h.HistorialID;
GO


/* ============================================================
   3. VERIFICAR RESERVA DE STOCK
   ============================================================ */

SELECT
    SKUID,
    TiendaID,
    StockSistema,
    StockReservado,
    StockSistema - StockReservado AS StockDisponible
FROM dbo.StockSKUTienda
WHERE SKUID = 4
  AND TiendaID = 6;
GO


/* ============================================================
   4. VERIFICAR MOVIMIENTO DE RESERVA
   ============================================================ */

SELECT
    MovimientoID,
    SKUID,
    TiendaID,
    FechaID,
    FechaHora,
    TipoMovimiento,
    Origen,
    Cantidad,
    LineaID,
    CantidadEsperada,
    CantidadRecibida,
    Discrepancia,
    MotivoID
FROM dbo.FactMovimientoInventario
WHERE LineaID = 53
ORDER BY MovimientoID;
GO


/* ============================================================
   5. ASIGNAR PICKING
   ============================================================ */

DECLARE @ResultadoAsignar VARCHAR(20);

EXEC dbo.sp_AsignarPicking
    @LineaID = 53,
    @FechaID = 20260102,
    @Resultado = @ResultadoAsignar OUTPUT;

SELECT @ResultadoAsignar AS Resultado;
GO


/* ============================================================
   6. VERIFICAR ASIGNACIÓN A PICKING
   ============================================================ */

SELECT
    h.HistorialID,
    h.LineaID,
    h.EstadoID,
    e.NombreEstado,
    h.FechaID,
    h.FechaHora
FROM dbo.FactHistorialEstadoLinea h
INNER JOIN dbo.DimEstado e
    ON e.EstadoID = h.EstadoID
WHERE h.LineaID = 53
ORDER BY h.HistorialID;
GO

SELECT
    fd.LineaID,
    fd.PedidoID,
    fd.EstadoActualID,
    e.NombreEstado
FROM dbo.FactPedidoDetalle fd
INNER JOIN dbo.DimEstado e
    ON e.EstadoID = fd.EstadoActualID
WHERE fd.LineaID = 53;
GO


/* ============================================================
   7. CONCURRENCIA - sp_IniciarPicking
   ============================================================

   Ejecutar el siguiente bloque simultáneamente en dos
   ventanas de SSMS.

   SESIÓN A:
   ------------------------------------------------------------

   DECLARE @Resultado VARCHAR(20);

   EXEC dbo.sp_IniciarPicking
       @LineaID = 53,
       @FechaID = 20260102,
       @Resultado = @Resultado OUTPUT;

   SELECT @Resultado AS Resultado;


   SESIÓN B:
   ------------------------------------------------------------

   DECLARE @Resultado VARCHAR(20);

   EXEC dbo.sp_IniciarPicking
       @LineaID = 53,
       @FechaID = 20260102,
       @Resultado = @Resultado OUTPUT;

   SELECT @Resultado AS Resultado;


   Resultado esperado:
   - Una sesión: INICIADO
   - La otra sesión: error 51011
*/


/* ============================================================
   8. VERIFICACIÓN FINAL
   ============================================================ */

SELECT
    h.HistorialID,
    h.LineaID,
    h.EstadoID,
    e.NombreEstado,
    h.FechaID,
    h.FechaHora
FROM dbo.FactHistorialEstadoLinea h
INNER JOIN dbo.DimEstado e
    ON e.EstadoID = h.EstadoID
WHERE h.LineaID = 53
ORDER BY h.HistorialID;
GO

SELECT
    fd.LineaID,
    fd.PedidoID,
    fd.EstadoActualID,
    e.NombreEstado
FROM dbo.FactPedidoDetalle fd
INNER JOIN dbo.DimEstado e
    ON e.EstadoID = fd.EstadoActualID
WHERE fd.LineaID = 53;
GO