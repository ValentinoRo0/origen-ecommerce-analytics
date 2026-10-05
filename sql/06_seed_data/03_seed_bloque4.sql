/*
===============================================================================
ORIGEN — Seed del Bloque 4: 45 pedidos / 52 líneas (Fase 4)
===============================================================================
Archivo único del Bloque 4. NO modifica tablas, columnas, PK/FK/CHECK,
triggers, vistas ni stored procedures; NO crea entidades permanentes
(solo variables de tabla). Requiere 01_datos_maestros.sql y
02_presiembra_stock_sku_tienda.sql ejecutados previamente.

EJECUCIÓN (dos sesiones, mismo archivo):
  sqlcmd -S localhost -E -d OrigenDB -f 65001 -i sql\06_seed_data\03_seed_bloque4.sql

  - SESIÓN 1 (batch 1): secciones A..H. Crea los pedidos y ejecuta el flujo
    hasta el estado final de sesión 1; valida Q01-Q13 y C01-C24 con valores
    de sesión 1 y reporta "IMPLEMENTADO — PENDIENTE SESIÓN 2".
  - SESIÓN 2 (batch 2): secciones I..J. Exige un día natural real posterior
    (gate temporal con SYSDATETIME()); ejecuta escalamientos, cancelaciones
    por incidencia, resolución de la incidencia de recepción, flujo final y
    vencimientos; re-valida todo con los valores finales y reporta
    "IMPLEMENTADO Y VALIDADO".
  Si la sesión 2 se ejecuta el mismo día, DETIENE con el mensaje exacto:
  "La sesión 2 no puede ejecutarse todavía porque no se ha cumplido el
   intervalo temporal real requerido."

ESTADOS DEL REPORTE §41:
  - IMPLEMENTADO — PENDIENTE SESIÓN 2   (sesión 1 correcta)
  - IMPLEMENTADO Y VALIDADO             (sesión 2 correcta)
  - DETENIDO POR INCOMPATIBILIDAD       (validación en FALLA o error con ROLLBACK)

SECCIONES:
  A. Prevalidaciones + guard de idempotencia (sin DELETE: si existen pedidos
     100001-100045 se omiten las operaciones).
  B. Recepciones CD (DML directo documentado: INGRESO + Origen RECEPCION_CD,
     FechaID 20260101; 8 recepciones = 6 exactas + 2 incompletas).
  C. Ajustes de conteo físico (DML directo documentado: AJUSTE MotivoID 14
     Origen CONTEO_FISICO, FechaID 20260101; 6 filas: +2 SKU6×T6, +1 SKU8×T8,
     +3 SKU13×T6, −2 SKU4×T7, −1 SKU7×T6, −1 SKU12×T8).
  D. Creación de 52 líneas / 45 pedidos vía sp_CrearPedido (cursor).
  E. Operaciones de flujo vía SPs (cursor por Tipo):
     CR/CD/CI/VN completan el camino de asignar→iniciar→[incidencia CI→
     resolver]→confirmar→preparar→registrar→completar (VN se detiene en
     "Disponible para recojo"); XI/IP/IR se detienen en incidencia creada;
     XV cancela voluntaria (MotivoID 7) según origen; RJ = RECHAZADO.
  F. Incidencias recepcion_incompleta (DML directo documentado: creación y
     resolución). Cada recepción incompleta genera EXACTAMENTE 1 incidencia
     (D-J resuelta); la #1 se resuelve en sesión 1, la #2 queda en_atencion.
  G. Devoluciones vía sp_RegistrarDevolucion (6: motivos 15/16/17 en 2/2/2,
     FechaID = F+k con k<=7, @FechaDevolucion = SYSDATETIME() real).
  H. Validaciones Q01-Q13 + C01-C24 (valores de sesión 1) + reporte.
  I. Sesión 2: escalamientos (DML directo documentado: transición escalada +
     AreaEscaladaID), cancelaciones XI (MotivoID 8 + incidencia), resolución
     IR + flujo final, escalada de la recepción pendiente (área 3) y
     vencimientos vía sp_ProcesarVencimientosRecojo.
  J. Validaciones finales (valores definitivos) + reporte.

DATASET (diseño cerrado):
  - 45 pedidos 100001-100045 / 52 líneas; clientes 4..9 = 8/8/8/7/7/7.
  - Fechas: ene 12 / feb 11 / mar 1-14 10 / campaña 9 / mar 22-31 3,
    43 FechaID distintos (>=25); campaña = 20260315-20260321 con >=1
    incidencia y >=1 cancelación.
  - Canal: 27 recojo / 18 despacho (pedidos); 31/21 líneas.
  - Tiendas: T6=16, T7=16, T8=12 (líneas no rechazadas), T5=0; 8 rechazados
    con TiendaID NULL y cantidades 4,4,3,3,2,2,1,1.
  - Estados final (sesión 2): 31 Completado, 11 Cancelado (6 voluntaria /
    3 incidencia / 2 vencimiento), 8 Rechazado, 2 Incidencia de picking.
    Sesión 1: 30/6/8/6/2 (2 en "Disponible para recojo").
  - Cantidades: 1→29, 2→14, 3→6, 4→3.
  - Incidencias 11: picking 9 (4 no_encontrado / 3 cantidad_insuficiente /
    2 dañado) + 2 recepción; estados 5 resueltas / 3 no_resueltas /
    2 en_atencion / 1 escalada; matriz §25:
      ne 1/1/1/0; ci 1/1/1/0; da 1/1/0/0; rec 1/0/0/1 (res/no_res/atencion/esc)
  - SKUs: 14 distintos en FactPedidoDetalle (>=12) y 14 con movimiento;
    4 categorías.
  - Movimientos nuevos: sesión 1 = 96 (8 INGRESO + 6 AJUSTE + 44 RESERVA +
    32 DESC + 6 LIBER) → ledger 110; sesión 2 = 6 (3 LIBER + 1 DESC +
    2 AJUSTE retorno) → ledger 116. Stock SOLO vía
    FactMovimientoInventario → trigger; NUNCA se hace UPDATE a
    StockSKUTienda. Ancla SKU4×T6 intacta: 8/0/8 y exactamente 8 movimientos.

DECISIONES RESUELTAS (no son preguntas abiertas):
  - D-I: AreaEscaladaID = 3 (Abastecimiento) para la escalada persistente de
    la recepcion_incompleta de sesión 2. Escaladas de picking = área 2
    (Operaciones E-commerce).
  - D-J: 8 recepciones = 6 exactas + 2 incompletas; cada incompleta genera
    exactamente una FactIncidencia TipoIncidencia='recepcion_incompleta';
    se mantienen 11 incidencias totales y la distribución 5/3/2/1.
    NO existen referencias a "4 recepciones incompletas" ni "13 incidencias"
    (verificado en el repositorio antes de implementar).

RESTRICCIONES CUMPLIDAS:
  - Todo dato se siembra con los 14 SPs salvo las 4 excepciones de DML
    directo documentadas arriba (recepciones, ajustes de conteo,
    incidencias de recepción, escalamientos).
  - FechaID = fecha de negocio (DimFecha 2026); FechaHora = SYSDATETIME()
    real en cada operación; sin RAND(); sin timestamps futuros fabricados.
  - Transacción con ROLLBACK + reporte + THROW ante fallo (THROW termina el
    batch); guard de idempotencia sin DELETE; validaciones al final del
    mismo archivo; test_vistas.sql NO se modifica.

§41/§42/§43/§44 = secciones del prompt de implementación del Bloque 4.
===============================================================================
*/

USE OrigenDB;
GO

-- ===========================================================================
-- SESIÓN 1 — BATCH 1 — Secciones A..H
-- ===========================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;

-- ---------------------------------------------------------------------------
-- A. Dataset de líneas (fuente única del diseño) + prevalidaciones + guard
-- ---------------------------------------------------------------------------
DECLARE @Lineas TABLE
(
    N            INT IDENTITY(1, 1) NOT NULL PRIMARY KEY,
    PedidoID     INT      NOT NULL,
    Orden        TINYINT  NOT NULL,
    ClienteID    INT      NOT NULL,
    FechaID      INT      NOT NULL,
    Canal        VARCHAR(10) NOT NULL,
    SKUID        INT      NOT NULL,
    TiendaID     INT      NOT NULL,  -- tienda intentada (NULL si RECHAZADO)
    Cantidad     INT      NOT NULL,
    Tipo         CHAR(2)  NOT NULL,  -- CR CD CI XI IP IR XV VN RJ
    MotivoIncID  INT      NULL,      -- 10/11/12 para tipos con incidencia
    XVOrigen     TINYINT  NULL,      -- 1 Pedido creado, 2 Asignado, 3 Picking
    LineaID      INT      NULL       -- se llena tras sp_CrearPedido (no RJ)
);

INSERT INTO @Lineas
    (PedidoID, Orden, ClienteID, FechaID, Canal, SKUID, TiendaID, Cantidad, Tipo, MotivoIncID, XVOrigen)
VALUES
    (100001, 1, 4, 20260102, 'recojo',   5, 6, 2, 'CR', NULL, NULL),
    (100001, 2, 4, 20260102, 'recojo',   7, 6, 4, 'CR', NULL, NULL),
    (100002, 1, 5, 20260105, 'despacho', 4, 7, 1, 'CD', NULL, NULL),
    (100002, 2, 5, 20260105, 'despacho', 9, 7, 1, 'CD', NULL, NULL),
    (100003, 1, 6, 20260107, 'recojo',   5, 6, 1, 'CR', NULL, NULL),
    (100004, 1, 7, 20260109, 'recojo',   5, 6, 2, 'CR', NULL, NULL),
    (100005, 1, 8, 20260112, 'recojo',   7, 6, 1, 'CR', NULL, NULL),
    (100006, 1, 9, 20260114, 'recojo',  16, 6, 1, 'CR', NULL, NULL),
    (100007, 1, 4, 20260116, 'recojo',  16, 6, 1, 'CR', NULL, NULL),
    (100008, 1, 5, 20260119, 'despacho', 5, 6, 1, 'XV', NULL, 1),
    (100009, 1, 6, 20260121, 'recojo',   5, 6, 1, 'XV', NULL, 2),
    (100010, 1, 7, 20260123, 'recojo',  10, 7, 1, 'CR', NULL, NULL),
    (100011, 1, 8, 20260126, 'recojo',  14, 7, 2, 'CR', NULL, NULL),
    (100012, 1, 9, 20260128, 'despacho', 8, 7, 4, 'RJ', NULL, NULL),
    (100013, 1, 4, 20260202, 'recojo',  16, 6, 2, 'CR', NULL, NULL),
    (100013, 2, 4, 20260202, 'recojo',   5, 6, 1, 'XV', NULL, 3),
    (100014, 1, 5, 20260204, 'despacho', 4, 7, 3, 'CD', NULL, NULL),
    (100014, 2, 5, 20260204, 'despacho',14, 7, 1, 'XI', 12, NULL),
    (100015, 1, 6, 20260206, 'recojo',   5, 6, 3, 'XI', 10, NULL),
    (100016, 1, 7, 20260209, 'recojo',   7, 6, 1, 'CI', 12, NULL),
    (100017, 1, 8, 20260211, 'recojo',   4, 7, 1, 'CR', NULL, NULL),
    (100018, 1, 9, 20260213, 'recojo',  14, 7, 1, 'CR', NULL, NULL),
    (100019, 1, 4, 20260216, 'despacho', 4, 7, 3, 'CD', NULL, NULL),
    (100020, 1, 5, 20260218, 'despacho', 4, 7, 2, 'CD', NULL, NULL),
    (100021, 1, 6, 20260220, 'recojo',  11, 8, 2, 'CR', NULL, NULL),
    (100022, 1, 7, 20260224, 'recojo',   8, 6, 3, 'RJ', NULL, NULL),
    (100023, 1, 8, 20260226, 'despacho',13, 7, 2, 'RJ', NULL, NULL),
    (100024, 1, 9, 20260302, 'recojo',  12, 8, 1, 'CR', NULL, NULL),
    (100024, 2, 9, 20260302, 'recojo',  17, 8, 1, 'IP', 11, NULL),
    (100025, 1, 4, 20260304, 'despacho', 4, 7, 1, 'CD', NULL, NULL),
    (100026, 1, 5, 20260305, 'despacho',14, 7, 2, 'CD', NULL, NULL),
    (100027, 1, 6, 20260306, 'despacho', 9, 7, 1, 'XI', 11, NULL),
    (100028, 1, 7, 20260309, 'recojo',  14, 7, 1, 'IP', 10, NULL),
    (100029, 1, 8, 20260310, 'recojo',  12, 8, 1, 'CR', NULL, NULL),
    (100030, 1, 9, 20260311, 'recojo',  17, 8, 2, 'CR', NULL, NULL),
    (100031, 1, 4, 20260312, 'despacho',12, 8, 2, 'CD', NULL, NULL),
    (100032, 1, 5, 20260313, 'recojo',   9, 8, 4, 'RJ', NULL, NULL),
    (100033, 1, 6, 20260314, 'despacho',12, 6, 1, 'RJ', NULL, NULL),
    (100034, 1, 7, 20260315, 'despacho',17, 8, 2, 'CD', NULL, NULL),
    (100035, 1, 8, 20260316, 'despacho',14, 7, 1, 'CD', NULL, NULL),
    (100035, 2, 8, 20260316, 'despacho', 9, 7, 1, 'XV', NULL, 1),
    (100036, 1, 9, 20260317, 'despacho',12, 8, 1, 'CI', 10, NULL),
    (100037, 1, 4, 20260318, 'recojo',   7, 6, 2, 'CR', NULL, NULL),
    (100037, 2, 4, 20260318, 'recojo',  16, 6, 1, 'CI', 11, NULL),
    (100038, 1, 5, 20260318, 'recojo',   7, 6, 1, 'VN', NULL, NULL),
    (100039, 1, 6, 20260318, 'recojo',  12, 8, 3, 'VN', NULL, NULL),
    (100040, 1, 7, 20260319, 'despacho',17, 8, 2, 'IR', 10, NULL),
    (100041, 1, 8, 20260320, 'recojo',  12, 8, 1, 'XV', NULL, 2),
    (100042, 1, 9, 20260321, 'despacho',17, 8, 1, 'XV', NULL, 3),
    (100043, 1, 4, 20260323, 'recojo',  15, 7, 3, 'RJ', NULL, NULL),
    (100044, 1, 5, 20260326, 'despacho', 6, 8, 2, 'RJ', NULL, NULL),
    (100045, 1, 6, 20260330, 'recojo',  10, 8, 1, 'RJ', NULL, NULL);

-- Guard de idempotencia: si ya existen los pedidos del Bloque 4, no se
-- vuelve a sembrar (sin DELETE, sin INSERT duplicados).
DECLARE @YaEjecutada BIT =
    CASE WHEN EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle
                      WHERE PedidoID BETWEEN 100001 AND 100045)
         THEN 1 ELSE 0 END;

