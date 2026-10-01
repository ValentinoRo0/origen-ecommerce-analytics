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

    Datos utilizados durante la prueba ejecutada:

    ClienteID = 4
    SKUID     = 4
    TiendaID  = 6
    FechaID   = 20260102

    La prueba de concurrencia se ejecutó mediante dos sesiones
    independientes de SSMS y se verificó el bloqueo mediante
    sys.dm_exec_requests.

    Resultado validado:

    - Sesión A: INICIADO
    - Sesión B: error 51011
    - Bloqueo observado: LCK_M_U
    - Datos de prueba eliminados posteriormente.
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

   Prueba manual en dos sesiones de SSMS.

   Objetivo:
   Validar que dos ejecuciones concurrentes sobre la misma
   línea no puedan realizar dos veces la misma transición.

   Mecanismo validado:
   - UPDLOCK
   - ROWLOCK
   - HOLDLOCK
   - Validación del estado origen dentro del procedimiento.

   Escenario validado:
   1. La línea se encuentra en "Asignado a picking".
   2. Sesión A bloquea la línea mediante UPDLOCK.
   3. Sesión B intenta obtener el mismo bloqueo y queda esperando.
   4. Sesión A ejecuta sp_IniciarPicking y obtiene INICIADO.
   5. Sesión A hace COMMIT.
   6. Sesión B continúa y observa que la línea ya está
      en "Picking en proceso".
   7. Sesión B ejecuta sp_IniciarPicking y recibe error 51011.

   ============================================================ */

-- ------------------------------------------------------------
-- SESIÓN A
-- ------------------------------------------------------------
-- Ejecutar primero y mantener la transacción abierta.

BEGIN TRANSACTION;

SELECT
    LineaID,
    PedidoID,
    EstadoActualID
FROM dbo.FactPedidoDetalle WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
WHERE LineaID = 53;

-- En este punto la línea queda bloqueada.
-- No hacer COMMIT todavía.


-- ------------------------------------------------------------
-- SESIÓN B
-- ------------------------------------------------------------
-- Ejecutar mientras la Sesión A mantiene la transacción abierta.

SELECT
    LineaID,
    PedidoID,
    EstadoActualID
FROM dbo.FactPedidoDetalle WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
WHERE LineaID = 53;

-- Resultado esperado:
-- La consulta queda esperando el bloqueo de la Sesión A.


-- ------------------------------------------------------------
-- SESIÓN A - ejecutar después de comprobar el bloqueo
-- ------------------------------------------------------------

DECLARE @ResultadoA VARCHAR(20);

EXEC dbo.sp_IniciarPicking
    @LineaID = 53,
    @FechaID = 20260102,
    @Resultado = @ResultadoA OUTPUT;

SELECT @ResultadoA AS Resultado;

-- Resultado esperado:
-- INICIADO


-- ------------------------------------------------------------
-- SESIÓN A - liberar el bloqueo
-- ------------------------------------------------------------

COMMIT TRANSACTION;


-- ------------------------------------------------------------
-- SESIÓN B - después de que la Sesión A haga COMMIT
-- ------------------------------------------------------------

-- La consulta bloqueada debe continuar y mostrar:
-- EstadoActualID = 10 (Picking en proceso).

-- Luego ejecutar:

DECLARE @ResultadoB VARCHAR(20);

EXEC dbo.sp_IniciarPicking
    @LineaID = 53,
    @FechaID = 20260102,
    @Resultado = @ResultadoB OUTPUT;

SELECT @ResultadoB AS Resultado;

-- Resultado esperado:
-- Error 51011
-- La línea no está en el estado origen de esta operación.


-- ============================================================
-- VERIFICACIÓN DE BLOQUEO (OPCIONAL)
-- ============================================================
-- Mientras la Sesión B esté esperando, puede verificarse
-- desde una tercera sesión:

SELECT
    session_id,
    blocking_session_id,
    status,
    wait_type,
    command
FROM sys.dm_exec_requests
WHERE blocking_session_id <> 0;


/* ============================================================
   Resultado esperado de la prueba
   ============================================================

   Sesión A:
       INICIADO

   Sesión B:
       Error 51011

   Durante la espera:
       wait_type = LCK_M_U
       blocking_session_id = sesión A

   Conclusión:
       La operación está protegida frente a dos ejecuciones
       concurrentes de la misma transición.

   ============================================================ */

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