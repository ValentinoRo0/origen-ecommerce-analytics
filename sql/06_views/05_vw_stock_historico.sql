/*
===============================================================================
ORIGEN — Vista: vw_StockHistorico
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: 03_implementacion_sql.md, sección 7 (capa de vistas analíticas);
02_modelo_de_datos.md, sección 4.3; RN-010 a RN-015 (01_procesos_y_reglas.md,
sección 4).

Objetivo: reconstruir el stock histórico DIARIO a partir del ledger
(FactMovimientoInventario). StockSKUTienda NO aparece en esta definición:
es un snapshot del estado actual y usarlo aquí destruiría el propósito de
reconstrucción. Solo se consulta fuera, para reconciliar el último día.

Grano: 1 fila = SKUID x TiendaID x FechaID, serie DIARIA DENSA. Se genera
con DimSKU x DimTienda x DimFecha (CROSS JOIN) y se le hacen LEFT JOIN los
movimientos diarios: si un día no hubo movimiento, los movimientos valen 0
y el acumulado conserva el día anterior.

Rango de fechas: DimFecha completo (2026-01-01 a 2026-03-31, 90 dias) —
ese ES el rango operativo del seed: el INGRESO de CONFIGURACION_INICIAL
cae en su primer día (FechaID 20260101) y todo el dato del seed vive
dentro. No se inventa fecha inicial propia: la reconstrucción arranca
acumulando desde ese primer ingreso (0 antes = sin datos, no un stock
inventado).

Formula (convenio de signos RN-013, SIN convertir signos, SIN ABS, SIN
"correcciones"):
- MovimientoStockSistema  = suma de Cantidad de INGRESO, AJUSTE y
  DESCUENTO_DEFINITIVO del día (los tres afectan StockSistema; el ledger
  ya guarda el signo correcto: INGRESO > 0, DESCUENTO < 0, AJUSTE con
  signo libre).
- MovimientoStockReservado = suma de Cantidad de RESERVA,
  LIBERACION_RESERVA y DESCUENTO_DEFINITIVO del día (RESERVA > 0,
  LIBERACION_RESERVA < 0, DESCUENTO_DEFINITIVO < 0). DESCUENTO_DEFINITIVO
  afecta AMBOS contadores: es la regla de RN-013 (docs/01:208 "−/−"),
  idéntica a la de trg_ActualizarStockSKUTienda (03_actualizar_stock_
  sku_tienda.sql:66-73) y a la de 03_sp_confirmar_picking.sql:111 —
  convierte la reserva en salida real, retirándola de sistema Y de
  reservado.
- StockSistema  = SUMA ACUMULADA diaria de MovimientoStockSistema
  (window ORDER BY FechaID, ROWS UNBOUNDED PRECEDING, partición
  SKUID+TiendaID).
- StockReservado = SUMA ACUMULADA diaria de MovimientoStockReservado.
- StockDisponible = StockSistema - StockReservado (RN-010; nada más).

Reglas explícitas:
- Stock negativo NO se oculta ni se corrige: si el ledger lo produce,
  queda visible (CASE ... < 0 THEN 0 prohibido).
- Los movimientos de un mismo día se agregan ANTES del acumulado (serie
  diaria, no por movimiento).
- Sin métricas de negocio: solo movimientos diarios y stocks acumulados.
- Uso posterior: Power BI y Python (capa de consumo analítico).
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.vw_StockHistorico', N'V') IS NOT NULL
    DROP VIEW dbo.vw_StockHistorico;
GO

CREATE VIEW dbo.vw_StockHistorico
AS
    WITH mov_diarios AS (
        -- Agrega los movimientos del día por SKU/tienda ANTES del acumulado.
        -- La clasificación por TipoMovimiento hacia cada contador es
        -- exactamente la regla RN-013 / trg_ActualizarEstadoActual:
        -- no se recalcula nada, solo se suma el Cantidad ya firmado.
        SELECT
            m.SKUID,
            m.TiendaID,
            m.FechaID,
            SUM(CASE
                    WHEN m.TipoMovimiento IN (N'INGRESO', N'AJUSTE', N'DESCUENTO_DEFINITIVO')
                    THEN m.Cantidad
                    ELSE 0
                END) AS MovimientoStockSistema,
            SUM(CASE
                    WHEN m.TipoMovimiento IN (N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO')
                    THEN m.Cantidad
                    ELSE 0
                END) AS MovimientoStockReservado
        FROM dbo.FactMovimientoInventario m
        GROUP BY m.SKUID, m.TiendaID, m.FechaID
    ),
    grilla AS (
        -- Serie diaria densa: SKU x Tienda x Fecha (DimFecha = rango seed)
        SELECT
            s.SKUID,
            t.TiendaID,
            f.FechaID
        FROM dbo.DimSKU s
        CROSS JOIN dbo.DimTienda t
        CROSS JOIN dbo.DimFecha f
    ),
    acumulado AS (
        SELECT
            g.SKUID,
            g.TiendaID,
            g.FechaID,
            ISNULL(d.MovimientoStockSistema, 0)  AS MovimientoStockSistema,
            ISNULL(d.MovimientoStockReservado, 0) AS MovimientoStockReservado,
            SUM(ISNULL(d.MovimientoStockSistema, 0)) OVER (
                PARTITION BY g.SKUID, g.TiendaID
                ORDER BY g.FechaID
                ROWS UNBOUNDED PRECEDING
            ) AS StockSistema,
            SUM(ISNULL(d.MovimientoStockReservado, 0)) OVER (
                PARTITION BY g.SKUID, g.TiendaID
                ORDER BY g.FechaID
                ROWS UNBOUNDED PRECEDING
            ) AS StockReservado
        FROM grilla g
        LEFT JOIN mov_diarios d
               ON d.SKUID    = g.SKUID
              AND d.TiendaID = g.TiendaID
              AND d.FechaID  = g.FechaID
    )
    SELECT
        f.FechaID,
        f.Fecha,
        f.Anio,
        f.Mes,
        f.NombreMes,
        a.SKUID,
        s.CodigoSKU,
        s.ProductoID,
        p.NombreProducto,
        p.Categoria,
        a.TiendaID,
        t.NombreTienda,
        a.MovimientoStockSistema,
        a.MovimientoStockReservado,
        a.StockSistema,
        a.StockReservado,
        a.StockSistema - a.StockReservado AS StockDisponible
    FROM acumulado a
    INNER JOIN dbo.DimFecha    f ON f.FechaID  = a.FechaID
    INNER JOIN dbo.DimSKU      s ON s.SKUID    = a.SKUID
    INNER JOIN dbo.DimProducto p ON p.ProductoID = s.ProductoID
    INNER JOIN dbo.DimTienda   t ON t.TiendaID = a.TiendaID;
GO

-- Verificación de existencia
SELECT
    v.name         AS Vista,
    s.name         AS Esquema,
    v.create_date  AS Creada
FROM sys.views v
JOIN sys.schemas s ON s.schema_id = v.schema_id
WHERE v.name = N'vw_StockHistorico';
GO