IF @YaEjecutada = 0
BEGIN
    -- ---- Prevalidaciones: estado base intacto (se detiene antes de tocar) --
    IF NOT EXISTS (SELECT 1 FROM dbo.DimFecha WHERE FechaID = 20260101)
        THROW 51400, N'DimFecha no contiene FechaID 20260101. Ejecutar antes 01_datos_maestros.sql.', 1;

    IF (SELECT COUNT(*) FROM dbo.FactPedidoDetalle) <> 6
        THROW 51401, N'Estado base inesperado: FactPedidoDetalle no tiene las 6 lineas historicas esperadas.', 1;

    IF (SELECT COUNT(*) FROM dbo.FactMovimientoInventario) <> 14
        THROW 51402, N'Estado base inesperado: FactMovimientoInventario no tiene los 14 movimientos esperados.', 1;

    IF (SELECT COUNT(*) FROM dbo.FactIncidencia) <> 1
        THROW 51403, N'Estado base inesperado: FactIncidencia no tiene la 1 incidencia historica esperada.', 1;

    IF (SELECT COUNT(*) FROM dbo.FactDevolucion) <> 0
        THROW 51404, N'Estado base inesperado: FactDevolucion no esta vacia.', 1;

    IF (SELECT COUNT(*) FROM dbo.StockSKUTienda) <> 56
        THROW 51405, N'Estado base inesperado: StockSKUTienda no tiene las 56 filas esperadas.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.StockSKUTienda
                   WHERE SKUID = 4 AND TiendaID = 6 AND StockSistema = 8 AND StockReservado = 0)
        THROW 51406, N'Ancla SKU4 x Tienda6 alterada: se esperaba StockSistema=8 y StockReservado=0.', 1;

    IF (SELECT COUNT(*) FROM dbo.FactMovimientoInventario WHERE SKUID = 4 AND TiendaID = 6) <> 8
        THROW 51407, N'Ancla SKU4 x Tienda6 alterada: se esperaban exactamente 8 movimientos.', 1;

    IF EXISTS (SELECT 1
               FROM @Lineas l
               WHERE NOT EXISTS (SELECT 1 FROM dbo.DimFecha f WHERE f.FechaID = l.FechaID))
        THROW 51408, N'Alguna FechaID del dataset no existe en DimFecha. Verificar 01_datos_maestros.sql.', 1;

    IF EXISTS (SELECT 1
               FROM (VALUES (20260109), (20260117), (20260214), (20260215), (20260218), (20260222)) v(FechaID)
               WHERE NOT EXISTS (SELECT 1 FROM dbo.DimFecha f WHERE f.FechaID = v.FechaID))
        THROW 51408, N'Alguna FechaID de devolucion del dataset no existe en DimFecha.', 1;

    -- Variables de trabajo (lote completo)
    DECLARE @N INT, @PedidoID INT, @ClienteID INT, @SKUID INT, @TiendaID INT,
            @FechaID INT, @Canal VARCHAR(10), @Cantidad INT, @Tipo CHAR(2),
            @MotivoIncID INT, @XVOrigen TINYINT, @LineaID INT,
            @Res VARCHAR(20), @TipoInc VARCHAR(30), @IncidenciaID INT,
            @MovRec1 INT, @MovRec2 INT, @IncRec1 INT, @IncRec2 INT,
            @FechaBase DATE, @FechaIDMas1 INT, @DevolucionID INT,
            @FechaDevolucion DATETIME2(0);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ---- B. Recepciones CD (DML directo documentado) ------------------
        -- Columnas de recepcion: CantidadEsperada / CantidadRecibida /
        -- Discrepancia = E - R (CK_MovInventario_*); Cantidad = Recibida.
        INSERT INTO dbo.FactMovimientoInventario
            (SKUID, TiendaID, FechaID, FechaHora, TipoMovimiento, Origen, Cantidad,
             LineaID, CantidadEsperada, CantidadRecibida, Discrepancia)
        VALUES (5, 6, 20260101, SYSDATETIME(), N'INGRESO', N'RECEPCION_CD', 14, NULL, 14, 14, 0);

        INSERT INTO dbo.FactMovimientoInventario
            (SKUID, TiendaID, FechaID, FechaHora, TipoMovimiento, Origen, Cantidad,
             LineaID, CantidadEsperada, CantidadRecibida, Discrepancia)
        VALUES (7, 6, 20260101, SYSDATETIME(), N'INGRESO', N'RECEPCION_CD', 12, NULL, 12, 12, 0);

        INSERT INTO dbo.FactMovimientoInventario
            (SKUID, TiendaID, FechaID, FechaHora, TipoMovimiento, Origen, Cantidad,
             LineaID, CantidadEsperada, CantidadRecibida, Discrepancia)
        VALUES (16, 6, 20260101, SYSDATETIME(), N'INGRESO', N'RECEPCION_CD', 8, NULL, 8, 8, 0);

        -- Recepcion incompleta #1 (SKU15 x T6, E=5 R=4) -> incidencia rec #1
        INSERT INTO dbo.FactMovimientoInventario
            (SKUID, TiendaID, FechaID, FechaHora, TipoMovimiento, Origen, Cantidad,
             LineaID, CantidadEsperada, CantidadRecibida, Discrepancia)
        VALUES (15, 6, 20260101, SYSDATETIME(), N'INGRESO', N'RECEPCION_CD', 4, NULL, 5, 4, 1);
        SET @MovRec1 = SCOPE_IDENTITY();

        -- Recepcion incompleta #2 (SKU14 x T7, E=9 R=8) -> incidencia rec #2
        INSERT INTO dbo.FactMovimientoInventario
            (SKUID, TiendaID, FechaID, FechaHora, TipoMovimiento, Origen, Cantidad,
             LineaID, CantidadEsperada, CantidadRecibida, Discrepancia)
        VALUES (14, 7, 20260101, SYSDATETIME(), N'INGRESO', N'RECEPCION_CD', 8, NULL, 9, 8, 1);
        SET @MovRec2 = SCOPE_IDENTITY();

        INSERT INTO dbo.FactMovimientoInventario
            (SKUID, TiendaID, FechaID, FechaHora, TipoMovimiento, Origen, Cantidad,
             LineaID, CantidadEsperada, CantidadRecibida, Discrepancia)
        VALUES (12, 8, 20260101, SYSDATETIME(), N'INGRESO', N'RECEPCION_CD', 12, NULL, 12, 12, 0);

        INSERT INTO dbo.FactMovimientoInventario
            (SKUID, TiendaID, FechaID, FechaHora, TipoMovimiento, Origen, Cantidad,
             LineaID, CantidadEsperada, CantidadRecibida, Discrepancia)
        VALUES (17, 8, 20260101, SYSDATETIME(), N'INGRESO', N'RECEPCION_CD', 10, NULL, 10, 10, 0);

        INSERT INTO dbo.FactMovimientoInventario
            (SKUID, TiendaID, FechaID, FechaHora, TipoMovimiento, Origen, Cantidad,
             LineaID, CantidadEsperada, CantidadRecibida, Discrepancia)
        VALUES (4, 7, 20260101, SYSDATETIME(), N'INGRESO', N'RECEPCION_CD', 9, NULL, 9, 9, 0);

        IF @MovRec1 IS NULL OR @MovRec2 IS NULL
            THROW 51409, N'No se capturaron los MovimientoID de las recepciones incompletas.', 1;

        -- ---- C. Ajustes de conteo fisico (DML directo documentado) --------
        -- AJUSTE con Origen CONTEO_FISICO y MotivoID 14; se insertan primero
        -- los positivos; los negativos caen sobre combos con recepcion/base
        -- ya aplicada, por lo que StockSistema nunca baja de 0 (RN-015).
        INSERT INTO dbo.FactMovimientoInventario
            (SKUID, TiendaID, FechaID, FechaHora, TipoMovimiento, Origen, Cantidad, LineaID, MotivoID)
        VALUES
            (6,  6, 20260101, SYSDATETIME(), N'AJUSTE', N'CONTEO_FISICO',  2, NULL, 14),
            (8,  8, 20260101, SYSDATETIME(), N'AJUSTE', N'CONTEO_FISICO',  1, NULL, 14),
            (13, 6, 20260101, SYSDATETIME(), N'AJUSTE', N'CONTEO_FISICO',  3, NULL, 14),
            (4,  7, 20260101, SYSDATETIME(), N'AJUSTE', N'CONTEO_FISICO', -2, NULL, 14),
            (7,  6, 20260101, SYSDATETIME(), N'AJUSTE', N'CONTEO_FISICO', -1, NULL, 14),
            (12, 8, 20260101, SYSDATETIME(), N'AJUSTE', N'CONTEO_FISICO', -1, NULL, 14);

        -- ---- D. Creacion de las 52 lineas (sp_CrearPedido) ----------------
        DECLARE curCrear CURSOR LOCAL FAST_FORWARD FOR
            SELECT N, PedidoID, ClienteID, SKUID, TiendaID, FechaID, Canal, Cantidad, Tipo
            FROM @Lineas
            ORDER BY N;

        OPEN curCrear;
        FETCH NEXT FROM curCrear
            INTO @N, @PedidoID, @ClienteID, @SKUID, @TiendaID, @FechaID, @Canal, @Cantidad, @Tipo;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC dbo.sp_CrearPedido
                @PedidoID = @PedidoID, @ClienteID = @ClienteID, @SKUID = @SKUID,
                @TiendaID = @TiendaID, @FechaID = @FechaID, @Canal = @Canal,
                @Cantidad = @Cantidad, @LineaID = @LineaID OUTPUT, @Resultado = @Res OUTPUT;

            IF @Tipo = 'RJ'
            BEGIN
                -- Rechazo deterministico: combo con disponible 0 (siempre).
                IF @Res <> 'RECHAZADO'
                    THROW 51411, N'sp_CrearPedido devolvio un resultado inesperado para una linea RJ (se esperaba RECHAZADO).', 1;

                IF EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle
                           WHERE LineaID = @LineaID AND TiendaID IS NOT NULL)
                    THROW 51412, N'Una linea RECHAZADO quedo con TiendaID no nulo.', 1;

                IF EXISTS (SELECT 1 FROM dbo.FactMovimientoInventario WHERE LineaID = @LineaID)
                    THROW 51413, N'Una linea RECHAZADO genero movimientos de inventario.', 1;
            END
            ELSE
            BEGIN
                IF @Res <> 'CREADO'
                    THROW 51414, N'sp_CrearPedido devolvio un resultado inesperado (se esperaba CREADO para combo con stock).', 1;

                UPDATE @Lineas SET LineaID = @LineaID WHERE N = @N;
            END

            FETCH NEXT FROM curCrear
                INTO @N, @PedidoID, @ClienteID, @SKUID, @TiendaID, @FechaID, @Canal, @Cantidad, @Tipo;
        END

        CLOSE curCrear;
        DEALLOCATE curCrear;

        IF EXISTS (SELECT 1 FROM @Lineas WHERE Tipo <> 'RJ' AND LineaID IS NULL)
            THROW 51415, N'Alguna linea no rechazada no capturo su LineaID tras la creacion.', 1;

        -- ---- E. Operaciones de flujo (los 14 SPs, por Tipo) ---------------
        DECLARE curFlujo CURSOR LOCAL FAST_FORWARD FOR
            SELECT N FROM @Lineas WHERE Tipo <> 'RJ' ORDER BY N;

        OPEN curFlujo;
        FETCH NEXT FROM curFlujo INTO @N;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SELECT @PedidoID = PedidoID, @LineaID = LineaID, @FechaID = FechaID,
                   @Canal = Canal, @Tipo = Tipo, @MotivoIncID = MotivoIncID,
                   @XVOrigen = XVOrigen, @SKUID = SKUID, @TiendaID = TiendaID,
                   @Cantidad = Cantidad
            FROM @Lineas
            WHERE N = @N;

            IF @Tipo IN ('CR', 'CD', 'CI', 'VN')
            BEGIN
                EXEC dbo.sp_AsignarPicking @LineaID = @LineaID, @FechaID = @FechaID, @Resultado = @Res OUTPUT;
                IF @Res <> 'ASIGNADO'
                    THROW 51417, N'resultado inesperado en sp_AsignarPicking.', 1;

                EXEC dbo.sp_IniciarPicking @LineaID = @LineaID, @FechaID = @FechaID, @Resultado = @Res OUTPUT;
                IF @Res <> 'INICIADO'
                    THROW 51418, N'resultado inesperado en sp_IniciarPicking.', 1;

                IF @Tipo = 'CI'
                BEGIN
                    -- El tipo de incidencia se toma del catalogo (evita
                    -- problemas de codificacion con el literal 'danado').
                    SELECT @TipoInc = NombreMotivo FROM dbo.DimMotivo WHERE MotivoID = @MotivoIncID;
                    IF @TipoInc IS NULL
                        THROW 51416, N'Motivo de incidencia invalido para una linea CI.', 1;

                    EXEC dbo.sp_RegistrarIncidenciaPicking
                        @LineaID = @LineaID, @TipoIncidencia = @TipoInc,
                        @MotivoID = @MotivoIncID, @FechaID = @FechaID,
                        @IncidenciaID = @IncidenciaID OUTPUT;
                    IF @IncidenciaID IS NULL
                        THROW 51419, N'sp_RegistrarIncidenciaPicking no devolvio IncidenciaID.', 1;

                    EXEC dbo.sp_ResolverIncidencia
                        @LineaID = @LineaID, @IncidenciaID = @IncidenciaID,
                        @FechaID = @FechaID, @Resultado = @Res OUTPUT;
                    IF @Res <> 'RESUELTA'
                        THROW 51420, N'resultado inesperado en sp_ResolverIncidencia (linea CI).', 1;
                END

                EXEC dbo.sp_ConfirmarPicking @LineaID = @LineaID, @FechaID = @FechaID, @Resultado = @Res OUTPUT;
                IF @Res <> 'EMPAQUETADO'
                    THROW 51421, N'resultado inesperado en sp_ConfirmarPicking.', 1;

                IF @Canal = 'despacho'
                BEGIN
                    EXEC dbo.sp_PrepararDespacho @LineaID = @LineaID, @FechaID = @FechaID, @Resultado = @Res OUTPUT;
                    IF @Res <> 'EN_TRANSITO'
                        THROW 51422, N'resultado inesperado en sp_PrepararDespacho.', 1;

                    EXEC dbo.sp_RegistrarEntrega @LineaID = @LineaID, @FechaID = @FechaID, @Resultado = @Res OUTPUT;
                    IF @Res <> 'ENTREGADO'
                        THROW 51423, N'resultado inesperado en sp_RegistrarEntrega.', 1;

                    EXEC dbo.sp_CompletarPedido @LineaID = @LineaID, @FechaID = @FechaID, @Resultado = @Res OUTPUT;
                    IF @Res <> 'COMPLETADO'
                        THROW 51424, N'resultado inesperado en sp_CompletarPedido (despacho).', 1;
                END
                ELSE IF @Canal = 'recojo'
                BEGIN
                    EXEC dbo.sp_PrepararRecojo @LineaID = @LineaID, @FechaID = @FechaID, @Resultado = @Res OUTPUT;
                    IF @Res <> 'DISPONIBLE'
                        THROW 51422, N'resultado inesperado en sp_PrepararRecojo.', 1;

                    IF @Tipo = 'VN'
                    BEGIN
                        -- VN se queda en "Disponible para recojo" hasta que
                        -- la sesion 2 venza (sp_ProcesarVencimientosRecojo).
                        IF @Canal <> 'recojo'
                            THROW 51427, N'Una linea VN debe ser de canal recojo.', 1;
                    END
                    ELSE
                    BEGIN
                        EXEC dbo.sp_RegistrarRecojo @LineaID = @LineaID, @FechaID = @FechaID, @Resultado = @Res OUTPUT;
                        IF @Res <> 'RECOGIDO'
                            THROW 51423, N'resultado inesperado en sp_RegistrarRecojo.', 1;

                        EXEC dbo.sp_CompletarPedido @LineaID = @LineaID, @FechaID = @FechaID, @Resultado = @Res OUTPUT;
                        IF @Res <> 'COMPLETADO'
                            THROW 51424, N'resultado inesperado en sp_CompletarPedido (recojo).', 1;
                    END
                END
                ELSE
                    THROW 51427, N'Canal inesperado en una linea CR/CD/CI/VN.', 1;
            END
            ELSE IF @Tipo IN ('XI', 'IP', 'IR')
            BEGIN
                EXEC dbo.sp_AsignarPicking @LineaID = @LineaID, @FechaID = @FechaID, @Resultado = @Res OUTPUT;
                IF @Res <> 'ASIGNADO'
                    THROW 51417, N'resultado inesperado en sp_AsignarPicking.', 1;

                EXEC dbo.sp_IniciarPicking @LineaID = @LineaID, @FechaID = @FechaID, @Resultado = @Res OUTPUT;
                IF @Res <> 'INICIADO'
                    THROW 51418, N'resultado inesperado en sp_IniciarPicking.', 1;

                SELECT @TipoInc = NombreMotivo FROM dbo.DimMotivo WHERE MotivoID = @MotivoIncID;
                IF @TipoInc IS NULL
                    THROW 51416, N'Motivo de incidencia invalido para una linea XI/IP/IR.', 1;

                EXEC dbo.sp_RegistrarIncidenciaPicking
                    @LineaID = @LineaID, @TipoIncidencia = @TipoInc,
                    @MotivoID = @MotivoIncID, @FechaID = @FechaID,
                    @IncidenciaID = @IncidenciaID OUTPUT;
                IF @IncidenciaID IS NULL
                    THROW 51419, N'sp_RegistrarIncidenciaPicking no devolvio IncidenciaID.', 1;
                -- Se detiene aqui: queda en_atencion para la sesion 2
                -- (XI se escala y cancela; IR se escala y resuelve; IP
                --  permanece en_atencion en ambas sesiones).
            END
            ELSE IF @Tipo = 'XV'
            BEGIN
                IF @XVOrigen IS NULL OR @XVOrigen NOT IN (1, 2, 3)
                    THROW 51426, N'XVOrigen invalido para una linea XV.', 1;

                IF @XVOrigen >= 2
                BEGIN
                    EXEC dbo.sp_AsignarPicking @LineaID = @LineaID, @FechaID = @FechaID, @Resultado = @Res OUTPUT;
                    IF @Res <> 'ASIGNADO'
                        THROW 51417, N'resultado inesperado en sp_AsignarPicking (XV).', 1;
                END

                IF @XVOrigen = 3
                BEGIN
                    EXEC dbo.sp_IniciarPicking @LineaID = @LineaID, @FechaID = @FechaID, @Resultado = @Res OUTPUT;
                    IF @Res <> 'INICIADO'
                        THROW 51418, N'resultado inesperado en sp_IniciarPicking (XV).', 1;
                END

                EXEC dbo.sp_CancelarPedido
                    @LineaID = @LineaID, @MotivoID = 7, @FechaID = @FechaID,
                    @IncidenciaID = NULL, @Resultado = @Res OUTPUT;
                IF @Res <> 'CANCELADO'
                    THROW 51425, N'resultado inesperado en sp_CancelarPedido (voluntaria).', 1;
            END
            ELSE
                THROW 51426, N'Tipo de linea desconocido en el dataset.', 1;

            FETCH NEXT FROM curFlujo INTO @N;
        END

        CLOSE curFlujo;
        DEALLOCATE curFlujo;

        -- ---- F. Incidencias de recepcion incompleta (DML documentado) ------
        -- D-J: cada recepcion incompleta genera EXACTAMENTE 1 incidencia.
        INSERT INTO dbo.FactIncidencia
            (TipoIncidencia, LineaID, MovimientoID, MotivoID, AreaAtencionID,
             AreaEscaladaID, FechaID, FechaDeteccion, EstadoResolucion, FechaResolucion)
        VALUES
            (N'recepcion_incompleta', NULL, @MovRec1, 13, 1, NULL,
             20260101, SYSDATETIME(), N'en_atencion', NULL);
        SET @IncRec1 = SCOPE_IDENTITY();

        INSERT INTO dbo.FactIncidencia
            (TipoIncidencia, LineaID, MovimientoID, MotivoID, AreaAtencionID,
             AreaEscaladaID, FechaID, FechaDeteccion, EstadoResolucion, FechaResolucion)
        VALUES
            (N'recepcion_incompleta', NULL, @MovRec2, 13, 1, NULL,
             20260101, SYSDATETIME(), N'en_atencion', NULL);
        SET @IncRec2 = SCOPE_IDENTITY();

        -- Rec #1 se resuelve en la sesion 1; rec #2 queda en_atencion y se
        -- escalara en la sesion 2 (D-I: AreaEscaladaID = 3 Abastecimiento).
        UPDATE dbo.FactIncidencia
        SET EstadoResolucion = N'resuelta', FechaResolucion = SYSDATETIME()
        WHERE IncidenciaID = @IncRec1;

        IF @@ROWCOUNT <> 1
            THROW 51410, N'No se pudo resolver la incidencia de recepcion #1.', 1;

        -- ---- G. Devoluciones (sp_RegistrarDevolucion) ---------------------
        DECLARE @Dev TABLE
        (
            PedidoID INT NOT NULL PRIMARY KEY,
            MotivoID INT NOT NULL,
            FechaID  INT NOT NULL
        );

        INSERT INTO @Dev (PedidoID, MotivoID, FechaID) VALUES
            (100003, 15, 20260109),
            (100006, 15, 20260117),
            (100016, 17, 20260214),
            (100017, 16, 20260215),
            (100019, 16, 20260218),
            (100021, 17, 20260222);

        DECLARE curDev CURSOR LOCAL FAST_FORWARD FOR
            SELECT PedidoID, MotivoID, FechaID FROM @Dev ORDER BY PedidoID;

        OPEN curDev;
        FETCH NEXT FROM curDev INTO @PedidoID, @MotivoIncID, @FechaID;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM dbo.DimFecha WHERE FechaID = @FechaID)
                THROW 51429, N'FechaID de devolucion inexistente en DimFecha.', 1;

            SELECT @LineaID = LineaID
            FROM dbo.FactPedidoDetalle
            WHERE PedidoID = @PedidoID;

            IF @LineaID IS NULL
                THROW 51428, N'El pedido de una devolucion no tiene linea unica esperada.', 1;

            -- @FechaDevolucion = tiempo real de ejecucion (SYSDATETIME);
            -- la ventana RN-027 se evalua contra el tiempo real del
            -- historial, por lo que queda en 0 dias (<= 7). Se asigna a una
            -- variable porque T-SQL no admite funciones como valor de
            -- parametro de un EXEC.
            SET @FechaDevolucion = SYSDATETIME();

            EXEC dbo.sp_RegistrarDevolucion
                @LineaID = @LineaID, @MotivoID = @MotivoIncID, @FechaID = @FechaID,
                @FechaDevolucion = @FechaDevolucion, @DiasVentanaDevolucion = 7,
                @DevolucionID = @DevolucionID OUTPUT;

            IF @DevolucionID IS NULL
                THROW 51428, N'sp_RegistrarDevolucion no devolvio DevolucionID.', 1;

            FETCH NEXT FROM curDev INTO @PedidoID, @MotivoIncID, @FechaID;
        END

        CLOSE curDev;
        DEALLOCATE curDev;

        COMMIT TRANSACTION;
        PRINT N'SESSION 1: operaciones completadas (secciones B-G).';
    END TRY
    BEGIN CATCH
        -- El trigger/SP pueden haber hecho ROLLBACK por su cuenta; solo se
        -- revierte si todavia hay transaccion abierta.
        DECLARE @Err1 NVARCHAR(400) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        PRINT N'SESSION 1: ERROR - transaccion revertida (ROLLBACK). ' + @Err1;
        PRINT N'ESTADO BLOQUE 4: DETENIDO POR INCOMPATIBILIDAD';
        THROW;
    END CATCH
