/*
===============================================================================
ORIGEN — Vista: vw_PedidosOperaciones
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: 03_implementacion_sql.md, sección 7 (capa de vistas analíticas);
02_modelo_de_datos.md, secciones 3 y 4.1.

Grano: 1 fila = 1 línea de pedido (FactPedidoDetalle.LineaID, PK de la
tabla). La unicidad de LineaID está garantizada por construcción:
- todas las dimensiones se unen por su clave primaria (relación 1:1);
- las incidencias se agregan con OUTER APPLY escalar, de modo que una
  línea con varias incidencias sigue devolviendo UNA sola fila.

Columnas derivadas:
- Cancelada       → 1 si el estado actual es 'Cancelado'. Se compara contra
                    DimEstado.NombreEstado, que tiene restricción UNIQUE y
                    es la clave de negocio canónica de los 14 estados
                    (01_procesos_y_reglas.md, sección 3.2); no se usa
                    EstadoActualID = <número> porque los ID son IDENTITY
                    y no son estables entre entornos.
- NIncidencias    → COUNT real de filas de FactIncidencia con esa LineaID.
- TieneIncidencia → derivado exclusivamente de NIncidencias > 0.
- TipoIncidencia /
  MotivoIncidencia → lista concatenada de valores DISTINTOS (STRING_AGG
                    sobre subconsulta con SELECT DISTINCT, ordenado). Si
                    hay varias incidencias NO se elige una arbitraria: se
                    exponen todas sin perder información.

Reglas explícitas (alcance de esta view):
- Entrega SOLO datos atómicos: no calcula tasas ni porcentajes. Power BI y
  Python calculan a partir de aquí tasa de cancelación, % de líneas con
  incidencia, comparación campaña/no campaña, distribución por tienda,
  categoría y periodo.
- Sin lógica SLA y sin lógica de Fase 4.
- NO clasifica cancelaciones como "por stock": se expone el motivo crudo
  (MotivoCancelacion) y la regla de categorización queda pendiente de
  decisión de negocio.
- DimMotivo se une sin filtrar por TipoMotivo: la corrección del tipo
  ('cancelacion') es una regla de datos que se verifica en las pruebas,
  no un supuesto del join. Un LEFT JOIN con filtro silenciaría una
  violación en lugar de detectarla.
- DimTienda se une con LEFT JOIN: una línea nunca asignada (ej. Rechazado)
  tiene TiendaID NULL, por lo que NombreTienda y Ciudad pueden ser NULL.
  Eso es un NULL esperado, no un fallo de join.

Uso posterior: Power BI y Python (capa de consumo analítico, no
transaccional).
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.vw_PedidosOperaciones', N'V') IS NOT NULL
    DROP VIEW dbo.vw_PedidosOperaciones;
GO

CREATE VIEW dbo.vw_PedidosOperaciones
AS
    SELECT
        d.LineaID,
        d.PedidoID,
        d.ClienteID,
        c.NombreCliente,
        d.SKUID,
        s.CodigoSKU,
        p.NombreProducto,
        p.Categoria,
        d.TiendaID,
        t.NombreTienda,
        t.Ciudad,
        d.FechaID,
        f.Fecha,
        f.Anio,
        f.Mes,
        f.NombreMes,
        f.EsCampania,
        f.NombreCampania,
        d.Canal,
        d.Cantidad,
        e.NombreEstado              AS EstadoActual,
        e.EsFinal,
        mc.NombreMotivo             AS MotivoCancelacion,
        CASE
            WHEN e.NombreEstado = N'Cancelado' THEN 1
            ELSE 0
        END                         AS Cancelada,
        inc.NIncidencias,
        CASE
            WHEN inc.NIncidencias > 0 THEN 1
            ELSE 0
        END                         AS TieneIncidencia,
        inc.TipoIncidencia,
        inc.MotivoIncidencia
    FROM dbo.FactPedidoDetalle d
    INNER JOIN dbo.DimCliente   c ON c.ClienteID  = d.ClienteID
    INNER JOIN dbo.DimSKU       s ON s.SKUID      = d.SKUID
    INNER JOIN dbo.DimProducto  p ON p.ProductoID = s.ProductoID
    INNER JOIN dbo.DimFecha     f ON f.FechaID    = d.FechaID
    INNER JOIN dbo.DimEstado    e ON e.EstadoID   = d.EstadoActualID
    LEFT  JOIN dbo.DimTienda    t ON t.TiendaID   = d.TiendaID
    LEFT  JOIN dbo.DimMotivo    mc ON mc.MotivoID = d.MotivoCancelacionID
    OUTER APPLY (
        SELECT
            COUNT(*)                                     AS NIncidencias,
            (
                SELECT STRING_AGG(x.TipoInc, ', ')
                         WITHIN GROUP (ORDER BY x.TipoInc)
                FROM (
                    SELECT DISTINCT i2.TipoIncidencia AS TipoInc
                    FROM dbo.FactIncidencia i2
                    WHERE i2.LineaID = d.LineaID
                ) x
            )                                             AS TipoIncidencia,
            (
                SELECT STRING_AGG(x.NomMotivo, ', ')
                         WITHIN GROUP (ORDER BY x.NomMotivo)
                FROM (
                    SELECT DISTINCT m2.NombreMotivo AS NomMotivo
                    FROM dbo.FactIncidencia i3
                    INNER JOIN dbo.DimMotivo m2 ON m2.MotivoID = i3.MotivoID
                    WHERE i3.LineaID = d.LineaID
                ) x
            )                                             AS MotivoIncidencia
        FROM dbo.FactIncidencia i
        WHERE i.LineaID = d.LineaID
    ) inc;
GO

-- Verificación de existencia
SELECT
    v.name  AS Vista,
    s.name  AS Esquema,
    v.create_date AS Creada
FROM sys.views v
JOIN sys.schemas s ON s.schema_id = v.schema_id
WHERE v.name = N'vw_PedidosOperaciones';
GO
