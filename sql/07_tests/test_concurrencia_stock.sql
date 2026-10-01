/*
===============================================================================
PROYECTO: OrigenDB
ARCHIVO: test_concurrencia_stock.sql
TIPO: Prueba de concurrencia y transiciones de picking

OBJETIVO
--------
Validar que las operaciones de picking:

1. Respeten las transiciones de estado permitidas.
2. Actualicen correctamente EstadoActualID.
3. Registren el historial de estados.
4. Eviten procesamiento concurrente de una misma línea.
5. Mantengan la integridad de la reserva de stock.
6. Permitan liberar correctamente el stock al finalizar la prueba.

NOTA
----
Este script utiliza dos sesiones de SQL Server (A y B) para probar
el comportamiento de bloqueo y concurrencia.

Pedido de prueba:
    PedidoID = 991001
    SKUID    = 4
    TiendaID = 6
    Cantidad = 1

Resultado esperado al finalizar:
    StockSistema   = 8
    StockReservado = 0
    StockDisponible = 8
===============================================================================
*/


/* ============================================================================
   1. PREPARACIÓN Y CREACIÓN DEL PEDIDO DE PRUEBA
   ============================================================================ */

-- Verificar que el pedido de prueba no exista.
SELECT *
FROM dbo.FactPedidoDetalle
WHERE PedidoID = 991001;


-- Verificar stock inicial.
SELECT
    SKUID,
    TiendaID,
    StockSistema,
    StockReservado,
    StockSistema - StockReservado AS StockDisponible
FROM dbo.StockSKUTienda
WHERE SKUID = 4
  AND TiendaID = 6;


-- Crear pedido de prueba.
DECLARE @LineaID INT;
DECLARE @Resultado VARCHAR(20);

EXEC dbo.sp_CrearPedido
    @PedidoID = 991001,
    @ClienteID = 4,
    @SKUID = 4,
    @TiendaID = 6,
    @FechaID = 20260102,
    @Canal = 'recojo',
    @Cantidad = 1,
    @LineaID = @LineaID OUTPUT,
    @Resultado = @Resultado OUTPUT;

SELECT
    @LineaID AS LineaID,
    @Resultado AS Resultado;


-- Verificar línea creada.
SELECT
    fpd.LineaID,
    fpd.PedidoID,
    fpd.ClienteID,
    fpd.SKUID,
    fpd.TiendaID,
    fpd.FechaID,
    fpd.Canal,
    fpd.Cantidad,
    fpd.EstadoActualID,
    de.NombreEstado
FROM dbo.FactPedidoDetalle AS fpd
INNER JOIN dbo.DimEstado AS de
    ON de.EstadoID = fpd.EstadoActualID
WHERE fpd.PedidoID = 991001;


-- Verificar reserva.
SELECT
    SKUID,
    TiendaID,
    StockSistema,
    StockReservado,
    StockSistema - StockReservado AS StockDisponible
FROM dbo.StockSKUTienda
WHERE SKUID = 4
  AND TiendaID = 6;


-- Verificar movimiento de inventario.
SELECT
    MovimientoID,
    SKUID,
    TiendaID,
    TipoMovimiento,
    Origen,
    Cantidad,
    LineaID
FROM dbo.FactMovimientoInventario
WHERE LineaID = @LineaID;


/* ============================================================================
   2. CONCURRENCIA: sp_AsignarPicking
   ============================================================================

   IMPORTANTE:
   Ejecutar las siguientes instrucciones en DOS SESIONES de SSMS.

   SESIÓN A:
   ------------------------------------------------------------------------- */

-- SESIÓN A
BEGIN TRANSACTION;

DECLARE @LineaID_A INT;

SELECT
    @LineaID_A = LineaID
FROM dbo.FactPedidoDetalle WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
WHERE PedidoID = 991001;

SELECT
    LineaID,
    PedidoID,
    EstadoActualID
FROM dbo.FactPedidoDetalle
WHERE LineaID = @LineaID_A;

-- NO HACER COMMIT TODAVÍA.


/*
   SESIÓN B:
   Ejecutar mientras la transacción A sigue abierta.
   Esta consulta debe quedar esperando.
   ------------------------------------------------------------------------- */

-- SESIÓN B
DECLARE @LineaID_B INT;

SELECT
    @LineaID_B = LineaID
FROM dbo.FactPedidoDetalle WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
WHERE PedidoID = 991001;

SELECT
    LineaID,
    PedidoID,
    EstadoActualID
FROM dbo.FactPedidoDetalle
WHERE LineaID = @LineaID_B;


/*
   OPCIONAL - SESIÓN C
   Permite observar sesiones bloqueadas mientras B está esperando.
   ------------------------------------------------------------------------- */

SELECT
    session_id,
    blocking_session_id,
    status,
    wait_type,
    command
FROM sys.dm_exec_requests
WHERE blocking_session_id <> 0;