END
ELSE
    PRINT N'SESSION 1: ya ejecutada - se omiten las operaciones (idempotencia).';
GO

-- ===========================================================================
-- SESIÓN 1 — BATCH 1 (continuación) — Sección H: validaciones Q01-Q13, C01-C24
-- Valores esperados de SESION 1 (2 en "Disponible para recojo", ledger 110).
-- ===========================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Guard de omisión (MISMO batch que H: RETURN solo termina el batch actual).
DECLARE @YaEjecutada BIT =
    CASE WHEN EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle
                      WHERE PedidoID BETWEEN 100001 AND 100045)
         THEN 1 ELSE 0 END;

-- Si el Bloque 4 ya avanzo a la sesion 2, las validaciones H (valores de
-- sesion 1) ya no aplican: se omite el reporte para no confundir.
IF @YaEjecutada = 1
   AND NOT EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle
                   WHERE PedidoID BETWEEN 100001 AND 100045 AND EstadoActualID = 6)
BEGIN
    PRINT N'SESSION 1: el Bloque 4 ya paso a la sesion 2; las validaciones H se omiten (usar el batch de la sesion 2).';
    RETURN;
END

DECLARE @V TABLE
(
    Nro        INT           NOT NULL PRIMARY KEY,
    Validacion NVARCHAR(80)  NOT NULL,
    Esperado   NVARCHAR(80)  NOT NULL,
    Obtenido   NVARCHAR(160) NOT NULL,
    Resultado  VARCHAR(5)    NOT NULL
);

DECLARE @n INT, @n1 INT, @n2 INT, @n3 INT, @n4 INT, @n5 INT, @n6 INT,
        @s NVARCHAR(200), @d INT;

-- ---- Q01: ventanas de fecha del pedido (12/11/10/9/3) ---------------------
SELECT @n1 = COUNT(DISTINCT CASE WHEN p.FechaID <  20260201 THEN p.PedidoID END),
       @n2 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260201 AND 20260228 THEN p.PedidoID END),
       @n3 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260301 AND 20260314 THEN p.PedidoID END),
       @n4 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260315 AND 20260321 THEN p.PedidoID END),
       @n5 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260322 AND 20260331 THEN p.PedidoID END)
FROM (SELECT DISTINCT PedidoID, FechaID
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045) p;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (1, N'Q01 Ventanas ene/feb/mar1-14/campana/mar22-31', N'12/11/10/9/3',
        CONCAT(@n1, N'/', @n2, N'/', @n3, N'/', @n4, N'/', @n5),
        CASE WHEN @n1=12 AND @n2=11 AND @n3=10 AND @n4=9 AND @n5=3 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q02: canal (pedidos 27/18, lineas 31/21) -----------------------------
SELECT @n1 = COUNT(DISTINCT CASE WHEN p.Canal = 'recojo'   THEN p.PedidoID END),
       @n2 = COUNT(DISTINCT CASE WHEN p.Canal = 'despacho' THEN p.PedidoID END)
FROM (SELECT DISTINCT PedidoID, Canal
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045) p;

SELECT @n3 = SUM(CASE WHEN Canal = 'recojo'   THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN Canal = 'despacho' THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (2, N'Q02 Canal: pedidos y lineas recojo/despacho', N'27/18 pedidos; 31/21 lineas',
        CONCAT(@n1, N'/', @n2, N' pedidos; ', @n3, N'/', @n4, N' lineas'),
        CASE WHEN @n1=27 AND @n2=18 AND @n3=31 AND @n4=21 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q03: tiendas (NULL=8; T5=0; T6=16; T7=16; T8=12) --------------------
SELECT @n  = SUM(CASE WHEN TiendaID IS NULL THEN 1 ELSE 0 END),
       @n1 = SUM(CASE WHEN TiendaID = 5 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN TiendaID = 6 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN TiendaID = 7 THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN TiendaID = 8 THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (3, N'Q03 Tiendas: T5 sin pedidos; reparto T6/T7/T8; rechazados NULL',
        N'NULL=8; T5=0; T6=16; T7=16; T8=12',
        CONCAT(N'NULL=', @n, N'; T5=', @n1, N'; T6=', @n2, N'; T7=', @n3, N'; T8=', @n4),
        CASE WHEN @n=8 AND @n1=0 AND @n2=16 AND @n3=16 AND @n4=12 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q04: estados de linea (sesion 1: 30/6/8/6/2) ------------------------
SELECT @n1 = SUM(CASE WHEN EstadoActualID = 8 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN EstadoActualID = 5 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN EstadoActualID = 2 THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN EstadoActualID = 3 THEN 1 ELSE 0 END),
       @n5 = SUM(CASE WHEN EstadoActualID = 6 THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (4, N'Q04 Estados de linea (Com/Can/Rech/Inc/Disp)', N'Com=30; Can=6; Rech=8; Inc=6; Disp=2',
        CONCAT(N'Com=', @n1, N'; Can=', @n2, N'; Rech=', @n3, N'; Inc=', @n4, N'; Disp=', @n5),
        CASE WHEN @n1=30 AND @n2=6 AND @n3=8 AND @n4=6 AND @n5=2 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q05: motivos de cancelacion (sesion 1: 6/0/0) -----------------------
SELECT @n1 = SUM(CASE WHEN MotivoCancelacionID = 7 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN MotivoCancelacionID = 8 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN MotivoCancelacionID = 9 THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045 AND EstadoActualID = 5;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (5, N'Q05 Cancelaciones: voluntaria/incidencia/vencimiento', N'vol=6; inc=0; venc=0',
        CONCAT(N'vol=', ISNULL(@n1, 0), N'; inc=', ISNULL(@n2, 0), N'; venc=', ISNULL(@n3, 0)),
        CASE WHEN ISNULL(@n1,0)=6 AND ISNULL(@n2,0)=0 AND ISNULL(@n3,0)=0 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q06: matriz de incidencias por tipo/estado (sesion 1) ---------------
SELECT @s = CONCAT(
    N'ne ',
    (SELECT CONCAT(ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'resuelta'    THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'no_resuelta' THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'en_atencion'  THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'escalada'     THEN 1 ELSE 0 END), 0))
       FROM dbo.FactIncidencia i
       WHERE i.TipoIncidencia = N'no_encontrado'
         AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
                     WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045)),
    N'; ci ',
    (SELECT CONCAT(ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'resuelta'    THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'no_resuelta' THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'en_atencion'  THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'escalada'     THEN 1 ELSE 0 END), 0))
       FROM dbo.FactIncidencia i
       WHERE i.TipoIncidencia = N'cantidad_insuficiente'
         AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
                     WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045)),
    N'; da ',
    (SELECT CONCAT(ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'resuelta'    THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'no_resuelta' THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'en_atencion'  THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'escalada'     THEN 1 ELSE 0 END), 0))
       FROM dbo.FactIncidencia i
       WHERE i.TipoIncidencia = N'dañado'
         AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
                     WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045)),
    N'; rec ',
    (SELECT CONCAT(ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'resuelta'    THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'no_resuelta' THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'en_atencion'  THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'escalada'     THEN 1 ELSE 0 END), 0))
       FROM dbo.FactIncidencia i
       WHERE i.TipoIncidencia = N'recepcion_incompleta'));

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (6, N'Q06 Matriz incidencias tipo x estado (res/nores/atenc/esc)',
        N'ne 1/0/3/0; ci 1/0/2/0; da 1/0/1/0; rec 1/0/1/0', @s,
        CASE WHEN @s = N'ne 1/0/3/0; ci 1/0/2/0; da 1/0/1/0; rec 1/0/1/0'
             THEN 'OK' ELSE 'FALLA' END);

