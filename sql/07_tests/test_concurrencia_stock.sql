/*
    OrigenDB
    Test: Concurrencia de reserva de stock

    Objetivo:
    Validar que dos pedidos concurrentes no puedan reservar
    la misma unidad disponible.

    Escenario:
    SKU 10 (A30002)
    Producto: Jean slim
    Talla: 34
    Color: Azul

    Tienda:
    TiendaID = 7
    Nombre = Real Plaza Arequipa

    Stock inicial:
    StockSistema   = 1
    StockReservado = 0
    StockDisponible = 1

    Pedidos:
    Sesión A -> PedidoID 990002
    Sesión B -> PedidoID 990003

    Ambas sesiones solicitan:
    Cantidad = 1

    Resultado esperado:
    - Una sesión obtiene CREADO.
    - La otra obtiene RECHAZADO.
    - StockReservado termina en 1.
    - StockDisponible termina en 0.
    - Solo existe un movimiento RESERVA.
    - Solo el pedido creado tiene TiendaID asignada.
*/


USE OrigenDB;
GO


/* ============================================================
   1. VERIFICAR STOCK INICIAL
   ============================================================ */

SELECT
    SKUID,
    TiendaID,
    StockSistema,
    StockReservado,
    StockSistema - StockReservado AS StockDisponible
FROM dbo.StockSKUTienda
WHERE SKUID = 10
  AND TiendaID = 7;
GO


/* ============================================================
   2. CONCURRENCIA
   ============================================================

   Ejecutar los siguientes bloques simultáneamente
   en DOS ventanas de SSMS.

   ------------------------------------------------------------
   SESIÓN A
   ------------------------------------------------------------

   DECLARE @LineaID INT,
           @Resultado VARCHAR(20);

   EXEC dbo.sp_CrearPedido
       @PedidoID   = 990002,
       @ClienteID  = 4,
       @SKUID      = 10,
       @TiendaID   = 7,
       @FechaID    = 20260102,
       @Canal      = 'recojo',
       @Cantidad   = 1,
       @LineaID    = @LineaID OUTPUT,
       @Resultado  = @Resultado OUTPUT;

   SELECT
       @LineaID AS LineaID,
       @Resultado AS Resultado;


   ------------------------------------------------------------
   SESIÓN B
   ------------------------------------------------------------

   DECLARE @LineaID INT,
           @Resultado VARCHAR(20);

   EXEC dbo.sp_CrearPedido
       @PedidoID   = 990003,
       @ClienteID  = 4,
       @SKUID      = 10,
       @TiendaID   = 7,
       @FechaID    = 20260102,
       @Canal      = 'recojo',
       @Cantidad   = 1,
       @LineaID    = @LineaID OUTPUT,
       @Resultado  = @Resultado OUTPUT;

   SELECT
       @LineaID AS LineaID,
       @Resultado AS Resultado;


   Resultado esperado:
   - Una sesión: CREADO
   - La otra sesión: RECHAZADO
*/


/* ============================================================
   3. VERIFICAR STOCK FINAL
   ============================================================ */

SELECT
    SKUID,
    TiendaID,
    StockSistema,
    StockReservado,
    StockSistema - StockReservado AS StockDisponible
FROM dbo.StockSKUTienda
WHERE SKUID = 10
  AND TiendaID = 7;
GO


/* ============================================================
   4. VERIFICAR LÍNEAS DE PEDIDO
   ============================================================ */

SELECT
    fd.LineaID,
    fd.PedidoID,
    fd.SKUID,
    fd.TiendaID,
    fd.Cantidad,
    fd.EstadoActualID,
    e.NombreEstado,
    fd.MotivoCancelacionID
FROM dbo.FactPedidoDetalle fd
INNER JOIN dbo.DimEstado e
    ON e.EstadoID = fd.EstadoActualID
WHERE fd.LineaID IN (54, 55)
ORDER BY fd.LineaID;
GO


/* ============================================================
   5. VERIFICAR MOVIMIENTOS DE INVENTARIO
   ============================================================ */

SELECT
    MovimientoID,
    SKUID,
    TiendaID,
    TipoMovimiento,
    Origen,
    Cantidad,
    LineaID
FROM dbo.FactMovimientoInventario
WHERE LineaID IN (54, 55)
ORDER BY MovimientoID;
GO


/* ============================================================
   6. VERIFICAR HISTORIAL DE ESTADOS
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
WHERE h.LineaID IN (54, 55)
ORDER BY h.LineaID, h.HistorialID;
GO