/*
   VOLVER A SESIÓN A
   Ejecutar el procedimiento mientras la transacción sigue abierta.
   ------------------------------------------------------------------------- */

-- SESIÓN A
DECLARE @ResultadoA VARCHAR(20);

EXEC dbo.sp_AsignarPicking
    @LineaID = 2054,
    @FechaID = 20260102,
    @Resultado = @ResultadoA OUTPUT;

SELECT
    @ResultadoA AS Resultado;


-- Liberar el bloqueo.
COMMIT TRANSACTION;


/*
   VOLVER A SESIÓN B
   La consulta bloqueada debe continuar.
   Luego verificar el nuevo estado.
   ------------------------------------------------------------------------- */

-- SESIÓN B
SELECT
    LineaID,
    PedidoID,
    EstadoActualID
FROM dbo.FactPedidoDetalle
WHERE LineaID = @LineaID_B;


-- Intentar nuevamente la operación.
-- Debe rechazarse porque la línea ya no está en Pedido creado.

DECLARE @ResultadoB VARCHAR(20);

EXEC dbo.sp_AsignarPicking
    @LineaID = @LineaID_B,
    @FechaID = 20260102,
    @Resultado = @ResultadoB OUTPUT;

SELECT
    @ResultadoB AS Resultado;


/* ============================================================================
   3. VERIFICACIÓN DE LA PRIMERA TRANSICIÓN
   ============================================================================ */

-- Historial de estados.
SELECT
    h.HistorialID,
    h.LineaID,
    h.EstadoID,
    e.NombreEstado,
    h.FechaID,
    h.FechaHora
FROM dbo.FactHistorialEstadoLinea AS h
INNER JOIN dbo.DimEstado AS e
    ON e.EstadoID = h.EstadoID
WHERE h.LineaID = 2054
ORDER BY h.HistorialID;


-- Estado actual.
SELECT
    fpd.LineaID,
    fpd.PedidoID,
    fpd.EstadoActualID,
    e.NombreEstado
FROM dbo.FactPedidoDetalle AS fpd
INNER JOIN dbo.DimEstado AS e
    ON e.EstadoID = fpd.EstadoActualID
WHERE fpd.LineaID = 2054;


/* ============================================================================
   4. CONCURRENCIA: sp_IniciarPicking
   ============================================================================

   SESIÓN A:
   ------------------------------------------------------------------------- */

-- SESIÓN A
BEGIN TRANSACTION;

DECLARE @LineaID_A2 INT;

SELECT
    @LineaID_A2 = LineaID
FROM dbo.FactPedidoDetalle WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
WHERE PedidoID = 991001;

SELECT
    LineaID,
    PedidoID,
    EstadoActualID
FROM dbo.FactPedidoDetalle
WHERE LineaID = @LineaID_A2;

-- NO HACER COMMIT TODAVÍA.


/*
   SESIÓN B:
   Ejecutar mientras A mantiene la transacción abierta.
   ------------------------------------------------------------------------- */

-- SESIÓN B
DECLARE @LineaID_B2 INT;

SELECT
    @LineaID_B2 = LineaID
FROM dbo.FactPedidoDetalle WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
WHERE PedidoID = 991001;

SELECT
    LineaID,
    PedidoID,
    EstadoActualID
FROM dbo.FactPedidoDetalle
WHERE LineaID = @LineaID_B2;


/*
   OPCIONAL - SESIÓN C
   ------------------------------------------------------------------------- */

SELECT
    session_id,
    blocking_session_id,
    status,
    wait_type,
    command
FROM sys.dm_exec_requests
WHERE blocking_session_id <> 0;


/*
   VOLVER A SESIÓN A
   ------------------------------------------------------------------------- */

-- SESIÓN A
DECLARE @ResultadoA2 VARCHAR(20);

EXEC dbo.sp_IniciarPicking
    @LineaID = 2054,
    @FechaID = 20260102,
    @Resultado = @ResultadoA2 OUTPUT;

SELECT
    @ResultadoA2 AS Resultado;


-- Liberar el bloqueo.
COMMIT TRANSACTION;


/*
   VOLVER A SESIÓN B
   ------------------------------------------------------------------------- */

-- SESIÓN B
SELECT
    LineaID,
    PedidoID,
    EstadoActualID
FROM dbo.FactPedidoDetalle
WHERE LineaID = @LineaID_B2;


-- Intentar nuevamente.
-- Debe rechazarse porque la línea ya no está en Asignado a picking.

DECLARE @ResultadoB2 VARCHAR(20);

EXEC dbo.sp_IniciarPicking
    @LineaID = @LineaID_B2,
    @FechaID = 20260102,
    @Resultado = @ResultadoB2 OUTPUT;

SELECT
    @ResultadoB2 AS Resultado;


/* ============================================================================
   5. VERIFICACIÓN FINAL DE ESTADOS E HISTORIAL
   ============================================================================ */