-- ---- Q07: escalamientos (sesion 1: ninguno) ------------------------------
SELECT @n1 = SUM(CASE WHEN AreaEscaladaID = 2 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN AreaEscaladaID = 3 THEN 1 ELSE 0 END)
FROM dbo.FactIncidencia;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (7, N'Q07 Escalamientos persistidos (area2 picking / area3 recepcion)',
        N'area2=0; area3=0',
        CONCAT(N'area2=', ISNULL(@n1, 0), N'; area3=', ISNULL(@n2, 0)),
        CASE WHEN ISNULL(@n1, 0) = 0 AND ISNULL(@n2, 0) = 0 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q08: devoluciones (6 con motivos 2/2/2 y max 5 dias) ----------------
SELECT @n  = COUNT(*),
       @n1 = SUM(CASE WHEN dv.MotivoID = 15 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN dv.MotivoID = 16 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN dv.MotivoID = 17 THEN 1 ELSE 0 END),
       @d  = MAX(DATEDIFF(DAY, f1.Fecha, f2.Fecha))
FROM dbo.FactDevolucion dv
INNER JOIN dbo.FactPedidoDetalle d ON d.LineaID = dv.LineaID
INNER JOIN dbo.DimFecha f1 ON f1.FechaID = d.FechaID
INNER JOIN dbo.DimFecha f2 ON f2.FechaID = dv.FechaID
WHERE d.PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (8, N'Q08 Devoluciones: total, motivos 15/16/17 y ventana',
        N'total=6; m15=2; m16=2; m17=2; max_dias=5',
        CONCAT(N'total=', ISNULL(@n, 0), N'; m15=', ISNULL(@n1, 0), N'; m16=', ISNULL(@n2, 0),
               N'; m17=', ISNULL(@n3, 0), N'; max_dias=', ISNULL(@d, -1)),
        CASE WHEN ISNULL(@n,0)=6 AND ISNULL(@n1,0)=2 AND ISNULL(@n2,0)=2
                  AND ISNULL(@n3,0)=2 AND ISNULL(@d,-1)=5 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q09: clientes (6 con 7 u 8 pedidos) ---------------------------------
SELECT @n = COUNT(*), @n1 = MIN(c), @n2 = MAX(c)
FROM (SELECT x.ClienteID, COUNT(*) AS c
      FROM (SELECT DISTINCT PedidoID, ClienteID
            FROM dbo.FactPedidoDetalle
            WHERE PedidoID BETWEEN 100001 AND 100045) x
      GROUP BY x.ClienteID) y;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (9, N'Q09 Clientes: cobertura y reparto', N'clientes=6; min=7; max=8',
        CONCAT(N'clientes=', ISNULL(@n, 0), N'; min=', ISNULL(@n1, 0), N'; max=', ISNULL(@n2, 0)),
        CASE WHEN ISNULL(@n,0)=6 AND ISNULL(@n1,0)=7 AND ISNULL(@n2,0)=8 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q10: campana 15-21 marzo con incidencia y cancelacion ---------------
SELECT @n1 = COUNT(DISTINCT PedidoID)
FROM (SELECT DISTINCT PedidoID, FechaID
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045
        AND FechaID BETWEEN 20260315 AND 20260321) p;

SELECT @n2 = COUNT(*)
FROM dbo.FactIncidencia i
WHERE i.TipoIncidencia <> N'recepcion_incompleta'
  AND i.FechaID BETWEEN 20260315 AND 20260321
  AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
              WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045);

SELECT @n3 = COUNT(*)
FROM dbo.FactHistorialEstadoLinea h
INNER JOIN dbo.FactPedidoDetalle d ON d.LineaID = h.LineaID
WHERE d.PedidoID BETWEEN 100001 AND 100045
  AND h.EstadoID = 5
  AND h.FechaID BETWEEN 20260315 AND 20260321;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (10, N'Q10 Campana: pedidos, incidencias y cancelaciones en 15-21 marzo',
        N'pedidos=9; incidencias>=1; cancelaciones>=1',
        CONCAT(N'pedidos=', @n1, N'; incidencias=', @n2, N'; cancelaciones=', @n3),
        CASE WHEN @n1 = 9 AND @n2 >= 1 AND @n3 >= 1 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q11: stock global sin negativos y disponible > 0 --------------------
SELECT @n1 = COUNT(*)
FROM dbo.StockSKUTienda
WHERE StockSistema < 0 OR StockReservado < 0 OR StockReservado > StockSistema;

SELECT @n2 = SUM(StockSistema - StockReservado) FROM dbo.StockSKUTienda;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (11, N'Q11 Stock global: invariantes y disponibilidad', N'negativos=0; disponible>0',
        CONCAT(N'negativos=', @n1, N'; disponible=', ISNULL(@n2, -9999)),
        CASE WHEN @n1 = 0 AND ISNULL(@n2, -1) > 0 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q12: SKUs con movimiento (>= 12) ------------------------------------
SELECT @n = COUNT(DISTINCT SKUID) FROM dbo.FactMovimientoInventario;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (12, N'Q12 SKUs distintos con movimiento en el ledger', N'>=12',
        CONCAT(N'skus_con_movimiento=', @n),
        CASE WHEN @n >= 12 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q13: vencimientos (sesion 1: 2 pendientes, 0 procesados) ------------
SELECT @n1 = COUNT(*)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045 AND EstadoActualID = 6;

SELECT @n2 = COUNT(*)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045 AND EstadoActualID = 5 AND MotivoCancelacionID = 9;

SELECT @n3 = COUNT(*)
FROM dbo.FactMovimientoInventario
WHERE TipoMovimiento = N'AJUSTE' AND MotivoID = 31 AND FechaID >= 20260315;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (13, N'Q13 Vencimientos: pendientes/procesados/retornos', N'pendientes=2; procesados=0; retornos=0',
        CONCAT(N'pendientes=', @n1, N'; procesados=', @n2, N'; retornos=', @n3),
        CASE WHEN @n1 = 2 AND @n2 = 0 AND @n3 = 0 THEN 'OK' ELSE 'FALLA' END);

-- ---- C01: 45 pedidos -----------------------------------------------------
SELECT @n = COUNT(DISTINCT PedidoID)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (14, N'C01 Pedidos distintos del Bloque 4', N'45', CAST(@n AS NVARCHAR(60)),
        CASE WHEN @n = 45 THEN 'OK' ELSE 'FALLA' END);

-- ---- C02: 52 lineas; 38 pedidos de 1 linea y 7 de 2 ----------------------
SELECT @n = SUM(c),
       @n1 = SUM(CASE WHEN c = 1 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN c = 2 THEN 1 ELSE 0 END)
FROM (SELECT PedidoID, COUNT(*) AS c
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045
      GROUP BY PedidoID) p;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (15, N'C02 Lineas y pedidos de 1 y 2 lineas', N'lineas=52; 1 linea=38; 2 lineas=7',
        CONCAT(N'lineas=', ISNULL(@n, 0), N'; 1 linea=', @n1, N'; 2 lineas=', @n2),
        CASE WHEN @n = 52 AND @n1 = 38 AND @n2 = 7 THEN 'OK' ELSE 'FALLA' END);

-- ---- C03: estados finales (sesion 1) -------------------------------------
SELECT @n1 = SUM(CASE WHEN EstadoActualID = 8 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN EstadoActualID = 5 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN EstadoActualID = 2 THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN EstadoActualID = 3 THEN 1 ELSE 0 END),
       @n5 = SUM(CASE WHEN EstadoActualID = 6 THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (16, N'C03 Estados (Com/Can/Rech/Inc/Disp) y total', N'30/6/8/6/2; total=52',
        CONCAT(@n1, N'/', @n2, N'/', @n3, N'/', @n4, N'/', @n5, N'; total=',
               ISNULL(@n1,0)+ISNULL(@n2,0)+ISNULL(@n3,0)+ISNULL(@n4,0)+ISNULL(@n5,0)),
        CASE WHEN @n1=30 AND @n2=6 AND @n3=8 AND @n4=6 AND @n5=2 THEN 'OK' ELSE 'FALLA' END);

-- ---- C04: motivos de cancelacion (sesion 1) ------------------------------
SELECT @n1 = SUM(CASE WHEN MotivoCancelacionID = 7 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN MotivoCancelacionID = 8 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN MotivoCancelacionID = 9 THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045 AND EstadoActualID = 5;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (17, N'C04 Motivos de cancelacion vol/inc/venc', N'6/0/0',
        CONCAT(ISNULL(@n1, 0), N'/', ISNULL(@n2, 0), N'/', ISNULL(@n3, 0)),
        CASE WHEN ISNULL(@n1,0)=6 AND ISNULL(@n2,0)=0 AND ISNULL(@n3,0)=0 THEN 'OK' ELSE 'FALLA' END);

-- ---- C05: canal por pedido ------------------------------------------------
SELECT @n1 = COUNT(DISTINCT CASE WHEN p.Canal = 'recojo'   THEN p.PedidoID END),
       @n2 = COUNT(DISTINCT CASE WHEN p.Canal = 'despacho' THEN p.PedidoID END)
FROM (SELECT DISTINCT PedidoID, Canal
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045) p;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (18, N'C05 Canal por pedido recojo/despacho', N'27/18',
        CONCAT(@n1, N'/', @n2),
        CASE WHEN @n1 = 27 AND @n2 = 18 THEN 'OK' ELSE 'FALLA' END);

-- ---- C06: tiendas + T5 sin pedidos ---------------------------------------
SELECT @n  = SUM(CASE WHEN TiendaID IS NULL THEN 1 ELSE 0 END),
       @n1 = SUM(CASE WHEN TiendaID = 5 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN TiendaID = 6 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN TiendaID = 7 THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN TiendaID = 8 THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (19, N'C06 Tiendas: Web Nacional sin pedidos; reparto T6/T7/T8',
        N'T5=0; T6=16; T7=16; T8=12; NULL=8',
        CONCAT(N'T5=', @n1, N'; T6=', @n2, N'; T7=', @n3, N'; T8=', @n4, N'; NULL=', @n),
        CASE WHEN @n=8 AND @n1=0 AND @n2=16 AND @n3=16 AND @n4=12 THEN 'OK' ELSE 'FALLA' END);

-- ---- C07: clientes --------------------------------------------------------
SELECT @n = COUNT(*), @n1 = MIN(c), @n2 = MAX(c)
FROM (SELECT x.ClienteID, COUNT(*) AS c
      FROM (SELECT DISTINCT PedidoID, ClienteID
            FROM dbo.FactPedidoDetalle
            WHERE PedidoID BETWEEN 100001 AND 100045) x
      GROUP BY x.ClienteID) y;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (20, N'C07 Clientes: 6 con 7-8 pedidos', N'6/7/8',
        CONCAT(ISNULL(@n, 0), N'/', ISNULL(@n1, 0), N'/', ISNULL(@n2, 0)),
        CASE WHEN ISNULL(@n,0)=6 AND ISNULL(@n1,0)=7 AND ISNULL(@n2,0)=8 THEN 'OK' ELSE 'FALLA' END);

-- ---- C08: distribucion de cantidades -------------------------------------
SELECT @n1 = SUM(CASE WHEN Cantidad = 1 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN Cantidad = 2 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN Cantidad = 3 THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN Cantidad = 4 THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (21, N'C08 Cantidades 1/2/3/4 por linea', N'1=29; 2=14; 3=6; 4=3',
        CONCAT(N'1=', @n1, N'; 2=', @n2, N'; 3=', @n3, N'; 4=', @n4),
        CASE WHEN @n1=29 AND @n2=14 AND @n3=6 AND @n4=3 THEN 'OK' ELSE 'FALLA' END);

-- ---- C09: ventanas + >= 25 FechaID distintos ------------------------------
SELECT @n1 = COUNT(DISTINCT CASE WHEN p.FechaID <  20260201 THEN p.PedidoID END),
       @n2 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260201 AND 20260228 THEN p.PedidoID END),
       @n3 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260301 AND 20260314 THEN p.PedidoID END),
       @n4 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260315 AND 20260321 THEN p.PedidoID END),
       @n5 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260322 AND 20260331 THEN p.PedidoID END)
FROM (SELECT DISTINCT PedidoID, FechaID
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045) p;

SELECT @n = COUNT(DISTINCT FechaID)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (22, N'C09 Ventanas exactas y diversidad de fechas (>=25)', N'12/11/10/9/3; distintas>=25',
        CONCAT(@n1, N'/', @n2, N'/', @n3, N'/', @n4, N'/', @n5, N'; distintas=', @n),
        CASE WHEN @n1=12 AND @n2=11 AND @n3=10 AND @n4=9 AND @n5=3 AND @n >= 25
             THEN 'OK' ELSE 'FALLA' END);

-- ---- C10: campana con incidencia y cancelacion ---------------------------
SELECT @n1 = COUNT(DISTINCT PedidoID)
FROM (SELECT DISTINCT PedidoID, FechaID
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045
        AND FechaID BETWEEN 20260315 AND 20260321) p;

SELECT @n2 = COUNT(*)
FROM dbo.FactIncidencia i
WHERE i.TipoIncidencia <> N'recepcion_incompleta'
  AND i.FechaID BETWEEN 20260315 AND 20260321
  AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
              WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045);

SELECT @n3 = COUNT(*)
FROM dbo.FactHistorialEstadoLinea h
INNER JOIN dbo.FactPedidoDetalle d ON d.LineaID = h.LineaID
WHERE d.PedidoID BETWEEN 100001 AND 100045
  AND h.EstadoID = 5
  AND h.FechaID BETWEEN 20260315 AND 20260321;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (23, N'C10 Campana Cyber Origen: pedidos/incidencias/cancelaciones',
        N'pedidos=9; incid>=1; cancel>=1',
        CONCAT(N'pedidos=', @n1, N'; incid=', @n2, N'; cancel=', @n3),
        CASE WHEN @n1 = 9 AND @n2 >= 1 AND @n3 >= 1 THEN 'OK' ELSE 'FALLA' END);

-- ---- C11: >= 12 SKUs y 4 categorias --------------------------------------
SELECT @n = COUNT(DISTINCT d.SKUID)
FROM dbo.FactPedidoDetalle d
WHERE d.PedidoID BETWEEN 100001 AND 100045;

SELECT @n1 = COUNT(DISTINCT p.Categoria)
FROM (SELECT DISTINCT SKUID
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045) d
INNER JOIN dbo.DimSKU s ON s.SKUID = d.SKUID
INNER JOIN dbo.DimProducto p ON p.ProductoID = s.ProductoID;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (24, N'C11 SKUs distintos (>=12) y categorias (4)', N'skus>=12; cats=4',
        CONCAT(N'skus=', @n, N'; cats=', @n1),
        CASE WHEN @n >= 12 AND @n1 = 4 THEN 'OK' ELSE 'FALLA' END);

-- ---- C12: 14 SKUs con movimiento -----------------------------------------
SELECT @n = COUNT(DISTINCT SKUID) FROM dbo.FactMovimientoInventario;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (25, N'C12 SKUs distintos con movimiento', N'14', CAST(@n AS NVARCHAR(60)),
        CASE WHEN @n = 14 THEN 'OK' ELSE 'FALLA' END);

-- ---- C13: stock sin negativos, ledger=resumen, cobertura 56 --------------
SELECT @n1 = COUNT(*)
FROM dbo.StockSKUTienda
WHERE StockSistema < 0 OR StockReservado < 0 OR StockReservado > StockSistema;

;WITH L AS (
    SELECT SKUID, TiendaID,
           SUM(CASE WHEN TipoMovimiento IN (N'INGRESO', N'AJUSTE', N'DESCUENTO_DEFINITIVO')
                    THEN Cantidad ELSE 0 END) AS Sis,
           SUM(CASE WHEN TipoMovimiento IN (N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO')
                    THEN Cantidad ELSE 0 END) AS Res
    FROM dbo.FactMovimientoInventario
    GROUP BY SKUID, TiendaID
)
SELECT @n2 = COUNT(*)
FROM dbo.StockSKUTienda s
LEFT JOIN L ON L.SKUID = s.SKUID AND L.TiendaID = s.TiendaID
WHERE s.StockSistema <> ISNULL(L.Sis, 0)
   OR s.StockReservado <> ISNULL(L.Res, 0);

SELECT @n3 = COUNT(*) FROM dbo.StockSKUTienda;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (26, N'C13 Stock: sin negativos, ledger=resumen, cobertura', N'neg=0; disc=0; filas=56',
        CONCAT(N'neg=', @n1, N'; disc=', @n2, N'; filas=', @n3),
        CASE WHEN @n1 = 0 AND @n2 = 0 AND @n3 = 56 THEN 'OK' ELSE 'FALLA' END);

-- ---- C14: grilla vw_StockHistorico sin negativos -------------------------
SELECT @n = COUNT(*)
FROM dbo.vw_StockHistorico
WHERE StockSistema < 0 OR StockReservado < 0 OR StockDisponible < 0;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (27, N'C14 Grilla historica: ceros/negativos por FechaID', N'0',
        CAST(@n AS NVARCHAR(60)),
        CASE WHEN @n = 0 THEN 'OK' ELSE 'FALLA' END);

-- ---- C15: recepciones 8 = 6 exactas + 2 incompletas ----------------------
SELECT @n  = COUNT(*),
       @n1 = SUM(CASE WHEN Discrepancia = 0 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN Discrepancia > 0 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN FechaID = 20260101 THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN Cantidad = CantidadRecibida AND Cantidad > 0 THEN 1 ELSE 0 END)
FROM dbo.FactMovimientoInventario
WHERE Origen = N'RECEPCION_CD';

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (28, N'C15 Recepciones CD: 8 = 6 exactas + 2 incompletas (20260101)',
        N'total=8; exactas=6; incompletas=2; fecha=20260101',
        CONCAT(N'total=', ISNULL(@n,0), N'; exactas=', ISNULL(@n1,0),
               N'; incompletas=', ISNULL(@n2,0), N'; fecha_ok=', ISNULL(@n3,0),
               N'; cant=recibida=', ISNULL(@n4,0)),
        CASE WHEN @n=8 AND @n1=6 AND @n2=2 AND @n3=8 AND @n4=8 THEN 'OK' ELSE 'FALLA' END);

-- ---- C16: incidencias de recepcion (sesion 1: 1 resuelta + 1 en_atencion) --
SELECT @n  = COUNT(*),
       @n1 = SUM(CASE WHEN EstadoResolucion = N'resuelta'   THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN EstadoResolucion = N'no_resuelta' THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN EstadoResolucion = N'en_atencion' THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN EstadoResolucion = N'escalada'    THEN 1 ELSE 0 END),
       @n5 = SUM(CASE WHEN EstadoResolucion = N'escalada' AND AreaEscaladaID = 3 THEN 1 ELSE 0 END)
FROM dbo.FactIncidencia
WHERE TipoIncidencia = N'recepcion_incompleta';

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (29, N'C16 Recepcion incompleta: 1 resuelta + 1 en_atencion (D-J)',
        N'total=2; res=1; nores=0; atenc=1; esc=0',
        CONCAT(N'total=', @n, N'; res=', ISNULL(@n1,0), N'; nores=', ISNULL(@n2,0),
               N'; atenc=', ISNULL(@n3,0), N'; esc=', ISNULL(@n4,0),
               N'; esc_area3=', ISNULL(@n5,0)),
        CASE WHEN @n=2 AND ISNULL(@n1,0)=1 AND ISNULL(@n2,0)=0
                  AND ISNULL(@n3,0)=1 AND ISNULL(@n4,0)=0 THEN 'OK' ELSE 'FALLA' END);

-- ---- C17: tipos de incidencia de picking 4/3/2 ---------------------------
SELECT @n  = COUNT(*),
       @n1 = SUM(CASE WHEN i.TipoIncidencia = N'no_encontrado'       THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN i.TipoIncidencia = N'cantidad_insuficiente' THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN i.TipoIncidencia = N'dañado'              THEN 1 ELSE 0 END)
FROM dbo.FactIncidencia i
WHERE i.TipoIncidencia <> N'recepcion_incompleta'
  AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
              WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045);

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (30, N'C17 Incidencias de picking: no_encontrado/cantidad_insuficiente/danado',
        N'total=9; ne=4; ci=3; da=2',
        CONCAT(N'total=', ISNULL(@n,0), N'; ne=', ISNULL(@n1,0),
               N'; ci=', ISNULL(@n2,0), N'; da=', ISNULL(@n3,0)),
        CASE WHEN ISNULL(@n,0)=9 AND ISNULL(@n1,0)=4 AND ISNULL(@n2,0)=3
                  AND ISNULL(@n3,0)=2 THEN 'OK' ELSE 'FALLA' END);

-- ---- C18: estados de incidencia (sesion 1: 4/0/7/0) ----------------------
SELECT @n1 = SUM(CASE WHEN i.EstadoResolucion = N'resuelta'    THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN i.EstadoResolucion = N'no_resuelta' THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN i.EstadoResolucion = N'en_atencion' THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN i.EstadoResolucion = N'escalada'    THEN 1 ELSE 0 END)
FROM dbo.FactIncidencia i
WHERE (i.TipoIncidencia <> N'recepcion_incompleta'
       AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
                   WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045))
   OR i.TipoIncidencia = N'recepcion_incompleta';

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (31, N'C18 Estados de incidencia (res/nores/atenc/esc) y total', N'4/0/7/0; total=11',
        CONCAT(ISNULL(@n1,0), N'/', ISNULL(@n2,0), N'/', ISNULL(@n3,0), N'/', ISNULL(@n4,0),
               N'; total=', ISNULL(@n1,0)+ISNULL(@n2,0)+ISNULL(@n3,0)+ISNULL(@n4,0)),
        CASE WHEN ISNULL(@n1,0)=4 AND ISNULL(@n2,0)=0 AND ISNULL(@n3,0)=7
                  AND ISNULL(@n4,0)=0
                  AND ISNULL(@n1,0)+ISNULL(@n2,0)+ISNULL(@n3,0)+ISNULL(@n4,0)=11
             THEN 'OK' ELSE 'FALLA' END);

-- ---- C19: matriz §25 (reutiliza @s de Q06) -------------------------------
INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (32, N'C19 Matriz §25 tipo x estado (11 incidencias)', 
        N'ne 1/0/3/0; ci 1/0/2/0; da 1/0/1/0; rec 1/0/1/0', @s,
        CASE WHEN @s = N'ne 1/0/3/0; ci 1/0/2/0; da 1/0/1/0; rec 1/0/1/0'
             THEN 'OK' ELSE 'FALLA' END);

-- ---- C20: escalamientos con area correcta (sesion 1: ninguno) ------------
SELECT @n1 = SUM(CASE WHEN AreaEscaladaID = 2 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN AreaEscaladaID = 3 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN EstadoResolucion = N'en_atencion' AND AreaEscaladaID IS NOT NULL
                      THEN 1 ELSE 0 END)
FROM dbo.FactIncidencia;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (33, N'C20 Escaladas con area (picking=2, recepcion=3) y en_atencion sin area',
        N'area2=0; area3=0; en_atencion_con_area=0',
        CONCAT(N'area2=', ISNULL(@n1,0), N'; area3=', ISNULL(@n2,0),
               N'; en_atencion_con_area=', ISNULL(@n3,0)),
        CASE WHEN ISNULL(@n1,0)=0 AND ISNULL(@n2,0)=0 AND ISNULL(@n3,0)=0
             THEN 'OK' ELSE 'FALLA' END);

-- ---- C21: 11 incidencias totales -----------------------------------------
SELECT @n1 = COUNT(*)
FROM dbo.FactIncidencia i
WHERE i.TipoIncidencia <> N'recepcion_incompleta'
  AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
              WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045);

SELECT @n2 = COUNT(*)
FROM dbo.FactIncidencia
WHERE TipoIncidencia = N'recepcion_incompleta';

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (34, N'C21 Incidencias totales: picking + recepcion (D-J)', N'picking=9; rec=2; total=11',
        CONCAT(N'picking=', @n1, N'; rec=', @n2, N'; total=', @n1 + @n2),
        CASE WHEN @n1 = 9 AND @n2 = 2 AND (@n1 + @n2) = 11 THEN 'OK' ELSE 'FALLA' END);

-- ---- C22: devoluciones completas -----------------------------------------
SELECT @n  = COUNT(*),
       @n1 = SUM(CASE WHEN dv.MotivoID = 15 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN dv.MotivoID = 16 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN dv.MotivoID = 17 THEN 1 ELSE 0 END),
       @n4 = MAX(DATEDIFF(DAY, f1.Fecha, f2.Fecha))
FROM dbo.FactDevolucion dv
INNER JOIN dbo.FactPedidoDetalle d ON d.LineaID = dv.LineaID
INNER JOIN dbo.DimFecha f1 ON f1.FechaID = d.FechaID
INNER JOIN dbo.DimFecha f2 ON f2.FechaID = dv.FechaID
WHERE d.PedidoID BETWEEN 100001 AND 100045;

SELECT @n5 = COUNT(*)
FROM (SELECT LineaID FROM dbo.FactDevolucion GROUP BY LineaID HAVING COUNT(*) > 1) x;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (35, N'C22 Devoluciones: 6, motivos 2/2/2, ventana <=7, una por linea',
        N'total=6; m15=2; m16=2; m17=2; max_dias<=7; repetidas=0',
        CONCAT(N'total=', ISNULL(@n,0), N'; m15=', ISNULL(@n1,0), N'; m16=', ISNULL(@n2,0),
               N'; m17=', ISNULL(@n3,0), N'; max_dias=', ISNULL(@n4,0),
               N'; repetidas=', @n5),
        CASE WHEN ISNULL(@n,0)=6 AND ISNULL(@n1,0)=2 AND ISNULL(@n2,0)=2
                  AND ISNULL(@n3,0)=2 AND ISNULL(@n4,0) <= 7 AND @n5 = 0
             THEN 'OK' ELSE 'FALLA' END);

-- ---- C23: ancla SKU4 x Tienda6 intacta -----------------------------------
SELECT @n1 = StockSistema, @n2 = StockReservado
FROM dbo.StockSKUTienda
WHERE SKUID = 4 AND TiendaID = 6;

SELECT @n3 = COUNT(*) FROM dbo.FactMovimientoInventario WHERE SKUID = 4 AND TiendaID = 6;

SELECT @n4 = StockSistema, @n5 = StockReservado, @n6 = StockDisponible
FROM dbo.vw_StockHistorico
WHERE SKUID = 4 AND TiendaID = 6
  AND FechaID = (SELECT MAX(FechaID) FROM dbo.DimFecha);

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (36, N'C23 Ancla SKU4 x Tienda6: stock 8/0, vw 8/0/8, 8 movimientos',
        N'stock=8/0; vw=8/0/8; movs=8',
        CONCAT(N'stock=', @n1, N'/', @n2, N'; vw=', @n4, N'/', @n5, N'/', @n6,
               N'; movs=', @n3),
        CASE WHEN @n1=8 AND @n2=0 AND @n4=8 AND @n5=0 AND @n6=8 AND @n3=8
             THEN 'OK' ELSE 'FALLA' END);

-- ---- C24: coherencia linea-movimientos y ledger de sesion 1 ---------------
;WITH L AS (
    SELECT d.LineaID, d.Cantidad, d.EstadoActualID, d.MotivoCancelacionID,
           ISNULL(SUM(CASE WHEN m.TipoMovimiento = N'RESERVA'              THEN m.Cantidad END), 0) AS Res,
           ISNULL(SUM(CASE WHEN m.TipoMovimiento = N'LIBERACION_RESERVA'   THEN m.Cantidad END), 0) AS Lib,
           ISNULL(SUM(CASE WHEN m.TipoMovimiento = N'DESCUENTO_DEFINITIVO' THEN m.Cantidad END), 0) AS Dsc,
           COUNT(m.MovimientoID) AS NMov
    FROM dbo.FactPedidoDetalle d
    LEFT JOIN dbo.FactMovimientoInventario m ON m.LineaID = d.LineaID
    WHERE d.PedidoID BETWEEN 100001 AND 100045
    GROUP BY d.LineaID, d.Cantidad, d.EstadoActualID, d.MotivoCancelacionID
)
SELECT @n = COUNT(*)
FROM L
WHERE NOT (
        (EstadoActualID = 2 AND NMov = 0)                                                   -- Rechazado
     OR (EstadoActualID = 8 AND Res = Cantidad AND Dsc = -Cantidad AND Lib = 0)             -- Completado
     OR (EstadoActualID = 5 AND MotivoCancelacionID = 7 AND Res = Cantidad AND Lib = -Cantidad AND Dsc = 0)
     OR (EstadoActualID = 5 AND MotivoCancelacionID = 8 AND Res = Cantidad AND Lib = -Cantidad AND Dsc = 0)
     OR (EstadoActualID = 5 AND MotivoCancelacionID = 9 AND Res = Cantidad AND Dsc = -Cantidad AND Lib = 0)
     OR (EstadoActualID = 3 AND Res = Cantidad AND Dsc = 0 AND Lib = 0)                     -- Incidencia
     OR (EstadoActualID = 6 AND Res = Cantidad AND Dsc = -Cantidad AND Lib = 0));            -- Disponible

SELECT @n1 = COUNT(*) FROM dbo.FactMovimientoInventario;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (37, N'C24 Patron linea-movimientos y total del ledger (sesion 1)',
        N'desalineadas=0; ledger=110',
        CONCAT(N'desalineadas=', @n, N'; ledger=', @n1),
        CASE WHEN @n = 0 AND @n1 = 110 THEN 'OK' ELSE 'FALLA' END);

-- ---- Resultado H ----------------------------------------------------------
SELECT Nro, Validacion, Esperado, Obtenido, Resultado
FROM @V
ORDER BY Nro;

SELECT CASE WHEN EXISTS (SELECT 1 FROM @V WHERE Resultado <> 'OK')
            THEN N'HAY VALIDACIONES EN FALLA - reportar la tabla completa antes de continuar (sesion 2 bloqueada).'
            ELSE N'37/37 validaciones OK (Q01-Q13: 13/13; C01-C24: 24/24).'
       END AS ResumenBloque4;

-- Detalle informativo: estados de linea.
SELECT e.NombreEstado AS EstadoLinea, COUNT(*) AS Lineas
FROM dbo.FactPedidoDetalle d
INNER JOIN dbo.DimEstado e ON e.EstadoID = d.EstadoActualID
WHERE d.PedidoID BETWEEN 100001 AND 100045
GROUP BY e.NombreEstado
ORDER BY e.NombreEstado;

-- Detalle informativo: matriz de incidencias.
SELECT i.TipoIncidencia, i.EstadoResolucion, COUNT(*) AS N,
       MAX(ISNULL(ae.NombreArea, N'-')) AS AreaEscalada
FROM dbo.FactIncidencia i
LEFT JOIN dbo.DimArea ae ON ae.AreaID = i.AreaEscaladaID
WHERE (i.TipoIncidencia <> N'recepcion_incompleta'
       AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
                   WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045))
   OR i.TipoIncidencia = N'recepcion_incompleta'
GROUP BY i.TipoIncidencia, i.EstadoResolucion
ORDER BY i.TipoIncidencia, i.EstadoResolucion;

-- ---- §41: reporte de estado ----------------------------------------------
IF EXISTS (SELECT 1 FROM @V WHERE Resultado <> 'OK')
    PRINT N'ESTADO BLOQUE 4: DETENIDO POR INCOMPATIBILIDAD';
ELSE
    PRINT N'ESTADO BLOQUE 4: IMPLEMENTADO — PENDIENTE SESIÓN 2';
GO
-- ===========================================================================
-- SESIÓN 2 — BATCH 2 — Gates + Secciones I..J
-- Ejecutar en un día natural posterior a la sesión 1 (gate temporal real).
-- ===========================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;

-- ---- Gate 0: ¿se ejecutó la sesión 1? -------------------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle
               WHERE PedidoID BETWEEN 100001 AND 100045)
    THROW 51470, N'La sesion 1 no se ha ejecutado: no existen pedidos 100001-100045. Ejecutar primero la sesion 1.', 1;

