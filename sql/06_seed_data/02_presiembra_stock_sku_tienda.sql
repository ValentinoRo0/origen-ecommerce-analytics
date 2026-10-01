/*
===============================================================================
ORIGEN — Pre-siembra de StockSKUTienda (Fase 4, Bloque 3)
===============================================================================
Diseño acordado (no se modifica nada de Fase 3):

1. Filas base: una fila 0/0 por cada combinación DimSKU x DimTienda
   (14 SKU x 4 tiendas = 56). INSERT directo es válido: cero movimientos en
   el ledger equivale a cero stock, así que la fila 0/0 es coherente con él.
2. Stock inicial: SOLO vía movimientos INGRESO en FactMovimientoInventario,
   con Origen = 'CONFIGURACION_INICIAL', FechaID 20260101 y LineaID NULL.
   El trigger trg_ActualizarStockSKUTienda propaga cada INGRESO a
   StockSKUTienda. Nunca se hace UPDATE directo sobre StockSistema.

      A10001 @ Jockey Plaza            +10
      A10001 @ Real Plaza Arequipa     +4
      A30001 @ Real Plaza Arequipa     +3
      A30002 @ Real Plaza Arequipa     +1
      A40001 @ Mall Aventura Trujillo  +2
      (A20001 @ Jockey Plaza queda en 0: stock cero explícito, se usa para
       probar el camino RECHAZADO de sp_CrearPedido.)

3. Idempotencia: las filas base se insertan solo si no existen; cada INGRESO
   inicial solo si no existe ya uno con Origen = 'CONFIGURACION_INICIAL'
   para ese SKU+Tienda. Re-ejecutar el script no duplica stock.

4. Siete validaciones al final (batch 2). Este script NO declara el bloque
   como completado: eso ocurre cuando se ejecuta en SSMS y las 7 salen OK.

Prerrequisito: haber ejecutado 01_datos_maestros.sql.

Supuestos que este script hace sobre objetos que no están en el contexto de
su redacción (verificar al ejecutar; si alguno falla, el error lo mostrará):
 - StockSKUTienda tiene al menos SKUID, TiendaID, StockSistema, StockReservado
   y cualquier otra columna es nullable o tiene DEFAULT.
 - FactMovimientoInventario acepta INGRESO con CantidadEsperada,
   CantidadRecibida, Discrepancia y MotivoID en NULL cuando Origen no es
   RECEPCION_CD (según CK_MovInventario_CamposRecepcion).
===============================================================================
*/

USE OrigenDB;
GO

