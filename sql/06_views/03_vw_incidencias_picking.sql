/*
===============================================================================
ORIGEN — Vista: vw_IncidenciasPicking
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: 03_implementacion_sql.md, sección 7 (capa de vistas analíticas);
02_modelo_de_datos.md, sección 4.4 (FactIncidencia); RN-003, RN-004,
RN-019 a RN-022 (01_procesos_y_reglas.md, sección 6).

Grano: 1 fila = 1 incidencia (PK IncidenciaID de FactIncidencia). No se
agrupa ni se concatenan incidencias: si una línea tuviera 5 incidencias,
la vista devuelve 5 filas. Todos los joins son ≤1:1 sobre claves primarias,
así que la unicidad se conserva por construcción.

ADVERTENCIA DE NOMBRE: pese al nombre histórico "Picking", la vista
conservar TODAS las incidencias de FactIncidencia, incluidas las de
recepción (TipoIncidencia = 'recepcion_incompleta'), que nacen de un
MovimientoID y traen LineaID NULL. Por eso:
- FactPedidoDetalle se une con LEFT JOIN → una incidencia de recepción NO
  desaparece; sus campos de pedido/cliente/SKU/producto/tienda quedan NULL
  (NULL esperado, no un fallo de join).
- Se expone MovimientoID para poder rastrear el origen de esas incidencias.

Tiempos (nombres del DDL real entre paréntesis):
- FechaHoraDeteccion  = FactIncidencia.FechaDeteccion (DATETIME2(0), NOT NULL)
- FechaHoraResolucion = FactIncidencia.FechaResolucion (DATETIME2(0), NULL;
  poblada solo cuando EstadoResolucion es un desenlace final — CHECK de la
  tabla: resuelta / no_resuelta).
- DuracionMinutos = DATEDIFF(MINUTE, FechaHoraDeteccion, FechaHoraResolucion)
  → NULL automáticamente si FechaHoraResolucion es NULL. No se inventa una
  resolución.
- Sin columna "severidad": el modelo no la tiene. Escalamiento sí existe
  (AreaEscaladaID + EstadoResolucion) y se expone tal cual.

Alcance (reglas explícitas):
- Sin tasas, porcentajes, % de líneas afectadas, SLA, productividad ni
  rankings: solo datos atómicos de incidencias.
- Sin clasificación de causas propia: NombreMotivo/TipoMotivo vienen de
  DimMotivo sin reinterpretar.
- FechaID y Fecha corresponden a la FECHA DE LA INCIDENCIA
  (FactIncidencia.FechaID, FK NOT NULL) — es la base para "qué periodo
  concentra incidencias" y es la única fecha disponible también para las
  incidencias de recepción (sin línea de pedido).
- Uso posterior: Power BI y Python (capa de consumo analítico).
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.vw_IncidenciasPicking', N'V') IS NOT NULL
    DROP VIEW dbo.vw_IncidenciasPicking;
GO

CREATE VIEW dbo.vw_IncidenciasPicking
AS
    SELECT
        i.IncidenciaID,
        i.TipoIncidencia,
        i.LineaID,
        i.MovimientoID,
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
        i.FechaID,
        f.Fecha,
        f.Anio,
        f.Mes,
        f.NombreMes,
        i.MotivoID,
        m.NombreMotivo,
        m.TipoMotivo,
        i.AreaAtencionID            AS AreaID,
        a.NombreArea,
        i.AreaEscaladaID,
        ae.NombreArea               AS NombreAreaEscalada,
        i.EstadoResolucion,
        i.FechaDeteccion            AS FechaHoraDeteccion,
        i.FechaResolucion           AS FechaHoraResolucion,
        DATEDIFF(MINUTE, i.FechaDeteccion, i.FechaResolucion) AS DuracionMinutos
    FROM dbo.FactIncidencia i
    INNER JOIN dbo.DimMotivo m  ON m.MotivoID   = i.MotivoID
    INNER JOIN dbo.DimArea   a  ON a.AreaID     = i.AreaAtencionID
    LEFT  JOIN dbo.DimArea   ae ON ae.AreaID    = i.AreaEscaladaID
    INNER JOIN dbo.DimFecha  f  ON f.FechaID    = i.FechaID
    LEFT  JOIN dbo.FactPedidoDetalle d ON d.LineaID = i.LineaID
    LEFT  JOIN dbo.DimCliente   c ON c.ClienteID  = d.ClienteID
    LEFT  JOIN dbo.DimSKU       s ON s.SKUID      = d.SKUID
    LEFT  JOIN dbo.DimProducto  p ON p.ProductoID = s.ProductoID
    LEFT  JOIN dbo.DimTienda    t ON t.TiendaID   = d.TiendaID;
GO

-- Verificación de existencia
SELECT
    v.name         AS Vista,
    s.name         AS Esquema,
    v.create_date  AS Creada
FROM sys.views v
JOIN sys.schemas s ON s.schema_id = v.schema_id
WHERE v.name = N'vw_IncidenciasPicking';
GO