-- ---- Gate 2: ¿la sesión 2 ya se ejecutó? ----------------------------------
-- Marcador: la sesión 1 deja exactamente 2 líneas en "Disponible para
-- recojo"; la sesión 2 las vence y cancela (las elimina del estado 6).
DECLARE @S2Hecha BIT =
    CASE WHEN EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle
                      WHERE PedidoID BETWEEN 100001 AND 100045 AND EstadoActualID = 6)
         THEN 0 ELSE 1 END;

IF @S2Hecha = 0
BEGIN
    -- ---- Gate 1: la sesión 1 quedó completa y consistente -----------------
    DECLARE @gLineas INT, @gLedger INT, @gDev INT, @gPick INT, @gRec INT,
            @gEstados NVARCHAR(40);

    SELECT @gLineas = COUNT(*)
    FROM dbo.FactPedidoDetalle
    WHERE PedidoID BETWEEN 100001 AND 100045;

    SELECT @gLedger = COUNT(*) FROM dbo.FactMovimientoInventario;

    SELECT @gDev = COUNT(*)
    FROM dbo.FactDevolucion dv
    INNER JOIN dbo.FactPedidoDetalle d ON d.LineaID = dv.LineaID
    WHERE d.PedidoID BETWEEN 100001 AND 100045;

    SELECT @gPick = COUNT(*)
    FROM dbo.FactIncidencia i
    WHERE i.TipoIncidencia <> N'recepcion_incompleta'
      AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
                  WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045);

    SELECT @gRec = COUNT(*)
    FROM dbo.FactIncidencia
    WHERE TipoIncidencia = N'recepcion_incompleta';

    SELECT @gEstados = CONCAT(
        SUM(CASE WHEN EstadoActualID = 8 THEN 1 ELSE 0 END), N'/',
        SUM(CASE WHEN EstadoActualID = 5 THEN 1 ELSE 0 END), N'/',
        SUM(CASE WHEN EstadoActualID = 2 THEN 1 ELSE 0 END), N'/',
        SUM(CASE WHEN EstadoActualID = 3 THEN 1 ELSE 0 END), N'/',
        SUM(CASE WHEN EstadoActualID = 6 THEN 1 ELSE 0 END))
    FROM dbo.FactPedidoDetalle
    WHERE PedidoID BETWEEN 100001 AND 100045;

    IF @gLineas <> 52 OR @gLedger <> 110 OR @gDev <> 6
       OR @gPick <> 9 OR @gRec <> 2 OR @gEstados <> N'30/6/8/6/2'
        THROW 51471, N'La sesion 1 no esta completa, es inconsistente o la sesion 2 quedo a medias: se detiene para revision (esperado: 52 lineas, ledger 110, 6 devoluciones, 9+2 incidencias, estados 30/6/8/6/2).', 1;

    -- ---- Gate 3: intervalo temporal real (día natural posterior) ----------
    DECLARE @Ini DATETIME2;
    SELECT @Ini = MIN(FechaHora)
    FROM dbo.FactMovimientoInventario
    WHERE Origen = N'RECEPCION_CD';

    IF @Ini IS NULL
        THROW 51472, N'No existen recepciones de la sesion 1: estado inconsistente.', 1;

    IF DATEDIFF(DAY, @Ini, SYSDATETIME()) < 1
    BEGIN
        PRINT N'La sesión 2 no puede ejecutarse todavía porque no se ha cumplido el intervalo temporal real requerido.';
        RETURN;
    END

    -- ---- I. Operaciones de la sesión 2 ------------------------------------
    DECLARE @EscalarPicking TABLE (PedidoID INT NOT NULL PRIMARY KEY, SKUID INT NOT NULL);
    INSERT INTO @EscalarPicking (PedidoID, SKUID) VALUES
        (100015, 5), (100014, 14), (100027, 9), (100040, 17);

    DECLARE @CancelarXI TABLE (PedidoID INT NOT NULL PRIMARY KEY, SKUID INT NOT NULL);
    INSERT INTO @CancelarXI (PedidoID, SKUID) VALUES
        (100015, 5), (100014, 14), (100027, 9);

    DECLARE @ResolverIR TABLE (PedidoID INT NOT NULL PRIMARY KEY, SKUID INT NOT NULL);
    INSERT INTO @ResolverIR (PedidoID, SKUID) VALUES (100040, 17);

    DECLARE @PermanecerIP TABLE (PedidoID INT NOT NULL PRIMARY KEY, SKUID INT NOT NULL);
    INSERT INTO @PermanecerIP (PedidoID, SKUID) VALUES (100028, 14), (100024, 17);

    DECLARE @LineaID INT, @IncidenciaID INT, @FechaID INT, @Res VARCHAR(20),
            @FechaBase DATE, @FechaIDMas1 INT, @LineasProc INT = -1,
            @FechaIDVenc INT, @Ahora DATETIME2(0);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- ---- I1. Escalar las 4 incidencias de picking (área 2, D-I) -------
        -- DML directo documentado: transición escalada + AreaEscaladaID.
        DECLARE curEsc CURSOR LOCAL FAST_FORWARD FOR
            SELECT d.LineaID, i.IncidenciaID
            FROM @EscalarPicking e
            INNER JOIN dbo.FactPedidoDetalle d
                ON d.PedidoID = e.PedidoID AND d.SKUID = e.SKUID
            INNER JOIN dbo.FactIncidencia i
                ON i.LineaID = d.LineaID AND i.EstadoResolucion = N'en_atencion';

        OPEN curEsc;
        FETCH NEXT FROM curEsc INTO @LineaID, @IncidenciaID;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            UPDATE dbo.FactIncidencia
            SET EstadoResolucion = N'escalada', AreaEscaladaID = 2
            WHERE IncidenciaID = @IncidenciaID AND EstadoResolucion = N'en_atencion';

            IF @@ROWCOUNT <> 1
                THROW 51473, N'No se pudo escalar una incidencia de picking (area 2).', 1;

            FETCH NEXT FROM curEsc INTO @LineaID, @IncidenciaID;
        END

        CLOSE curEsc;
        DEALLOCATE curEsc;

        IF (SELECT COUNT(*)
            FROM @EscalarPicking e
            INNER JOIN dbo.FactPedidoDetalle d
                ON d.PedidoID = e.PedidoID AND d.SKUID = e.SKUID
            INNER JOIN dbo.FactIncidencia i
                ON i.LineaID = d.LineaID
               AND i.EstadoResolucion = N'escalada' AND i.AreaEscaladaID = 2) <> 4
            THROW 51474, N'No quedaron exactamente 4 incidencias de picking escaladas al area 2.', 1;

        -- ---- I2. Las 2 incidencias IP permanecen en_atencion (sin tocar) --
        IF (SELECT COUNT(*)
            FROM @PermanecerIP e
            INNER JOIN dbo.FactPedidoDetalle d
                ON d.PedidoID = e.PedidoID AND d.SKUID = e.SKUID
            INNER JOIN dbo.FactIncidencia i
                ON i.LineaID = d.LineaID AND i.EstadoResolucion = N'en_atencion') <> 2
            THROW 51475, N'Las incidencias IP (100028, 100024) deben permanecer en_atencion.', 1;

        -- ---- I3. Cancelar las 3 líneas XI (MotivoID 8 + incidencia) -------
        DECLARE curCan CURSOR LOCAL FAST_FORWARD FOR
            SELECT d.LineaID, i.IncidenciaID, d.FechaID
            FROM @CancelarXI c
            INNER JOIN dbo.FactPedidoDetalle d
                ON d.PedidoID = c.PedidoID AND d.SKUID = c.SKUID
            INNER JOIN dbo.FactIncidencia i
                ON i.LineaID = d.LineaID AND i.EstadoResolucion = N'escalada';

        OPEN curCan;
        FETCH NEXT FROM curCan INTO @LineaID, @IncidenciaID, @FechaID;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Fecha de operación = día natural posterior a la fecha de negocio
            SELECT @FechaBase = Fecha FROM dbo.DimFecha WHERE FechaID = @FechaID;
            SELECT @FechaIDMas1 = FechaID FROM dbo.DimFecha WHERE Fecha = DATEADD(DAY, 1, @FechaBase);

            IF @FechaIDMas1 IS NULL
                THROW 51486, N'No existe en DimFecha el día siguiente a la fecha de negocio de una línea XI.', 1;

            EXEC dbo.sp_CancelarPedido
                @LineaID = @LineaID, @MotivoID = 8, @FechaID = @FechaIDMas1,
                @IncidenciaID = @IncidenciaID, @Resultado = @Res OUTPUT;

            IF @Res <> 'CANCELADO'
                THROW 51476, N'resultado inesperado en sp_CancelarPedido (incidencia XI).', 1;

            FETCH NEXT FROM curCan INTO @LineaID, @IncidenciaID, @FechaID;
        END

        CLOSE curCan;
        DEALLOCATE curCan;

        IF (SELECT COUNT(*)
            FROM @CancelarXI c
            INNER JOIN dbo.FactPedidoDetalle d
                ON d.PedidoID = c.PedidoID AND d.SKUID = c.SKUID
            WHERE d.EstadoActualID = 5 AND d.MotivoCancelacionID = 8) <> 3
            THROW 51477, N'No quedaron exactamente 3 lineas XI canceladas por incidencia (MotivoID 8).', 1;

        -- ---- I4. Resolver la incidencia IR y completar su flujo ----------
        SET @LineaID = NULL; SET @IncidenciaID = NULL; SET @FechaID = NULL;

        SELECT @LineaID = d.LineaID, @IncidenciaID = i.IncidenciaID, @FechaID = d.FechaID
        FROM @ResolverIR r
        INNER JOIN dbo.FactPedidoDetalle d
            ON d.PedidoID = r.PedidoID AND d.SKUID = r.SKUID
        INNER JOIN dbo.FactIncidencia i
            ON i.LineaID = d.LineaID AND i.EstadoResolucion IN (N'en_atencion', N'escalada');

        IF @LineaID IS NULL OR @IncidenciaID IS NULL
            THROW 51478, N'No se localizo la linea/ incidencia IR (100040, SKU17).', 1;

        SELECT @FechaBase = Fecha FROM dbo.DimFecha WHERE FechaID = @FechaID;
        SELECT @FechaIDMas1 = FechaID FROM dbo.DimFecha WHERE Fecha = DATEADD(DAY, 1, @FechaBase);

        IF @FechaIDMas1 IS NULL
            THROW 51486, N'No existe en DimFecha el dia siguiente a la fecha de negocio de la linea IR.', 1;

        EXEC dbo.sp_ResolverIncidencia
            @LineaID = @LineaID, @IncidenciaID = @IncidenciaID,
            @FechaID = @FechaIDMas1, @Resultado = @Res OUTPUT;
        IF @Res <> 'RESUELTA'
            THROW 51479, N'resultado inesperado en sp_ResolverIncidencia (linea IR).', 1;

        EXEC dbo.sp_ConfirmarPicking @LineaID = @LineaID, @FechaID = @FechaIDMas1, @Resultado = @Res OUTPUT;
        IF @Res <> 'EMPAQUETADO'
            THROW 51480, N'resultado inesperado en sp_ConfirmarPicking (linea IR).', 1;

        EXEC dbo.sp_PrepararDespacho @LineaID = @LineaID, @FechaID = @FechaIDMas1, @Resultado = @Res OUTPUT;
        IF @Res <> 'EN_TRANSITO'
            THROW 51481, N'resultado inesperado en sp_PrepararDespacho (linea IR).', 1;

        EXEC dbo.sp_RegistrarEntrega @LineaID = @LineaID, @FechaID = @FechaIDMas1, @Resultado = @Res OUTPUT;
        IF @Res <> 'ENTREGADO'
            THROW 51482, N'resultado inesperado en sp_RegistrarEntrega (linea IR).', 1;

        EXEC dbo.sp_CompletarPedido @LineaID = @LineaID, @FechaID = @FechaIDMas1, @Resultado = @Res OUTPUT;
        IF @Res <> 'COMPLETADO'
            THROW 51483, N'resultado inesperado en sp_CompletarPedido (linea IR).', 1;

        -- ---- I5. Escalar la recepción pendiente (área 3, D-I) -------------
        -- Es la unica recepcion_incompleta todavia en_atencion (la otra se
        -- resolvio en la sesion 1). DML directo documentado.
        UPDATE dbo.FactIncidencia
        SET EstadoResolucion = N'escalada', AreaEscaladaID = 3
        WHERE TipoIncidencia = N'recepcion_incompleta'
          AND EstadoResolucion = N'en_atencion';

        IF @@ROWCOUNT <> 1
            THROW 51484, N'Se esperaba exactamente 1 incidencia de recepcion en_atencion para escalar al area 3.', 1;

        IF (SELECT COUNT(*) FROM dbo.FactIncidencia
            WHERE TipoIncidencia = N'recepcion_incompleta'
              AND EstadoResolucion = N'escalada' AND AreaEscaladaID = 3) <> 1
            THROW 51485, N'La incidencia de recepcion escalada no quedo con AreaEscaladaID = 3 (Abastecimiento).', 1;

        IF (SELECT COUNT(*) FROM dbo.FactIncidencia
            WHERE TipoIncidencia = N'recepcion_incompleta'
              AND EstadoResolucion = N'en_atencion') <> 0
            THROW 51485, N'Quedaron incidencias de recepcion en_atencion tras la sesion 2.', 1;

        -- ---- I6. Vencimientos de las 2 líneas VN (SP) ---------------------
        -- Ventana: >= 1 dia real entre "Disponible para recojo" (sesion 1,
        -- SYSDATETIME real) y SYSDATETIME() de esta sesion (ya >= 1 por el
        -- gate 3). FechaID de negocio = dia siguiente a 20260318.
        SELECT @FechaIDVenc = FechaID
        FROM dbo.DimFecha
        WHERE Fecha = DATEADD(DAY, 1, (SELECT Fecha FROM dbo.DimFecha WHERE FechaID = 20260318));

        IF @FechaIDVenc IS NULL
            THROW 51487, N'No existe en DimFecha el dia siguiente a 20260318 para los vencimientos.', 1;

        -- Tiempo real de la sesion 2 (variable: T-SQL no admite funciones
        -- como valor de parametro de un EXEC).
        SET @Ahora = SYSDATETIME();

        EXEC dbo.sp_ProcesarVencimientosRecojo
            @FechaHoraActual = @Ahora,
            @DiasVentanaRecojo = 1,
            @FechaID = @FechaIDVenc,
            @MotivoVencimientoID = 9,
            @LineasProcesadas = @LineasProc OUTPUT;

        IF @LineasProc <> 2
            THROW 51488, N'sp_ProcesarVencimientosRecojo no proceso exactamente las 2 lineas VN esperadas.', 1;

        COMMIT TRANSACTION;
        PRINT N'SESSION 2: operaciones completadas (seccion I).';
    END TRY
    BEGIN CATCH
        DECLARE @Err2 NVARCHAR(400) = ERROR_MESSAGE();
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        PRINT N'SESSION 2: ERROR - transaccion revertida (ROLLBACK). ' + @Err2;
        PRINT N'ESTADO BLOQUE 4: DETENIDO POR INCOMPATIBILIDAD';
        THROW;
    END CATCH
