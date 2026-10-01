/*
===============================================================================
ORIGEN — Vista: vw_TiemposEstados
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: 03_implementacion_sql.md, sección 7 (capa de vistas analíticas);
02_modelo_de_datos.md, sección 4.2 (FactHistorialEstadoLinea).

Grano: 1 fila = 1 episodio de estado de una línea de pedido (1 registro de
FactHistorialEstadoLinea = 1 entrada de la línea a un estado). NO es una
fila por pedido ni por LineaID: una línea que pasa por 5 estados genera
5 filas.

Cálculo temporal:
- FechaEntrada  = FechaHora del episodio (registro histórico).
- FechaSalida   = LEAD(FechaHora) PARTITION BY LineaID
                  ORDER BY FechaHora, HistorialID — es decir, la entrada
                  al estado siguiente de la MISMA línea. El orden se
                  completa con HistorialID (PK, IDENTITY) para que sea
                  determinístico ante empates de FechaHora (precisión
                  DATETIME2(0) = 1 segundo).
- Para el ÚLTIMO episodio de cada línea: FechaSalida = NULL y
  DATEDIFF sobre un NULL devuelve DuracionMinutos = NULL.
  No se inventa fecha de salida para el estado vigente.
- DuracionMinutos = DATEDIFF(MINUTE, FechaEntrada, FechaSalida);
  solo tiene valor cuando existe FechaSalida (nunca negativo: la
  ordenación de LEAD lo garantiza).

La comparación se calcula en un subquery derivado SOBRE
FactHistorialEstadoLinea, ANTES de unir dimensiones: así la ventana no
depende de los joins (aunque hoy todos son 1:1) y la vista conserva
exactamente una fila por HistorialID.

Alcance (reglas explícitas):
- Sin lógica SLA, sin IncumpleSLA, sin umbrales, sin clasificación de
  cumplimiento, sin tasas ni porcentajes: solo episodios y sus tiempos.
- Los estados no se reinterpretan: NombreEstado y EsFinal vienen
  tal cual de DimEstado (NombreEstado es la clave de negocio UNIQUE de
  los 14 estados).
- DimTienda se une con LEFT JOIN: una línea nunca asignada (ej.
  Rechazado) tiene TiendaID NULL y la fila conserva NombreTienda NULL.
- FechaID y los atributos de fecha corresponden al EPISODIO
  (FactHistorialEstadoLinea.FechaID), no a la fecha del pedido: son la
  base para analizar "en qué periodo se genera el retraso".
- NombreCliente y Categoria se exponen como simples atributos de
  dimensión (ya disponibles en los joins de identificación) para poder
  agrupar tiempos por cliente/categoría sin joins extra en el
  consumidor. No son métricas calculadas.

Uso posterior: Power BI y Python (capa de consumo analítico).
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.vw_TiemposEstados', N'V') IS NOT NULL
    DROP VIEW dbo.vw_TiemposEstados;
GO

CREATE VIEW dbo.vw_TiemposEstados
AS
    SELECT
        e.HistorialID,
        e.LineaID,
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
        e.FechaID,
        f.Fecha,
        f.Anio,
        f.Mes,
        f.NombreMes,
        e.EstadoID,
        es.NombreEstado,
        es.EsFinal,
        e.FechaEntrada,
        e.FechaSalida,
        DATEDIFF(MINUTE, e.FechaEntrada, e.FechaSalida) AS DuracionMinutos
    FROM (
        SELECT
            h.HistorialID,
            h.LineaID,
            h.EstadoID,
            h.FechaID,
            h.FechaHora                       AS FechaEntrada,
            LEAD(h.FechaHora) OVER (
                PARTITION BY h.LineaID
                ORDER BY h.FechaHora, h.HistorialID
            )                                 AS FechaSalida
        FROM dbo.FactHistorialEstadoLinea h
    ) e
    INNER JOIN dbo.FactPedidoDetalle d ON d.LineaID    = e.LineaID
    INNER JOIN dbo.DimCliente        c ON c.ClienteID  = d.ClienteID
    INNER JOIN dbo.DimSKU            s ON s.SKUID      = d.SKUID
    INNER JOIN dbo.DimProducto       p ON p.ProductoID = s.ProductoID
    INNER JOIN dbo.DimFecha          f ON f.FechaID    = e.FechaID
    INNER JOIN dbo.DimEstado         es ON es.EstadoID = e.EstadoID
    LEFT  JOIN dbo.DimTienda         t ON t.TiendaID   = d.TiendaID;
GO

-- Verificación de existencia
SELECT
    v.name         AS Vista,
    s.name         AS Esquema,
    v.create_date  AS Creada
FROM sys.views v
JOIN sys.schemas s ON s.schema_id = v.schema_id
WHERE v.name = N'vw_TiemposEstados';
GO