-- =============================================================================
-- BATCH 1 — SIEMBRA (transaccional: todo o nada)
-- =============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRY
    -- ---- Prerrequisitos: datos maestros presentes --------------------------
    IF NOT EXISTS (SELECT 1 FROM dbo.DimSKU) OR NOT EXISTS (SELECT 1 FROM dbo.DimTienda)
        THROW 51100, N'DimSKU y/o DimTienda vacías. Ejecutar antes 01_datos_maestros.sql.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.DimFecha WHERE FechaID = 20260101)
        THROW 51101, N'DimFecha no contiene FechaID 20260101. Ejecutar antes 01_datos_maestros.sql.', 1;

    -- ---- Definición del stock inicial (única fuente de estas cantidades) ---
    DECLARE @Ingresos TABLE
    (
        CodigoSKU    NVARCHAR(10)  NOT NULL,
        NombreTienda NVARCHAR(100) NOT NULL,
        Cantidad     INT           NOT NULL
    );

    INSERT INTO @Ingresos (CodigoSKU, NombreTienda, Cantidad) VALUES
        (N'A10001', N'Jockey Plaza',           10),
        (N'A10001', N'Real Plaza Arequipa',     4),
        (N'A30001', N'Real Plaza Arequipa',     3),
        (N'A30002', N'Real Plaza Arequipa',     1),
        (N'A40001', N'Mall Aventura Trujillo',  2);

    -- Cada fila debe resolver a un SKU y una tienda reales; si un nombre no
    -- coincide, falla aquí en lugar de sembrar menos de lo acordado.
    IF (SELECT COUNT(*)
        FROM @Ingresos i
        INNER JOIN dbo.DimSKU    sk ON sk.CodigoSKU    = i.CodigoSKU
        INNER JOIN dbo.DimTienda t  ON t.NombreTienda  = i.NombreTienda) <> 5
        THROW 51102, N'Alguno de los 5 ingresos iniciales no resuelve a un SKU/Tienda existente. Revisar códigos y nombres.', 1;

    BEGIN TRANSACTION;

    -- ---- Paso 1: filas base 0/0 (56 = 14 SKU x 4 tiendas) ------------------
    INSERT INTO dbo.StockSKUTienda (SKUID, TiendaID, StockSistema, StockReservado)
    SELECT sk.SKUID, t.TiendaID, 0, 0
    FROM dbo.DimSKU sk
    CROSS JOIN dbo.DimTienda t
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.StockSKUTienda s
        WHERE s.SKUID = sk.SKUID AND s.TiendaID = t.TiendaID
    );

    -- ---- Paso 2: stock inicial vía ledger (el trigger actualiza el resumen) -
    INSERT INTO dbo.FactMovimientoInventario
        (SKUID, TiendaID, FechaID, FechaHora, TipoMovimiento, Origen, Cantidad, LineaID)
    SELECT
        sk.SKUID,
        t.TiendaID,
        20260101,
        CAST('2026-01-01T00:00:00' AS DATETIME2(0)),
        N'INGRESO',
        N'CONFIGURACION_INICIAL',
        i.Cantidad,
        NULL
    FROM @Ingresos i
    INNER JOIN dbo.DimSKU    sk ON sk.CodigoSKU   = i.CodigoSKU
    INNER JOIN dbo.DimTienda t  ON t.NombreTienda = i.NombreTienda
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.FactMovimientoInventario m
        WHERE m.SKUID          = sk.SKUID
          AND m.TiendaID       = t.TiendaID
          AND m.TipoMovimiento = N'INGRESO'
          AND m.Origen         = N'CONFIGURACION_INICIAL'
    );

    COMMIT TRANSACTION;
    PRINT N'Siembra completada. Ejecutar el batch 2 (validaciones).';
END TRY
BEGIN CATCH
    -- El trigger puede haber hecho ROLLBACK por su cuenta; solo se revierte
    -- si todavía hay transacción abierta.
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH
GO

-- =============================================================================
-- BATCH 2 — VALIDACIONES (7)
-- Las validaciones 1 a 6 solo leen. La 7 abre una transacción, ejecuta
-- sp_CrearPedido y la revierte con ROLLBACK (ver nota en la validación 7).
-- =============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @V TABLE
(
    Nro        INT           NOT NULL,
    Validacion NVARCHAR(70)  NOT NULL,
    Esperado   NVARCHAR(60)  NOT NULL,
    Obtenido   NVARCHAR(120) NOT NULL,
    Resultado  VARCHAR(5)    NOT NULL
);

DECLARE @n INT;

-- ---- V1: cobertura ----------------------------------------------------------
-- Toda combinación SKU x Tienda tiene fila, y el total es 56 (14 x 4).
DECLARE @Faltantes INT, @TotalFilas INT;

SELECT @Faltantes = COUNT(*)
FROM dbo.DimSKU sk
CROSS JOIN dbo.DimTienda t
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.StockSKUTienda s
    WHERE s.SKUID = sk.SKUID AND s.TiendaID = t.TiendaID
);
SELECT @TotalFilas = COUNT(*) FROM dbo.StockSKUTienda;

INSERT INTO @V VALUES
    (1, N'Cobertura SKU x Tienda',
        N'faltantes=0; filas=56',
        CONCAT(N'faltantes=', @Faltantes, N'; filas=', @TotalFilas),
        CASE WHEN @Faltantes = 0 AND @TotalFilas = 56 THEN 'OK' ELSE 'FALLA' END);