END
ELSE
    PRINT N'SESSION 2: ya ejecutada - se omiten las operaciones (idempotencia).';

-- ===========================================================================
-- SESIÓN 2 — Sección J: validaciones finales (mismo batch que los gates,
-- para que el RETURN del gate temporal no ejecute J antes de tiempo)
-- Valores definitivos (31/11/8/2/0, ledger 116, matriz §25 final).
-- ===========================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @V TABLE
(
    Nro        INT           NOT NULL PRIMARY KEY,
    Validacion NVARCHAR(80)  NOT NULL,
    Esperado   NVARCHAR(80)  NOT NULL,
    Obtenido   NVARCHAR(160) NOT NULL,
    Resultado  VARCHAR(5)    NOT NULL
);

DECLARE @n INT, @n1 INT, @n2 INT, @n3 INT, @n4 INT, @n5 INT, @n6 INT,
        @s NVARCHAR(200), @d INT;

-- ---- Q01: ventanas de fecha del pedido ------------------------------------
SELECT @n1 = COUNT(DISTINCT CASE WHEN p.FechaID <  20260201 THEN p.PedidoID END),
       @n2 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260201 AND 20260228 THEN p.PedidoID END),
       @n3 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260301 AND 20260314 THEN p.PedidoID END),
       @n4 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260315 AND 20260321 THEN p.PedidoID END),
       @n5 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260322 AND 20260331 THEN p.PedidoID END)
FROM (SELECT DISTINCT PedidoID, FechaID
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045) p;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (1, N'Q01 Ventanas ene/feb/mar1-14/campana/mar22-31', N'12/11/10/9/3',
        CONCAT(@n1, N'/', @n2, N'/', @n3, N'/', @n4, N'/', @n5),
        CASE WHEN @n1=12 AND @n2=11 AND @n3=10 AND @n4=9 AND @n5=3 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q02: canal -----------------------------------------------------------
SELECT @n1 = COUNT(DISTINCT CASE WHEN p.Canal = 'recojo'   THEN p.PedidoID END),
       @n2 = COUNT(DISTINCT CASE WHEN p.Canal = 'despacho' THEN p.PedidoID END)
FROM (SELECT DISTINCT PedidoID, Canal
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045) p;

SELECT @n3 = SUM(CASE WHEN Canal = 'recojo'   THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN Canal = 'despacho' THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (2, N'Q02 Canal: pedidos y lineas recojo/despacho', N'27/18 pedidos; 31/21 lineas',
        CONCAT(@n1, N'/', @n2, N' pedidos; ', @n3, N'/', @n4, N' lineas'),
        CASE WHEN @n1=27 AND @n2=18 AND @n3=31 AND @n4=21 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q03: tiendas ---------------------------------------------------------
SELECT @n  = SUM(CASE WHEN TiendaID IS NULL THEN 1 ELSE 0 END),
       @n1 = SUM(CASE WHEN TiendaID = 5 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN TiendaID = 6 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN TiendaID = 7 THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN TiendaID = 8 THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (3, N'Q03 Tiendas: T5 sin pedidos; reparto T6/T7/T8; rechazados NULL',
        N'NULL=8; T5=0; T6=16; T7=16; T8=12',
        CONCAT(N'NULL=', @n, N'; T5=', @n1, N'; T6=', @n2, N'; T7=', @n3, N'; T8=', @n4),
        CASE WHEN @n=8 AND @n1=0 AND @n2=16 AND @n3=16 AND @n4=12 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q04: estados (FINAL: 31/11/8/2/0) -----------------------------------
SELECT @n1 = SUM(CASE WHEN EstadoActualID = 8 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN EstadoActualID = 5 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN EstadoActualID = 2 THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN EstadoActualID = 3 THEN 1 ELSE 0 END),
       @n5 = SUM(CASE WHEN EstadoActualID = 6 THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (4, N'Q04 Estados de linea (Com/Can/Rech/Inc/Disp)', N'Com=31; Can=11; Rech=8; Inc=2; Disp=0',
        CONCAT(N'Com=', @n1, N'; Can=', @n2, N'; Rech=', @n3, N'; Inc=', @n4, N'; Disp=', @n5),
        CASE WHEN @n1=31 AND @n2=11 AND @n3=8 AND @n4=2 AND @n5=0 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q05: motivos (FINAL: 6/3/2) -----------------------------------------
SELECT @n1 = SUM(CASE WHEN MotivoCancelacionID = 7 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN MotivoCancelacionID = 8 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN MotivoCancelacionID = 9 THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045 AND EstadoActualID = 5;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (5, N'Q05 Cancelaciones: voluntaria/incidencia/vencimiento', N'vol=6; inc=3; venc=2',
        CONCAT(N'vol=', ISNULL(@n1, 0), N'; inc=', ISNULL(@n2, 0), N'; venc=', ISNULL(@n3, 0)),
        CASE WHEN ISNULL(@n1,0)=6 AND ISNULL(@n2,0)=3 AND ISNULL(@n3,0)=2 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q06: matriz §25 final ------------------------------------------------
SELECT @s = CONCAT(
    N'ne ',
    (SELECT CONCAT(ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'resuelta'    THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'no_resuelta' THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'en_atencion'  THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'escalada'     THEN 1 ELSE 0 END), 0))
       FROM dbo.FactIncidencia i
       WHERE i.TipoIncidencia = N'no_encontrado'
         AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
                     WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045)),
    N'; ci ',
    (SELECT CONCAT(ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'resuelta'    THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'no_resuelta' THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'en_atencion'  THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'escalada'     THEN 1 ELSE 0 END), 0))
       FROM dbo.FactIncidencia i
       WHERE i.TipoIncidencia = N'cantidad_insuficiente'
         AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
                     WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045)),
    N'; da ',
    (SELECT CONCAT(ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'resuelta'    THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'no_resuelta' THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'en_atencion'  THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'escalada'     THEN 1 ELSE 0 END), 0))
       FROM dbo.FactIncidencia i
       WHERE i.TipoIncidencia = N'dañado'
         AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
                     WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045)),
    N'; rec ',
    (SELECT CONCAT(ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'resuelta'    THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'no_resuelta' THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'en_atencion'  THEN 1 ELSE 0 END), 0), N'/',
                   ISNULL(SUM(CASE WHEN i.EstadoResolucion = N'escalada'     THEN 1 ELSE 0 END), 0))
       FROM dbo.FactIncidencia i
       WHERE i.TipoIncidencia = N'recepcion_incompleta'));

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (6, N'Q06 Matriz incidencias tipo x estado (res/nores/atenc/esc)',
        N'ne 2/1/1/0; ci 1/1/1/0; da 1/1/0/0; rec 1/0/0/1', @s,
        CASE WHEN @s = N'ne 2/1/1/0; ci 1/1/1/0; da 1/1/0/0; rec 1/0/0/1'
             THEN 'OK' ELSE 'FALLA' END);

