/*
===============================================================================
ORIGEN — Vista: vw_Devoluciones
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: 03_implementacion_sql.md, sección 7 (capa de vistas analíticas);
02_modelo_de_datos.md, sección 4.5 (FactDevolucion); RN-026 y RN-027
(01_procesos_y_reglas.md, sección 8).

Grano: 1 fila = 1 registro de FactDevolucion (PK DevolucionID). Sin
agrupaciones, sin DISTINCT, sin cantidades agregadas: todos los joins son
≤1:1 sobre claves primarias (o FK NOT NULL), así que la unicidad se
conserva por construcción.

Relaciones utilizadas (todas explícitas en el DDL):
- FactDevolucion.LineaID    → FactPedidoDetalle (FK NOT NULL) → PedidoID,
  ClienteID, SKUID, TiendaID, Cantidad de la línea original.
- FactPedidoDetalle         → DimCliente (INNER), DimSKU → DimProducto
  (INNER), DimTienda (LEFT: TiendaID es anulable en la línea).
- FactDevolucion.MotivoID   → DimMotivo (INNER, FK NOT NULL). Sin filtro
  de TipoMotivo: el modelo lo restringe a 'devolucion' mediante el
  procedimiento (no con CHECK) — se expone TipoMotivo como dato y la
  corrección se verifica en pruebas, no se silencia con un filtro.
- FactDevolucion.FechaID    → DimFecha (INNER, FK NOT NULL).

Relaciones DESCARTADAS (no existen en el modelo):
- Movimiento de inventario: FactDevolucion NO tiene FK a
  FactMovimientoInventario. El reingreso de stock por devolución es una
  pregunta abierta en la documentación; NO se infiere ninguna relación
  por SKU+tienda+fecha, cliente+producto, coincidencia temporal ni
  cantidad. Por eso la vista no expone MovimientoID/TipoMovimiento.
- No existe columna de cantidad devuelta ni de estado/tipo de devolución
  en FactDevolucion. Se expone CantidadLinea = FactPedidoDetalle.Cantidad
  (las unidades de la línea original a la que se adhiere la devolución),
  con nombre que NO afirma que sea una cantidad "devuelta" medida: esa
  columna no existe en el modelo.

Alcance (reglas explícitas):
- Vista descriptiva y de trazabilidad: sin tasas, porcentajes, KPIs, SLA,
  clasificaciones, severidades, impacto económico ni stock calculado.
- FechaID y los atributos de fecha vienen de FactDevolucion.FechaID
  (convención de las vistas anteriores); FechaDevolucion es el timestamp
  real DATETIME2(0) almacenado, sin recalcular desde él ningún atributo.
- Uso posterior: Power BI y Python (capa de consumo analítico).
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.vw_Devoluciones', N'V') IS NOT NULL
    DROP VIEW dbo.vw_Devoluciones;
GO

CREATE VIEW dbo.vw_Devoluciones
AS
    SELECT
        dv.DevolucionID,
        dv.LineaID,
        d.PedidoID,
        d.ClienteID,
        c.NombreCliente,
        d.SKUID,
        s.CodigoSKU,
        s.ProductoID,
        p.NombreProducto,
        p.Categoria,
        d.TiendaID,
        t.NombreTienda,
        t.Ciudad,
        dv.FechaID,
        f.Fecha,
        f.Anio,
        f.Mes,
        f.NombreMes,
        d.Cantidad                    AS CantidadLinea,
        dv.MotivoID,
        m.NombreMotivo,
        m.TipoMotivo,
        dv.FechaDevolucion
    FROM dbo.FactDevolucion dv
    INNER JOIN dbo.FactPedidoDetalle d ON d.LineaID   = dv.LineaID
    INNER JOIN dbo.DimCliente        c ON c.ClienteID = d.ClienteID
    INNER JOIN dbo.DimSKU            s ON s.SKUID     = d.SKUID
    INNER JOIN dbo.DimProducto       p ON p.ProductoID = s.ProductoID
    LEFT  JOIN dbo.DimTienda         t ON t.TiendaID  = d.TiendaID
    INNER JOIN dbo.DimFecha          f ON f.FechaID   = dv.FechaID
    INNER JOIN dbo.DimMotivo         m ON m.MotivoID  = dv.MotivoID;
GO

-- Verificación de existencia
SELECT
    v.name         AS Vista,
    s.name         AS Esquema,
    v.create_date  AS Creada
FROM sys.views v
JOIN sys.schemas s ON s.schema_id = v.schema_id
WHERE v.name = N'vw_Devoluciones';
GO
