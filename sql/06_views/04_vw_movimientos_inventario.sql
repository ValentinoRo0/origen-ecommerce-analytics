/*
===============================================================================
ORIGEN — Vista: vw_MovimientosInventario
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: 03_implementacion_sql.md, sección 7 (capa de vistas analíticas);
02_modelo_de_datos.md, sección 4.3 (FactMovimientoInventario); RN-010 a
RN-017 (01_procesos_y_reglas.md, sección 4).

Grano: 1 fila = 1 movimiento de inventario (PK MovimientoID). El ledger
COMPLETO queda disponible: no se filtra por TipoMovimiento, Origen ni por
tener línea de pedido, y no se agrupa nada. Todos los joins son ≤1:1 sobre
claves primarias → unicidad por construcción.

Alcance (reglas explícitas):
- SOLO representa el ledger. NO calcula stock histórico, stock disponible,
  stock reservado, diferencias sistema/físico, tasas, porcentajes, SLA ni
  campaign readiness. La reconstrucción de stock en el tiempo es
  responsabilidad de vw_StockHistorico (futura).
- Cantidad se expone EXACTAMENTE con el signo almacenado (RN-013:
  INGRESO > 0, RESERVA > 0, LIBERACION_RESERVA < 0, DESCUENTO_DEFINITIVO < 0,
  AJUSTE con signo libre según conteo). No se recodifica ni se normaliza:
  la convención del ledger queda visible tal cual. Tampoco se añade ninguna
  columna derivada de efecto/interpretación: eso sería una regla de negocio
  nueva.
- SIN clasificación de "recepción incompleta": la vista expone los datos
  crudos con los que se construirá esa lógica después (Origen,
  CantidadEsperada, CantidadRecibida, Discrepancia — los 3 rellenos solo
  cuando Origen = RECEPCION_CD, garantido por CHECK en la tabla).
- Relación con el pedido: LEFT JOIN FactPedidoDetalle por LineaID (FK
  anulable: INGRESO de recepción, AJUSTE y CONTEO_FISICO no tienen línea).
  Un movimiento NUNCA desaparece por no tener LineaID; PedidoID queda NULL
  en ese caso (NULL esperado).
- Motivo: LEFT JOIN DimMotivo porque MotivoID es anulable (solo poblado
  para AJUSTE). Sin filtro de TipoMotivo: se expone el valor real del
  modelo; las inconsistencias se detectan en pruebas, no se silencian.
- Tienda y Fecha: INNER JOIN (FK NOT NULL en FactMovimientoInventario).
- FactIncidencia se revisó: su FK inversa MovimientoID existe, pero no se
  expone aquí (agregar un conteo de incidencias añadiría agregación al
  grano de ledger); MovimientoID está disponible para que el consumidor
  relacione si lo necesita.
- Uso posterior: Power BI y Python (capa de consumo analítico).
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.vw_MovimientosInventario', N'V') IS NOT NULL
    DROP VIEW dbo.vw_MovimientosInventario;
GO

CREATE VIEW dbo.vw_MovimientosInventario
AS
    SELECT
        m.MovimientoID,
        m.SKUID,
        s.CodigoSKU,
        s.ProductoID,
        p.NombreProducto,
        p.Categoria,
        m.TiendaID,
        t.NombreTienda,
        m.FechaID,
        f.Fecha,
        f.Anio,
        f.Mes,
        f.NombreMes,
        m.TipoMovimiento,
        m.Origen,
        m.Cantidad,
        m.FechaHora,
        m.LineaID,
        d.PedidoID,
        m.MotivoID,
        mo.NombreMotivo,
        mo.TipoMotivo,
        m.CantidadEsperada,
        m.CantidadRecibida,
        m.Discrepancia
    FROM dbo.FactMovimientoInventario m
    INNER JOIN dbo.DimSKU       s  ON s.SKUID      = m.SKUID
    INNER JOIN dbo.DimProducto  p  ON p.ProductoID = s.ProductoID
    INNER JOIN dbo.DimTienda    t  ON t.TiendaID   = m.TiendaID
    INNER JOIN dbo.DimFecha     f  ON f.FechaID    = m.FechaID
    LEFT  JOIN dbo.DimMotivo    mo ON mo.MotivoID  = m.MotivoID
    LEFT  JOIN dbo.FactPedidoDetalle d ON d.LineaID = m.LineaID;
GO

-- Verificación de existencia
SELECT
    v.name         AS Vista,
    s.name         AS Esquema,
    v.create_date  AS Creada
FROM sys.views v
JOIN sys.schemas s ON s.schema_id = v.schema_id
WHERE v.name = N'vw_MovimientosInventario';
GO