-- ---- Q07: escalamientos (FINAL: area2=4, area3=1) ------------------------
SELECT @n1 = SUM(CASE WHEN AreaEscaladaID = 2 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN AreaEscaladaID = 3 THEN 1 ELSE 0 END)
FROM dbo.FactIncidencia;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (7, N'Q07 Escalamientos persistidos (area2 picking / area3 recepcion)',
        N'area2=4; area3=1',
        CONCAT(N'area2=', ISNULL(@n1, 0), N'; area3=', ISNULL(@n2, 0)),
        CASE WHEN ISNULL(@n1, 0) = 4 AND ISNULL(@n2, 0) = 1 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q08: devoluciones ----------------------------------------------------
SELECT @n  = COUNT(*),
       @n1 = SUM(CASE WHEN dv.MotivoID = 15 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN dv.MotivoID = 16 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN dv.MotivoID = 17 THEN 1 ELSE 0 END),
       @d  = MAX(DATEDIFF(DAY, f1.Fecha, f2.Fecha))
FROM dbo.FactDevolucion dv
INNER JOIN dbo.FactPedidoDetalle d ON d.LineaID = dv.LineaID
INNER JOIN dbo.DimFecha f1 ON f1.FechaID = d.FechaID
INNER JOIN dbo.DimFecha f2 ON f2.FechaID = dv.FechaID
WHERE d.PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (8, N'Q08 Devoluciones: total, motivos 15/16/17 y ventana',
        N'total=6; m15=2; m16=2; m17=2; max_dias=5',
        CONCAT(N'total=', ISNULL(@n, 0), N'; m15=', ISNULL(@n1, 0), N'; m16=', ISNULL(@n2, 0),
               N'; m17=', ISNULL(@n3, 0), N'; max_dias=', ISNULL(@d, -1)),
        CASE WHEN ISNULL(@n,0)=6 AND ISNULL(@n1,0)=2 AND ISNULL(@n2,0)=2
                  AND ISNULL(@n3,0)=2 AND ISNULL(@d,-1)=5 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q09: clientes --------------------------------------------------------
SELECT @n = COUNT(*), @n1 = MIN(c), @n2 = MAX(c)
FROM (SELECT x.ClienteID, COUNT(*) AS c
      FROM (SELECT DISTINCT PedidoID, ClienteID
            FROM dbo.FactPedidoDetalle
            WHERE PedidoID BETWEEN 100001 AND 100045) x
      GROUP BY x.ClienteID) y;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (9, N'Q09 Clientes: cobertura y reparto', N'clientes=6; min=7; max=8',
        CONCAT(N'clientes=', ISNULL(@n, 0), N'; min=', ISNULL(@n1, 0), N'; max=', ISNULL(@n2, 0)),
        CASE WHEN ISNULL(@n,0)=6 AND ISNULL(@n1,0)=7 AND ISNULL(@n2,0)=8 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q10: campana ---------------------------------------------------------
SELECT @n1 = COUNT(DISTINCT PedidoID)
FROM (SELECT DISTINCT PedidoID, FechaID
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045
        AND FechaID BETWEEN 20260315 AND 20260321) p;

SELECT @n2 = COUNT(*)
FROM dbo.FactIncidencia i
WHERE i.TipoIncidencia <> N'recepcion_incompleta'
  AND i.FechaID BETWEEN 20260315 AND 20260321
  AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
              WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045);

SELECT @n3 = COUNT(*)
FROM dbo.FactHistorialEstadoLinea h
INNER JOIN dbo.FactPedidoDetalle d ON d.LineaID = h.LineaID
WHERE d.PedidoID BETWEEN 100001 AND 100045
  AND h.EstadoID = 5
  AND h.FechaID BETWEEN 20260315 AND 20260321;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (10, N'Q10 Campana: pedidos, incidencias y cancelaciones en 15-21 marzo',
        N'pedidos=9; incidencias>=1; cancelaciones>=1',
        CONCAT(N'pedidos=', @n1, N'; incidencias=', @n2, N'; cancelaciones=', @n3),
        CASE WHEN @n1 = 9 AND @n2 >= 1 AND @n3 >= 1 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q11: stock global ----------------------------------------------------
SELECT @n1 = COUNT(*)
FROM dbo.StockSKUTienda
WHERE StockSistema < 0 OR StockReservado < 0 OR StockReservado > StockSistema;

SELECT @n2 = SUM(StockSistema - StockReservado) FROM dbo.StockSKUTienda;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (11, N'Q11 Stock global: invariantes y disponibilidad', N'negativos=0; disponible>0',
        CONCAT(N'negativos=', @n1, N'; disponible=', ISNULL(@n2, -9999)),
        CASE WHEN @n1 = 0 AND ISNULL(@n2, -1) > 0 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q12: SKUs con movimiento --------------------------------------------
SELECT @n = COUNT(DISTINCT SKUID) FROM dbo.FactMovimientoInventario;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (12, N'Q12 SKUs distintos con movimiento en el ledger', N'>=12',
        CONCAT(N'skus_con_movimiento=', @n),
        CASE WHEN @n >= 12 THEN 'OK' ELSE 'FALLA' END);

-- ---- Q13: vencimientos (FINAL) -------------------------------------------
SELECT @n1 = COUNT(*)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045 AND EstadoActualID = 6;

SELECT @n2 = COUNT(*)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045 AND EstadoActualID = 5 AND MotivoCancelacionID = 9;

SELECT @n3 = COUNT(*)
FROM dbo.FactMovimientoInventario
WHERE TipoMovimiento = N'AJUSTE' AND MotivoID = 31 AND FechaID >= 20260315;

SELECT @n4 = MIN(DATEDIFF(DAY, a.FechaHora, b.FechaHora))
FROM dbo.FactHistorialEstadoLinea a
INNER JOIN dbo.FactHistorialEstadoLinea b ON b.LineaID = a.LineaID
INNER JOIN dbo.FactPedidoDetalle d ON d.LineaID = a.LineaID
WHERE d.PedidoID IN (100038, 100039)
  AND a.EstadoID = 6 AND b.EstadoID = 7;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (13, N'Q13 Vencimientos: pendientes/procesados/retornos/intervalo real',
        N'pendientes=0; procesados=2; retornos=2; intervalo>=1',
        CONCAT(N'pendientes=', @n1, N'; procesados=', @n2, N'; retornos=', @n3,
               N'; intervalo=', ISNULL(@n4, -1), N'd'),
        CASE WHEN @n1 = 0 AND @n2 = 2 AND @n3 = 2 AND ISNULL(@n4, -1) >= 1
             THEN 'OK' ELSE 'FALLA' END);

-- ---- C01 ------------------------------------------------------------------
SELECT @n = COUNT(DISTINCT PedidoID)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (14, N'C01 Pedidos distintos del Bloque 4', N'45', CAST(@n AS NVARCHAR(60)),
        CASE WHEN @n = 45 THEN 'OK' ELSE 'FALLA' END);

-- ---- C02 ------------------------------------------------------------------
SELECT @n = SUM(c),
       @n1 = SUM(CASE WHEN c = 1 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN c = 2 THEN 1 ELSE 0 END)
FROM (SELECT PedidoID, COUNT(*) AS c
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045
      GROUP BY PedidoID) p;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (15, N'C02 Lineas y pedidos de 1 y 2 lineas', N'lineas=52; 1 linea=38; 2 lineas=7',
        CONCAT(N'lineas=', ISNULL(@n, 0), N'; 1 linea=', @n1, N'; 2 lineas=', @n2),
        CASE WHEN @n = 52 AND @n1 = 38 AND @n2 = 7 THEN 'OK' ELSE 'FALLA' END);

-- ---- C03: estados FINALES -------------------------------------------------
SELECT @n1 = SUM(CASE WHEN EstadoActualID = 8 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN EstadoActualID = 5 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN EstadoActualID = 2 THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN EstadoActualID = 3 THEN 1 ELSE 0 END),
       @n5 = SUM(CASE WHEN EstadoActualID = 6 THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (16, N'C03 Estados (Com/Can/Rech/Inc/Disp) y total', N'31/11/8/2/0; total=52',
        CONCAT(@n1, N'/', @n2, N'/', @n3, N'/', @n4, N'/', @n5, N'; total=',
               ISNULL(@n1,0)+ISNULL(@n2,0)+ISNULL(@n3,0)+ISNULL(@n4,0)+ISNULL(@n5,0)),
        CASE WHEN @n1=31 AND @n2=11 AND @n3=8 AND @n4=2 AND @n5=0 THEN 'OK' ELSE 'FALLA' END);

-- ---- C04: motivos FINALES (6/3/2) ----------------------------------------
SELECT @n1 = SUM(CASE WHEN MotivoCancelacionID = 7 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN MotivoCancelacionID = 8 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN MotivoCancelacionID = 9 THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045 AND EstadoActualID = 5;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (17, N'C04 Motivos de cancelacion vol/inc/venc', N'6/3/2',
        CONCAT(ISNULL(@n1, 0), N'/', ISNULL(@n2, 0), N'/', ISNULL(@n3, 0)),
        CASE WHEN ISNULL(@n1,0)=6 AND ISNULL(@n2,0)=3 AND ISNULL(@n3,0)=2 THEN 'OK' ELSE 'FALLA' END);

-- ---- C05 ------------------------------------------------------------------
SELECT @n1 = COUNT(DISTINCT CASE WHEN p.Canal = 'recojo'   THEN p.PedidoID END),
       @n2 = COUNT(DISTINCT CASE WHEN p.Canal = 'despacho' THEN p.PedidoID END)
FROM (SELECT DISTINCT PedidoID, Canal
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045) p;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (18, N'C05 Canal por pedido recojo/despacho', N'27/18',
        CONCAT(@n1, N'/', @n2),
        CASE WHEN @n1 = 27 AND @n2 = 18 THEN 'OK' ELSE 'FALLA' END);

-- ---- C06 ------------------------------------------------------------------
SELECT @n  = SUM(CASE WHEN TiendaID IS NULL THEN 1 ELSE 0 END),
       @n1 = SUM(CASE WHEN TiendaID = 5 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN TiendaID = 6 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN TiendaID = 7 THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN TiendaID = 8 THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (19, N'C06 Tiendas: Web Nacional sin pedidos; reparto T6/T7/T8',
        N'T5=0; T6=16; T7=16; T8=12; NULL=8',
        CONCAT(N'T5=', @n1, N'; T6=', @n2, N'; T7=', @n3, N'; T8=', @n4, N'; NULL=', @n),
        CASE WHEN @n=8 AND @n1=0 AND @n2=16 AND @n3=16 AND @n4=12 THEN 'OK' ELSE 'FALLA' END);

-- ---- C07 ------------------------------------------------------------------
SELECT @n = COUNT(*), @n1 = MIN(c), @n2 = MAX(c)
FROM (SELECT x.ClienteID, COUNT(*) AS c
      FROM (SELECT DISTINCT PedidoID, ClienteID
            FROM dbo.FactPedidoDetalle
            WHERE PedidoID BETWEEN 100001 AND 100045) x
      GROUP BY x.ClienteID) y;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (20, N'C07 Clientes: 6 con 7-8 pedidos', N'6/7/8',
        CONCAT(ISNULL(@n, 0), N'/', ISNULL(@n1, 0), N'/', ISNULL(@n2, 0)),
        CASE WHEN ISNULL(@n,0)=6 AND ISNULL(@n1,0)=7 AND ISNULL(@n2,0)=8 THEN 'OK' ELSE 'FALLA' END);

-- ---- C08 ------------------------------------------------------------------
SELECT @n1 = SUM(CASE WHEN Cantidad = 1 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN Cantidad = 2 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN Cantidad = 3 THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN Cantidad = 4 THEN 1 ELSE 0 END)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (21, N'C08 Cantidades 1/2/3/4 por linea', N'1=29; 2=14; 3=6; 4=3',
        CONCAT(N'1=', @n1, N'; 2=', @n2, N'; 3=', @n3, N'; 4=', @n4),
        CASE WHEN @n1=29 AND @n2=14 AND @n3=6 AND @n4=3 THEN 'OK' ELSE 'FALLA' END);

-- ---- C09 ------------------------------------------------------------------
SELECT @n1 = COUNT(DISTINCT CASE WHEN p.FechaID <  20260201 THEN p.PedidoID END),
       @n2 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260201 AND 20260228 THEN p.PedidoID END),
       @n3 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260301 AND 20260314 THEN p.PedidoID END),
       @n4 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260315 AND 20260321 THEN p.PedidoID END),
       @n5 = COUNT(DISTINCT CASE WHEN p.FechaID BETWEEN 20260322 AND 20260331 THEN p.PedidoID END)
FROM (SELECT DISTINCT PedidoID, FechaID
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045) p;

SELECT @n = COUNT(DISTINCT FechaID)
FROM dbo.FactPedidoDetalle
WHERE PedidoID BETWEEN 100001 AND 100045;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (22, N'C09 Ventanas exactas y diversidad de fechas (>=25)', N'12/11/10/9/3; distintas>=25',
        CONCAT(@n1, N'/', @n2, N'/', @n3, N'/', @n4, N'/', @n5, N'; distintas=', @n),
        CASE WHEN @n1=12 AND @n2=11 AND @n3=10 AND @n4=9 AND @n5=3 AND @n >= 25
             THEN 'OK' ELSE 'FALLA' END);

-- ---- C10 ------------------------------------------------------------------
SELECT @n1 = COUNT(DISTINCT PedidoID)
FROM (SELECT DISTINCT PedidoID, FechaID
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045
        AND FechaID BETWEEN 20260315 AND 20260321) p;

SELECT @n2 = COUNT(*)
FROM dbo.FactIncidencia i
WHERE i.TipoIncidencia <> N'recepcion_incompleta'
  AND i.FechaID BETWEEN 20260315 AND 20260321
  AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
              WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045);

SELECT @n3 = COUNT(*)
FROM dbo.FactHistorialEstadoLinea h
INNER JOIN dbo.FactPedidoDetalle d ON d.LineaID = h.LineaID
WHERE d.PedidoID BETWEEN 100001 AND 100045
  AND h.EstadoID = 5
  AND h.FechaID BETWEEN 20260315 AND 20260321;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (23, N'C10 Campana Cyber Origen: pedidos/incidencias/cancelaciones',
        N'pedidos=9; incid>=1; cancel>=1',
        CONCAT(N'pedidos=', @n1, N'; incid=', @n2, N'; cancel=', @n3),
        CASE WHEN @n1 = 9 AND @n2 >= 1 AND @n3 >= 1 THEN 'OK' ELSE 'FALLA' END);

-- ---- C11 ------------------------------------------------------------------
SELECT @n = COUNT(DISTINCT d.SKUID)
FROM dbo.FactPedidoDetalle d
WHERE d.PedidoID BETWEEN 100001 AND 100045;

SELECT @n1 = COUNT(DISTINCT p.Categoria)
FROM (SELECT DISTINCT SKUID
      FROM dbo.FactPedidoDetalle
      WHERE PedidoID BETWEEN 100001 AND 100045) d
INNER JOIN dbo.DimSKU s ON s.SKUID = d.SKUID
INNER JOIN dbo.DimProducto p ON p.ProductoID = s.ProductoID;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (24, N'C11 SKUs distintos (>=12) y categorias (4)', N'skus>=12; cats=4',
        CONCAT(N'skus=', @n, N'; cats=', @n1),
        CASE WHEN @n >= 12 AND @n1 = 4 THEN 'OK' ELSE 'FALLA' END);

-- ---- C12 ------------------------------------------------------------------
SELECT @n = COUNT(DISTINCT SKUID) FROM dbo.FactMovimientoInventario;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (25, N'C12 SKUs distintos con movimiento', N'14', CAST(@n AS NVARCHAR(60)),
        CASE WHEN @n = 14 THEN 'OK' ELSE 'FALLA' END);

-- ---- C13 ------------------------------------------------------------------
SELECT @n1 = COUNT(*)
FROM dbo.StockSKUTienda
WHERE StockSistema < 0 OR StockReservado < 0 OR StockReservado > StockSistema;

;WITH L AS (
    SELECT SKUID, TiendaID,
           SUM(CASE WHEN TipoMovimiento IN (N'INGRESO', N'AJUSTE', N'DESCUENTO_DEFINITIVO')
                    THEN Cantidad ELSE 0 END) AS Sis,
           SUM(CASE WHEN TipoMovimiento IN (N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO')
                    THEN Cantidad ELSE 0 END) AS Res
    FROM dbo.FactMovimientoInventario
    GROUP BY SKUID, TiendaID
)
SELECT @n2 = COUNT(*)
FROM dbo.StockSKUTienda s
LEFT JOIN L ON L.SKUID = s.SKUID AND L.TiendaID = s.TiendaID
WHERE s.StockSistema <> ISNULL(L.Sis, 0)
   OR s.StockReservado <> ISNULL(L.Res, 0);

SELECT @n3 = COUNT(*) FROM dbo.StockSKUTienda;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (26, N'C13 Stock: sin negativos, ledger=resumen, cobertura', N'neg=0; disc=0; filas=56',
        CONCAT(N'neg=', @n1, N'; disc=', @n2, N'; filas=', @n3),
        CASE WHEN @n1 = 0 AND @n2 = 0 AND @n3 = 56 THEN 'OK' ELSE 'FALLA' END);

-- ---- C14 ------------------------------------------------------------------
SELECT @n = COUNT(*)
FROM dbo.vw_StockHistorico
WHERE StockSistema < 0 OR StockReservado < 0 OR StockDisponible < 0;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (27, N'C14 Grilla historica: ceros/negativos por FechaID', N'0',
        CAST(@n AS NVARCHAR(60)),
        CASE WHEN @n = 0 THEN 'OK' ELSE 'FALLA' END);

-- ---- C15 ------------------------------------------------------------------
SELECT @n  = COUNT(*),
       @n1 = SUM(CASE WHEN Discrepancia = 0 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN Discrepancia > 0 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN FechaID = 20260101 THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN Cantidad = CantidadRecibida AND Cantidad > 0 THEN 1 ELSE 0 END)
FROM dbo.FactMovimientoInventario
WHERE Origen = N'RECEPCION_CD';

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (28, N'C15 Recepciones CD: 8 = 6 exactas + 2 incompletas (20260101)',
        N'total=8; exactas=6; incompletas=2; fecha=20260101',
        CONCAT(N'total=', ISNULL(@n,0), N'; exactas=', ISNULL(@n1,0),
               N'; incompletas=', ISNULL(@n2,0), N'; fecha_ok=', ISNULL(@n3,0),
               N'; cant=recibida=', ISNULL(@n4,0)),
        CASE WHEN @n=8 AND @n1=6 AND @n2=2 AND @n3=8 AND @n4=8 THEN 'OK' ELSE 'FALLA' END);

-- ---- C16: recepcion (FINAL: 1 resuelta + 1 escalada area 3) --------------
SELECT @n  = COUNT(*),
       @n1 = SUM(CASE WHEN EstadoResolucion = N'resuelta'   THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN EstadoResolucion = N'no_resuelta' THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN EstadoResolucion = N'en_atencion' THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN EstadoResolucion = N'escalada'    THEN 1 ELSE 0 END),
       @n5 = SUM(CASE WHEN EstadoResolucion = N'escalada' AND AreaEscaladaID = 3 THEN 1 ELSE 0 END)
FROM dbo.FactIncidencia
WHERE TipoIncidencia = N'recepcion_incompleta';

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (29, N'C16 Recepcion incompleta: 1 resuelta + 1 escalada area 3 (D-J/D-I)',
        N'total=2; res=1; nores=0; atenc=0; esc=1; esc_area3=1',
        CONCAT(N'total=', @n, N'; res=', ISNULL(@n1,0), N'; nores=', ISNULL(@n2,0),
               N'; atenc=', ISNULL(@n3,0), N'; esc=', ISNULL(@n4,0),
               N'; esc_area3=', ISNULL(@n5,0)),
        CASE WHEN @n=2 AND ISNULL(@n1,0)=1 AND ISNULL(@n2,0)=0
                  AND ISNULL(@n3,0)=0 AND ISNULL(@n4,0)=1 AND ISNULL(@n5,0)=1
             THEN 'OK' ELSE 'FALLA' END);

-- ---- C17 ------------------------------------------------------------------
SELECT @n  = COUNT(*),
       @n1 = SUM(CASE WHEN i.TipoIncidencia = N'no_encontrado'       THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN i.TipoIncidencia = N'cantidad_insuficiente' THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN i.TipoIncidencia = N'dañado'              THEN 1 ELSE 0 END)
FROM dbo.FactIncidencia i
WHERE i.TipoIncidencia <> N'recepcion_incompleta'
  AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
              WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045);

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (30, N'C17 Incidencias de picking: no_encontrado/cantidad_insuficiente/danado',
        N'total=9; ne=4; ci=3; da=2',
        CONCAT(N'total=', ISNULL(@n,0), N'; ne=', ISNULL(@n1,0),
               N'; ci=', ISNULL(@n2,0), N'; da=', ISNULL(@n3,0)),
        CASE WHEN ISNULL(@n,0)=9 AND ISNULL(@n1,0)=4 AND ISNULL(@n2,0)=3
                  AND ISNULL(@n3,0)=2 THEN 'OK' ELSE 'FALLA' END);

-- ---- C18: estados FINALES (5/3/2/1) --------------------------------------
SELECT @n1 = SUM(CASE WHEN i.EstadoResolucion = N'resuelta'    THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN i.EstadoResolucion = N'no_resuelta' THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN i.EstadoResolucion = N'en_atencion' THEN 1 ELSE 0 END),
       @n4 = SUM(CASE WHEN i.EstadoResolucion = N'escalada'    THEN 1 ELSE 0 END)
FROM dbo.FactIncidencia i
WHERE (i.TipoIncidencia <> N'recepcion_incompleta'
       AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
                   WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045))
   OR i.TipoIncidencia = N'recepcion_incompleta';

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (31, N'C18 Estados de incidencia (res/nores/atenc/esc) y total', N'5/3/2/1; total=11',
        CONCAT(ISNULL(@n1,0), N'/', ISNULL(@n2,0), N'/', ISNULL(@n3,0), N'/', ISNULL(@n4,0),
               N'; total=', ISNULL(@n1,0)+ISNULL(@n2,0)+ISNULL(@n3,0)+ISNULL(@n4,0)),
        CASE WHEN ISNULL(@n1,0)=5 AND ISNULL(@n2,0)=3 AND ISNULL(@n3,0)=2
                  AND ISNULL(@n4,0)=1
                  AND ISNULL(@n1,0)+ISNULL(@n2,0)+ISNULL(@n3,0)+ISNULL(@n4,0)=11
             THEN 'OK' ELSE 'FALLA' END);

-- ---- C19: matriz §25 final ------------------------------------------------
INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (32, N'C19 Matriz §25 tipo x estado (11 incidencias)',
        N'ne 2/1/1/0; ci 1/1/1/0; da 1/1/0/0; rec 1/0/0/1', @s,
        CASE WHEN @s = N'ne 2/1/1/0; ci 1/1/1/0; da 1/1/0/0; rec 1/0/0/1'
             THEN 'OK' ELSE 'FALLA' END);

-- ---- C20: escaladas con area (FINAL: 4 + 1) ------------------------------
SELECT @n1 = SUM(CASE WHEN AreaEscaladaID = 2 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN AreaEscaladaID = 3 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN EstadoResolucion = N'en_atencion' AND AreaEscaladaID IS NOT NULL
                      THEN 1 ELSE 0 END)
FROM dbo.FactIncidencia;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (33, N'C20 Escaladas con area (picking=2, recepcion=3) y en_atencion sin area',
        N'area2=4; area3=1; en_atencion_con_area=0',
        CONCAT(N'area2=', ISNULL(@n1,0), N'; area3=', ISNULL(@n2,0),
               N'; en_atencion_con_area=', ISNULL(@n3,0)),
        CASE WHEN ISNULL(@n1,0)=4 AND ISNULL(@n2,0)=1 AND ISNULL(@n3,0)=0
             THEN 'OK' ELSE 'FALLA' END);

-- ---- C21 ------------------------------------------------------------------
SELECT @n1 = COUNT(*)
FROM dbo.FactIncidencia i
WHERE i.TipoIncidencia <> N'recepcion_incompleta'
  AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
              WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045);

SELECT @n2 = COUNT(*)
FROM dbo.FactIncidencia
WHERE TipoIncidencia = N'recepcion_incompleta';

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (34, N'C21 Incidencias totales: picking + recepcion (D-J)', N'picking=9; rec=2; total=11',
        CONCAT(N'picking=', @n1, N'; rec=', @n2, N'; total=', @n1 + @n2),
        CASE WHEN @n1 = 9 AND @n2 = 2 AND (@n1 + @n2) = 11 THEN 'OK' ELSE 'FALLA' END);

-- ---- C22 ------------------------------------------------------------------
SELECT @n  = COUNT(*),
       @n1 = SUM(CASE WHEN dv.MotivoID = 15 THEN 1 ELSE 0 END),
       @n2 = SUM(CASE WHEN dv.MotivoID = 16 THEN 1 ELSE 0 END),
       @n3 = SUM(CASE WHEN dv.MotivoID = 17 THEN 1 ELSE 0 END),
       @n4 = MAX(DATEDIFF(DAY, f1.Fecha, f2.Fecha))
FROM dbo.FactDevolucion dv
INNER JOIN dbo.FactPedidoDetalle d ON d.LineaID = dv.LineaID
INNER JOIN dbo.DimFecha f1 ON f1.FechaID = d.FechaID
INNER JOIN dbo.DimFecha f2 ON f2.FechaID = dv.FechaID
WHERE d.PedidoID BETWEEN 100001 AND 100045;

SELECT @n5 = COUNT(*)
FROM (SELECT LineaID FROM dbo.FactDevolucion GROUP BY LineaID HAVING COUNT(*) > 1) x;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (35, N'C22 Devoluciones: 6, motivos 2/2/2, ventana <=7, una por linea',
        N'total=6; m15=2; m16=2; m17=2; max_dias<=7; repetidas=0',
        CONCAT(N'total=', ISNULL(@n,0), N'; m15=', ISNULL(@n1,0), N'; m16=', ISNULL(@n2,0),
               N'; m17=', ISNULL(@n3,0), N'; max_dias=', ISNULL(@n4,0),
               N'; repetidas=', @n5),
        CASE WHEN ISNULL(@n,0)=6 AND ISNULL(@n1,0)=2 AND ISNULL(@n2,0)=2
                  AND ISNULL(@n3,0)=2 AND ISNULL(@n4,0) <= 7 AND @n5 = 0
             THEN 'OK' ELSE 'FALLA' END);

-- ---- C23: ancla intacta ---------------------------------------------------
SELECT @n1 = StockSistema, @n2 = StockReservado
FROM dbo.StockSKUTienda
WHERE SKUID = 4 AND TiendaID = 6;

SELECT @n3 = COUNT(*) FROM dbo.FactMovimientoInventario WHERE SKUID = 4 AND TiendaID = 6;

SELECT @n4 = StockSistema, @n5 = StockReservado, @n6 = StockDisponible
FROM dbo.vw_StockHistorico
WHERE SKUID = 4 AND TiendaID = 6
  AND FechaID = (SELECT MAX(FechaID) FROM dbo.DimFecha);

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (36, N'C23 Ancla SKU4 x Tienda6: stock 8/0, vw 8/0/8, 8 movimientos',
        N'stock=8/0; vw=8/0/8; movs=8',
        CONCAT(N'stock=', @n1, N'/', @n2, N'; vw=', @n4, N'/', @n5, N'/', @n6,
               N'; movs=', @n3),
        CASE WHEN @n1=8 AND @n2=0 AND @n4=8 AND @n5=0 AND @n6=8 AND @n3=8
             THEN 'OK' ELSE 'FALLA' END);

-- ---- C24: patron linea-movimientos y ledger FINAL (116) ------------------
;WITH L AS (
    SELECT d.LineaID, d.Cantidad, d.EstadoActualID, d.MotivoCancelacionID,
           ISNULL(SUM(CASE WHEN m.TipoMovimiento = N'RESERVA'              THEN m.Cantidad END), 0) AS Res,
           ISNULL(SUM(CASE WHEN m.TipoMovimiento = N'LIBERACION_RESERVA'   THEN m.Cantidad END), 0) AS Lib,
           ISNULL(SUM(CASE WHEN m.TipoMovimiento = N'DESCUENTO_DEFINITIVO' THEN m.Cantidad END), 0) AS Dsc,
           COUNT(m.MovimientoID) AS NMov
    FROM dbo.FactPedidoDetalle d
    LEFT JOIN dbo.FactMovimientoInventario m ON m.LineaID = d.LineaID
    WHERE d.PedidoID BETWEEN 100001 AND 100045
    GROUP BY d.LineaID, d.Cantidad, d.EstadoActualID, d.MotivoCancelacionID
)
SELECT @n = COUNT(*)
FROM L
WHERE NOT (
        (EstadoActualID = 2 AND NMov = 0)
     OR (EstadoActualID = 8 AND Res = Cantidad AND Dsc = -Cantidad AND Lib = 0)
     OR (EstadoActualID = 5 AND MotivoCancelacionID = 7 AND Res = Cantidad AND Lib = -Cantidad AND Dsc = 0)
     OR (EstadoActualID = 5 AND MotivoCancelacionID = 8 AND Res = Cantidad AND Lib = -Cantidad AND Dsc = 0)
     OR (EstadoActualID = 5 AND MotivoCancelacionID = 9 AND Res = Cantidad AND Dsc = -Cantidad AND Lib = 0)
     OR (EstadoActualID = 3 AND Res = Cantidad AND Dsc = 0 AND Lib = 0)
     OR (EstadoActualID = 6 AND Res = Cantidad AND Dsc = -Cantidad AND Lib = 0));

SELECT @n1 = COUNT(*) FROM dbo.FactMovimientoInventario;

INSERT INTO @V (Nro, Validacion, Esperado, Obtenido, Resultado) VALUES
    (37, N'C24 Patron linea-movimientos y total del ledger (final)',
        N'desalineadas=0; ledger=116',
        CONCAT(N'desalineadas=', @n, N'; ledger=', @n1),
        CASE WHEN @n = 0 AND @n1 = 116 THEN 'OK' ELSE 'FALLA' END);

-- ---- Resultado J ----------------------------------------------------------
SELECT Nro, Validacion, Esperado, Obtenido, Resultado
FROM @V
ORDER BY Nro;

SELECT CASE WHEN EXISTS (SELECT 1 FROM @V WHERE Resultado <> 'OK')
            THEN N'HAY VALIDACIONES EN FALLA - reportar la tabla completa antes de continuar.'
            ELSE N'37/37 validaciones OK (Q01-Q13: 13/13; C01-C24: 24/24).'
       END AS ResumenBloque4;

-- Detalle informativo: estados de linea.
SELECT e.NombreEstado AS EstadoLinea, COUNT(*) AS Lineas
FROM dbo.FactPedidoDetalle d
INNER JOIN dbo.DimEstado e ON e.EstadoID = d.EstadoActualID
WHERE d.PedidoID BETWEEN 100001 AND 100045
GROUP BY e.NombreEstado
ORDER BY e.NombreEstado;

-- Detalle informativo: matriz de incidencias.
SELECT i.TipoIncidencia, i.EstadoResolucion, COUNT(*) AS N,
       MAX(ISNULL(ae.NombreArea, N'-')) AS AreaEscalada
FROM dbo.FactIncidencia i
LEFT JOIN dbo.DimArea ae ON ae.AreaID = i.AreaEscaladaID
WHERE (i.TipoIncidencia <> N'recepcion_incompleta'
       AND EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
                   WHERE d.LineaID = i.LineaID AND d.PedidoID BETWEEN 100001 AND 100045))
   OR i.TipoIncidencia = N'recepcion_incompleta'
GROUP BY i.TipoIncidencia, i.EstadoResolucion
ORDER BY i.TipoIncidencia, i.EstadoResolucion;

-- ---- §41: reporte de estado (final) ---------------------------------------
IF EXISTS (SELECT 1 FROM @V WHERE Resultado <> 'OK')
    PRINT N'ESTADO BLOQUE 4: DETENIDO POR INCOMPATIBILIDAD';
ELSE
    PRINT N'ESTADO BLOQUE 4: IMPLEMENTADO Y VALIDADO';
GO