-- Historial completo esperado:
-- 1  = Pedido creado
-- 9  = Asignado a picking
-- 10 = Picking en proceso

SELECT
    h.HistorialID,
    h.LineaID,
    h.EstadoID,
    e.NombreEstado,
    h.FechaID,
    h.FechaHora
FROM dbo.FactHistorialEstadoLinea AS h
INNER JOIN dbo.DimEstado AS e
    ON e.EstadoID = h.EstadoID
WHERE h.LineaID = 2054
ORDER BY h.HistorialID;


-- Estado final esperado:
-- EstadoActualID = 10
-- NombreEstado = Picking en proceso

SELECT
    fpd.LineaID,
    fpd.PedidoID,
    fpd.EstadoActualID,
    e.NombreEstado
FROM dbo.FactPedidoDetalle AS fpd
INNER JOIN dbo.DimEstado AS e
    ON e.EstadoID = fpd.EstadoActualID
WHERE fpd.LineaID = 2054;


/* ============================================================================
   6. LIMPIEZA DE DATOS DE PRUEBA
   ============================================================================

   La limpieza libera primero la reserva mediante un movimiento
   LIBERACION_RESERVA y posteriormente elimina los registros de prueba.
   ============================================================================ */

BEGIN TRANSACTION;

DECLARE @LineaID_Limpieza INT;

SELECT
    @LineaID_Limpieza = LineaID
FROM dbo.FactPedidoDetalle WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
WHERE PedidoID = 991001;


IF @LineaID_Limpieza IS NULL
BEGIN
    ROLLBACK TRANSACTION;

    PRINT 'No se encontró la línea de prueba. No se realizó limpieza.';
    RETURN;
END;


DECLARE @CantidadReserva INT;

SELECT
    @CantidadReserva =
        ISNULL(
            SUM(
                CASE
                    WHEN TipoMovimiento IN
                    (
                        'RESERVA',
                        'LIBERACION_RESERVA',
                        'DESCUENTO_DEFINITIVO'
                    )
                    THEN Cantidad
                    ELSE 0
                END
            ),
            0
        )
FROM dbo.FactMovimientoInventario
WHERE LineaID = @LineaID_Limpieza;


IF @CantidadReserva <> 0
BEGIN

    INSERT INTO dbo.FactMovimientoInventario
    (
        SKUID,
        TiendaID,
        FechaID,
        FechaHora,
        TipoMovimiento,
        Origen,
        Cantidad,
        LineaID
    )
    SELECT
        SKUID,
        TiendaID,
        20260102,
        SYSDATETIME(),
        'LIBERACION_RESERVA',
        'CANCELACION',
        -@CantidadReserva,
        @LineaID_Limpieza
    FROM dbo.FactPedidoDetalle
    WHERE LineaID = @LineaID_Limpieza;

END;


-- Eliminar historial.
DELETE FROM dbo.FactHistorialEstadoLinea
WHERE LineaID = @LineaID_Limpieza;


-- Eliminar movimientos.
DELETE FROM dbo.FactMovimientoInventario
WHERE LineaID = @LineaID_Limpieza;


-- Eliminar línea.
DELETE FROM dbo.FactPedidoDetalle
WHERE LineaID = @LineaID_Limpieza;


COMMIT TRANSACTION;


/* ============================================================================
   7. VERIFICACIÓN DE LIMPIEZA
   ============================================================================ */

-- Debe devolver 0 filas.
SELECT *
FROM dbo.FactPedidoDetalle
WHERE PedidoID = 991001;


-- Debe devolver 0 filas.
SELECT *
FROM dbo.FactMovimientoInventario
WHERE LineaID = 2054;


-- Debe devolver 0 filas.
SELECT *
FROM dbo.FactHistorialEstadoLinea
WHERE LineaID = 2054;


/* ============================================================================
   8. VERIFICACIÓN FINAL DEL STOCK
   ============================================================================

   Valores esperados:
       StockSistema   = 8
       StockReservado = 0
       StockDisponible = 8
   ============================================================================ */

SELECT
    SKUID,
    TiendaID,
    StockSistema,
    StockReservado,
    StockSistema - StockReservado AS StockDisponible
FROM dbo.StockSKUTienda
WHERE SKUID = 4
  AND TiendaID = 6;


/*
===============================================================================
FIN DEL TEST

RESULTADOS ESPERADOS
--------------------
Pedido de prueba:
    991001

Línea:
    2054

Transiciones:
    Pedido creado
        ↓
    Asignado a picking
        ↓
    Picking en proceso

Concurrencia:
    La segunda sesión queda bloqueada mientras la primera mantiene
    la fila bloqueada y, posteriormente, la operación es rechazada
    cuando el estado origen ya no es válido.

Limpieza:
    0 registros restantes de la prueba.

Stock final:
    StockSistema    = 8
    StockReservado  = 0
    StockDisponible = 8
===============================================================================
*/