-- ---- V2: duplicados ---------------------------------------------------------
SELECT @n = COUNT(*)
FROM (
    SELECT SKUID, TiendaID
    FROM dbo.StockSKUTienda
    GROUP BY SKUID, TiendaID
    HAVING COUNT(*) > 1
) d;

INSERT INTO @V VALUES
    (2, N'Sin duplicados SKU+Tienda', N'0', CAST(@n AS NVARCHAR(60)),
        CASE WHEN @n = 0 THEN 'OK' ELSE 'FALLA' END);

-- ---- V3: no negativos (RN-015) ---------------------------------------------
SELECT @n = COUNT(*)
FROM dbo.StockSKUTienda
WHERE StockSistema < 0 OR StockReservado < 0;

INSERT INTO @V VALUES
    (3, N'Sin stock negativo (RN-015)', N'0', CAST(@n AS NVARCHAR(60)),
        CASE WHEN @n = 0 THEN 'OK' ELSE 'FALLA' END);

-- ---- V4: reserva <= sistema -------------------------------------------------
SELECT @n = COUNT(*)
FROM dbo.StockSKUTienda
WHERE StockReservado > StockSistema;

INSERT INTO @V VALUES
    (4, N'StockReservado <= StockSistema', N'0', CAST(@n AS NVARCHAR(60)),
        CASE WHEN @n = 0 THEN 'OK' ELSE 'FALLA' END);

-- ---- V5: coherencia ledger vs StockSKUTienda -------------------------------
-- Recalcula ambos contadores desde FactMovimientoInventario con las mismas
-- reglas que el trigger y los compara contra el resumen.
;WITH L AS (
    SELECT
        SKUID,
        TiendaID,
        SUM(CASE WHEN TipoMovimiento IN (N'INGRESO', N'AJUSTE', N'DESCUENTO_DEFINITIVO')
                 THEN Cantidad ELSE 0 END) AS Sis,
        SUM(CASE WHEN TipoMovimiento IN (N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO')
                 THEN Cantidad ELSE 0 END) AS Res
    FROM dbo.FactMovimientoInventario
    GROUP BY SKUID, TiendaID
)
SELECT @n = COUNT(*)
FROM dbo.StockSKUTienda s
LEFT JOIN L ON L.SKUID = s.SKUID AND L.TiendaID = s.TiendaID
WHERE s.StockSistema   <> ISNULL(L.Sis, 0)
   OR s.StockReservado <> ISNULL(L.Res, 0);

INSERT INTO @V VALUES
    (5, N'Coherencia ledger vs StockSKUTienda', N'0 discrepancias', CAST(@n AS NVARCHAR(60)),
        CASE WHEN @n = 0 THEN 'OK' ELSE 'FALLA' END);

-- ---- V6: disponibilidad por invariantes (no por snapshot) -------------------
-- DOS capas conceptuales:
--
-- Capa A - Integridad de la siembra inicial (diseno aprobado, NO el saldo):
--   exige en FactMovimientoInventario exactamente los 5 movimientos
--   aprobados INGRESO / CONFIGURACION_INICIAL (FechaID 20260101, LineaID
--   NULL), exactamente uno por combinacion, con cantidades 10/4/3/1/2 =
--   20 unidades sembradas, sin duplicados y sin movimientos
--   CONFIGURACION_INICIAL fuera de esas 5 combinaciones.
--
-- Capa B - Disponibilidad operativa actual (derivada del ledger):
--   recalcula StockSistema/StockReservado por SKU x Tienda con las reglas
--   RN-013 (las mismas de vw_StockHistorico y trg_ActualizarStockSKUTienda):
--     StockSistema   <- INGRESO, AJUSTE, DESCUENTO_DEFINITIVO
--     StockReservado <- RESERVA, LIBERACION_RESERVA, DESCUENTO_DEFINITIVO
--   (con el signo ya almacenado en Cantidad) y lo compara contra
--   StockSKUTienda. Exige ademas: cobertura de las 56 combinaciones,
--   StockReservado <= StockSistema, Disponible = Sistema - Reservado >= 0
--   (RN-010) y sin stock negativo (RN-015).
--
-- NO exige 5 filas con stock ni 20/18 unidades disponibles: son snapshots
-- operativos variables. Siembra aprobada = 5 combinaciones / 20 unidades;
-- el saldo actual derivado de los movimientos operativos de Fase 3 se
-- muestra como valor observado (informativo), sin fijarlo como expectativa.
DECLARE @Sembrado TABLE (CodigoSKU NVARCHAR(10), NombreTienda NVARCHAR(100), Cantidad INT NOT NULL);
INSERT INTO @Sembrado VALUES
    (N'A10001', N'Jockey Plaza',           10),
    (N'A10001', N'Real Plaza Arequipa',     4),
    (N'A30001', N'Real Plaza Arequipa',     3),
    (N'A30002', N'Real Plaza Arequipa',     1),
    (N'A40001', N'Mall Aventura Trujillo',  2);

-- Capa A: la siembra aprobada existe en el ledger --------------------------------
DECLARE @CombOk INT, @ConfTotal INT, @ConfFuera INT, @UnidSembradas INT;

-- Cada una de las 5 combinaciones debe tener EXACTAMENTE 1 movimiento con las
-- condiciones aprobadas y su cantidad aprobada (una combinacion ausente,
-- mal condicionada, con cantidad distinta o duplicada resta 1 a @CombOk).
SELECT @CombOk = COUNT(*)
FROM (
    SELECT sk.CodigoSKU, t.NombreTienda, e.Cantidad AS Cant,
           COUNT(m.MovimientoID) AS N, ISNULL(SUM(m.Cantidad), 0) AS Q
    FROM @Sembrado e
    INNER JOIN dbo.DimSKU    sk ON sk.CodigoSKU   = e.CodigoSKU
    INNER JOIN dbo.DimTienda t  ON t.NombreTienda = e.NombreTienda
    LEFT  JOIN dbo.FactMovimientoInventario m
           ON m.SKUID          = sk.SKUID
          AND m.TiendaID       = t.TiendaID
          AND m.TipoMovimiento = N'INGRESO'
          AND m.Origen         = N'CONFIGURACION_INICIAL'
          AND m.FechaID        = 20260101
          AND m.LineaID        IS NULL
    GROUP BY sk.CodigoSKU, t.NombreTienda, e.Cantidad
) c
WHERE c.N = 1 AND c.Q = c.Cant;

-- Total de movimientos CONFIGURACION_INICIAL (de cualquier forma): debe ser 5.
-- Cubre duplicados y movimientos de configuracion con otra fecha/tipo/linea.
SELECT @ConfTotal = COUNT(*)
FROM dbo.FactMovimientoInventario
WHERE Origen = N'CONFIGURACION_INICIAL';

-- Ningun CONFIGURACION_INICIAL fuera de las 5 combinaciones aprobadas.
SELECT @ConfFuera = COUNT(*)
FROM dbo.FactMovimientoInventario m
WHERE m.Origen = N'CONFIGURACION_INICIAL'
  AND NOT EXISTS (
        SELECT 1
        FROM @Sembrado e
        INNER JOIN dbo.DimSKU    sk ON sk.CodigoSKU   = e.CodigoSKU
        INNER JOIN dbo.DimTienda t  ON t.NombreTienda = e.NombreTienda
        WHERE sk.SKUID = m.SKUID AND t.TiendaID = m.TiendaID);

-- Unidades sembradas bajo las condiciones aprobadas: debe ser 20.
SELECT @UnidSembradas = ISNULL(SUM(m.Cantidad), 0)
FROM dbo.FactMovimientoInventario m
INNER JOIN dbo.DimSKU    sk ON sk.SKUID   = m.SKUID
INNER JOIN dbo.DimTienda t  ON t.TiendaID = m.TiendaID
INNER JOIN @Sembrado e ON e.CodigoSKU = sk.CodigoSKU AND e.NombreTienda = t.NombreTienda
WHERE m.TipoMovimiento = N'INGRESO'
  AND m.Origen         = N'CONFIGURACION_INICIAL'
  AND m.FechaID        = 20260101
  AND m.LineaID        IS NULL;

-- Capa B: disponibilidad operativa recalculada desde el ledger -------------------
DECLARE @Disc INT, @Falt INT, @ResExcede INT, @Negativos INT, @DispNeg INT,
        @ObsComb INT, @ObsUnid INT;

-- Ledger vs resumen (mismas reglas RN-013 que V5, aqui como base de la
-- disponibilidad que despues se contrasta con RN-010/RN-015).
;WITH L AS (
    SELECT SKUID, TiendaID,
           SUM(CASE WHEN TipoMovimiento IN (N'INGRESO', N'AJUSTE', N'DESCUENTO_DEFINITIVO')
                    THEN Cantidad ELSE 0 END) AS Sis,
           SUM(CASE WHEN TipoMovimiento IN (N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO')
                    THEN Cantidad ELSE 0 END) AS Res
    FROM dbo.FactMovimientoInventario
    GROUP BY SKUID, TiendaID
)
SELECT @Disc = COUNT(*)
FROM dbo.StockSKUTienda s
FULL OUTER JOIN L ON L.SKUID = s.SKUID AND L.TiendaID = s.TiendaID
WHERE ISNULL(s.StockSistema,   -2147483647) <> ISNULL(L.Sis, 0)
   OR ISNULL(s.StockReservado, -2147483647) <> ISNULL(L.Res, 0);

-- Cobertura: las 56 combinaciones SKU x Tienda deben existir en el resumen.
SELECT @Falt = COUNT(*)
FROM dbo.DimSKU sk
CROSS JOIN dbo.DimTienda t
WHERE NOT EXISTS (
        SELECT 1 FROM dbo.StockSKUTienda s
        WHERE s.SKUID = sk.SKUID AND s.TiendaID = t.TiendaID);

-- Reglas RN-010/RN-015 sobre el resumen (igual al ledger cuando @Disc = 0)
-- + agregados observados, que se reportan como informativos.
SELECT @ResExcede = ISNULL(SUM(CASE WHEN StockReservado > StockSistema              THEN 1 ELSE 0 END), 0),
       @Negativos = ISNULL(SUM(CASE WHEN StockSistema < 0 OR StockReservado < 0    THEN 1 ELSE 0 END), 0),
       @DispNeg   = ISNULL(SUM(CASE WHEN (StockSistema - StockReservado) < 0       THEN 1 ELSE 0 END), 0),
       @ObsComb   = ISNULL(SUM(CASE WHEN (StockSistema - StockReservado) > 0       THEN 1 ELSE 0 END), 0),
       @ObsUnid   = ISNULL(SUM(StockSistema - StockReservado), 0)
FROM dbo.StockSKUTienda;

DECLARE @OkV6 BIT = CASE WHEN @CombOk = 5
                          AND @ConfTotal = 5
                          AND @ConfFuera = 0
                          AND @UnidSembradas = 20
                          AND @Disc = 0
                          AND @Falt = 0
                          AND @ResExcede = 0
                          AND @Negativos = 0
                          AND @DispNeg = 0
                     THEN 1 ELSE 0 END;

INSERT INTO @V VALUES
    (6, N'Disponibilidad: siembra aprobada (ledger) + invariantes RN-010/15',
        N'sembrado 5 comb./20 u.; ledger=resumen; RN-010/15; cob=56',
        CONCAT(N'sembrado=', @CombOk, N'/5, ', @UnidSembradas, N' u. (conf=', @ConfTotal,
               N', fuera=', @ConfFuera, N'); disc=', @Disc, N'; falt=', @Falt,
               N'; res>sis=', @ResExcede, N'; neg=', @Negativos, N'; disp<0=', @DispNeg,
               N'; observado=', @ObsComb, N' comb./', @ObsUnid, N' u.'),
        CASE WHEN @OkV6 = 1 THEN 'OK' ELSE 'FALLA' END);

-- ---- V7: compatibilidad con sp_CrearPedido, con ROLLBACK -------------------
/*
Tres llamadas dentro de UNA transacción externa que se revierte al final:
  a) A10001 @ Jockey Plaza, cant 1   -> CREADO (hay 10 disponibles).
  b) A20001 @ Jockey Plaza, cant 1   -> RECHAZADO (stock cero explícito).
  c) A10001 @ Jockey Plaza, cant 10  -> RECHAZADO (tras (a) quedan 9: prueba
     el límite exacto de RN-010, Disponible = Sistema - Reservado).

Nota sobre la lección "no envolver pruebas en transacción externa": el riesgo
existe cuando el SP lanza un error (su CATCH hace ROLLBACK de todo y con
XACT_ABORT el batch se aborta). Estos tres casos son rutas SIN error (CREADO
y RECHAZADO son resultados normales), por lo que la transacción externa
llega intacta al ROLLBACK final. Si aun así algo lanza, el CATCH lo reporta
como FALLA y limpia.

Efecto colateral inevitable: el ROLLBACK no devuelve los valores IDENTITY
consumidos, así que FactPedidoDetalle/FactHistorialEstadoLinea/
FactMovimientoInventario quedarán con huecos en sus IDs. No hay filas
residuales (se verifica abajo).
*/
DECLARE @SKU_A10001 INT, @SKU_A20001 INT, @Tienda_Jockey INT, @Cliente INT;

SELECT @SKU_A10001   = SKUID    FROM dbo.DimSKU    WHERE CodigoSKU   = N'A10001';
SELECT @SKU_A20001   = SKUID    FROM dbo.DimSKU    WHERE CodigoSKU   = N'A20001';
SELECT @Tienda_Jockey = TiendaID FROM dbo.DimTienda WHERE NombreTienda = N'Jockey Plaza';
SELECT TOP (1) @Cliente = ClienteID FROM dbo.DimCliente ORDER BY ClienteID;

DECLARE @SisAntes INT, @ResAntes INT, @SisDespues INT, @ResDespues INT;
DECLARE @ResA VARCHAR(20), @ResB VARCHAR(20), @ResC VARCHAR(20);
DECLARE @LineaA INT, @LineaB INT, @LineaC INT;
DECLARE @ResTrasA INT, @TiendaLineaB INT, @MovsLineaB INT;
DECLARE @Residuos INT, @ErrMsg NVARCHAR(200) = N'';

SELECT @SisAntes = StockSistema, @ResAntes = StockReservado
FROM dbo.StockSKUTienda
WHERE SKUID = @SKU_A10001 AND TiendaID = @Tienda_Jockey;

BEGIN TRY
    BEGIN TRANSACTION;

    EXEC dbo.sp_CrearPedido
        @PedidoID = 900001, @ClienteID = @Cliente, @SKUID = @SKU_A10001,
        @TiendaID = @Tienda_Jockey, @FechaID = 20260101, @Canal = 'despacho',
        @Cantidad = 1, @LineaID = @LineaA OUTPUT, @Resultado = @ResA OUTPUT;

    SELECT @ResTrasA = StockReservado
    FROM dbo.StockSKUTienda
    WHERE SKUID = @SKU_A10001 AND TiendaID = @Tienda_Jockey;

    EXEC dbo.sp_CrearPedido
        @PedidoID = 900002, @ClienteID = @Cliente, @SKUID = @SKU_A20001,
        @TiendaID = @Tienda_Jockey, @FechaID = 20260101, @Canal = 'despacho',
        @Cantidad = 1, @LineaID = @LineaB OUTPUT, @Resultado = @ResB OUTPUT;

    SELECT @TiendaLineaB = TiendaID FROM dbo.FactPedidoDetalle WHERE LineaID = @LineaB;
    SELECT @MovsLineaB   = COUNT(*)  FROM dbo.FactMovimientoInventario WHERE LineaID = @LineaB;

    EXEC dbo.sp_CrearPedido
        @PedidoID = 900003, @ClienteID = @Cliente, @SKUID = @SKU_A10001,
        @TiendaID = @Tienda_Jockey, @FechaID = 20260101, @Canal = 'despacho',
        @Cantidad = 10, @LineaID = @LineaC OUTPUT, @Resultado = @ResC OUTPUT;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    SET @ErrMsg = LEFT(ERROR_MESSAGE(), 200);
END CATCH

SELECT @SisDespues = StockSistema, @ResDespues = StockReservado
FROM dbo.StockSKUTienda
WHERE SKUID = @SKU_A10001 AND TiendaID = @Tienda_Jockey;

SELECT @Residuos = COUNT(*)
FROM dbo.FactPedidoDetalle
WHERE PedidoID IN (900001, 900002, 900003);

DECLARE @OkA BIT = CASE WHEN @ResA = 'CREADO'    AND @ResTrasA = @ResAntes + 1 THEN 1 ELSE 0 END;
DECLARE @OkB BIT = CASE WHEN @ResB = 'RECHAZADO' AND @TiendaLineaB IS NULL AND @MovsLineaB = 0 THEN 1 ELSE 0 END;
DECLARE @OkC BIT = CASE WHEN @ResC = 'RECHAZADO' THEN 1 ELSE 0 END;
DECLARE @OkRB BIT = CASE WHEN @SisDespues = @SisAntes AND @ResDespues = @ResAntes AND @Residuos = 0 THEN 1 ELSE 0 END;

INSERT INTO @V VALUES
    (7, N'sp_CrearPedido compatible (con ROLLBACK)',
        N'CREADO; RECHAZADO; RECHAZADO; estado restaurado',
        CONCAT(ISNULL(@ResA, N'?'), N'; ', ISNULL(@ResB, N'?'), N'; ', ISNULL(@ResC, N'?'), N'; ',
               CASE WHEN @OkRB = 1 THEN N'restaurado' ELSE N'NO restaurado' END,
               CASE WHEN @ErrMsg <> N'' THEN CONCAT(N' | ERROR: ', @ErrMsg) ELSE N'' END),
        CASE WHEN @OkA = 1 AND @OkB = 1 AND @OkC = 1 AND @OkRB = 1 AND @ErrMsg = N'' THEN 'OK' ELSE 'FALLA' END);

-- ---- Resultado -------------------------------------------------------------
SELECT Nro, Validacion, Esperado, Obtenido, Resultado
FROM @V
ORDER BY Nro;

SELECT CASE WHEN EXISTS (SELECT 1 FROM @V WHERE Resultado <> 'OK')
            THEN N'HAY VALIDACIONES EN FALLA — reportar la tabla completa antes de continuar.'
            ELSE N'7/7 validaciones OK.'
       END AS ResumenBloque3;

-- Detalle informativo: stock disponible por SKU y tienda (solo filas > 0).
SELECT sk.CodigoSKU, t.NombreTienda, s.StockSistema, s.StockReservado,
       s.StockSistema - s.StockReservado AS StockDisponible
FROM dbo.StockSKUTienda s
INNER JOIN dbo.DimSKU    sk ON sk.SKUID   = s.SKUID
INNER JOIN dbo.DimTienda t  ON t.TiendaID = s.TiendaID
WHERE s.StockSistema <> 0 OR s.StockReservado <> 0
ORDER BY sk.CodigoSKU, t.NombreTienda;
GO
