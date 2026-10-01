/*
===============================================================================
ORIGEN — Test: test_vistas.sql
Fase 3 — Batería de regresión de SOLO LECTURA de la capa analítica (6 vistas)
===============================================================================
Objetivo: validar las 6 vistas de sql/06_views/:
  vw_PedidosOperaciones, vw_TiemposEstados, vw_IncidenciasPicking,
  vw_MovimientosInventario, vw_StockHistorico, vw_Devoluciones.

Garantía de solo lectura:
- Única sentencia de datos: SELECT / CTE / subconsultas / JOIN / UNION ALL.
- El script no contiene ninguna sentencia de escritura (ni DML que modifique
  datos, ni definición de esquema que altere objetos) ni invocación de
  procedimientos: no se crea ninguna tabla auxiliar; los resultados se
  construyen en la propia consulta (CTE "Tests").
  (Tampoco aparecen esas sentencias ni siquiera comentadas: basta con
  comprobarlo con una búsqueda de palabras clave del script.)

Formato de salida (columnas fijas en todas las secciones):
  Seccion | TestID | Vista | Validacion | Esperado | Obtenido | Estado
  Estado = PASS | FAIL. Nunca se ocultan los valores reales.

Pruebas (60):
  T01-T06   Existencia de las 6 vistas (OBJECT_ID en catálogo)
  T07-T14   vw_PedidosOperaciones (grano LineaID, correspondencia con base,
            campos derivados, incidencias, cancelación)
  T15-T23   vw_TiemposEstados (grano HistorialID, FechaEntrada/LEAD,
            duraciones, último episodio)
  T24-T33   vw_IncidenciasPicking (grano IncidenciaID, motivo/área/fecha,
            duración, LineaID opcional)
  T34-T44   vw_MovimientosInventario (grano MovimientoID, dimensiones,
            línea/pedido, recepción, agregado Tipo+Origen sin tocar signos)
  T45-T53   vw_StockHistorico (conteo desde dimensiones, densidad, movimientos
            diarios y acumulados RN-013, disponible, negativos,
            reconciliación con StockSKUTienda con MAX(DimFecha) independiente,
            caso SKU 4/Tienda 6)
  T54-T59   vw_Devoluciones (grano DevolucionID; base con 0 filas → 0/0 PASS)
  T60       Duplicados globales (suma de los 6 granos)

Secciones de salida: TEST (60 filas), RESUMEN (por vista), TOTAL, GLOBAL,
MENSAJE y FALLO (esta última solo aporta filas cuando hay fallos: 0 filas si
todo pasa).

Nota de datos: T53 fija el caso actual del seed (SKU4/T6 = 8/0/8 al último
día). Es una prueba de regla dura del seed actual; cuando Fase 4 cargue
nuevos datos este valor puntual deberá actualizarse (el resto del test no
depende de él: T52 es la reconciliación general).
===============================================================================
*/

USE OrigenDB;
GO

SET NOCOUNT ON;

WITH Tests AS (
    -- ========================================================================
    -- SECCIÓN 2 — Existencia de las 6 vistas (T01-T06)
    -- ========================================================================
    SELECT N'TEST' AS Seccion, N'T01' AS TestID, N'vw_PedidosOperaciones' AS Vista,
           N'Existencia en catalogo (OBJECT_ID V)' AS Validacion, N'1' AS Esperado,
           CAST(CASE WHEN OBJECT_ID(N'dbo.vw_PedidosOperaciones', N'V') IS NOT NULL THEN 1 ELSE 0 END AS NVARCHAR(10)) AS Obtenido,
           CASE WHEN OBJECT_ID(N'dbo.vw_PedidosOperaciones', N'V') IS NOT NULL THEN N'PASS' ELSE N'FAIL' END AS Estado
    UNION ALL
    SELECT N'TEST', N'T02', N'vw_TiemposEstados', N'Existencia en catalogo (OBJECT_ID V)', N'1',
           CAST(CASE WHEN OBJECT_ID(N'dbo.vw_TiemposEstados', N'V') IS NOT NULL THEN 1 ELSE 0 END AS NVARCHAR(10)),
           CASE WHEN OBJECT_ID(N'dbo.vw_TiemposEstados', N'V') IS NOT NULL THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T03', N'vw_IncidenciasPicking', N'Existencia en catalogo (OBJECT_ID V)', N'1',
           CAST(CASE WHEN OBJECT_ID(N'dbo.vw_IncidenciasPicking', N'V') IS NOT NULL THEN 1 ELSE 0 END AS NVARCHAR(10)),
           CASE WHEN OBJECT_ID(N'dbo.vw_IncidenciasPicking', N'V') IS NOT NULL THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T04', N'vw_MovimientosInventario', N'Existencia en catalogo (OBJECT_ID V)', N'1',
           CAST(CASE WHEN OBJECT_ID(N'dbo.vw_MovimientosInventario', N'V') IS NOT NULL THEN 1 ELSE 0 END AS NVARCHAR(10)),
           CASE WHEN OBJECT_ID(N'dbo.vw_MovimientosInventario', N'V') IS NOT NULL THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T05', N'vw_StockHistorico', N'Existencia en catalogo (OBJECT_ID V)', N'1',
           CAST(CASE WHEN OBJECT_ID(N'dbo.vw_StockHistorico', N'V') IS NOT NULL THEN 1 ELSE 0 END AS NVARCHAR(10)),
           CASE WHEN OBJECT_ID(N'dbo.vw_StockHistorico', N'V') IS NOT NULL THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T06', N'vw_Devoluciones', N'Existencia en catalogo (OBJECT_ID V)', N'1',
           CAST(CASE WHEN OBJECT_ID(N'dbo.vw_Devoluciones', N'V') IS NOT NULL THEN 1 ELSE 0 END AS NVARCHAR(10)),
           CASE WHEN OBJECT_ID(N'dbo.vw_Devoluciones', N'V') IS NOT NULL THEN N'PASS' ELSE N'FAIL' END

    -- ========================================================================
    -- SECCIÓN 3 — vw_PedidosOperaciones (T07-T14)
    -- ========================================================================
    UNION ALL
    SELECT N'TEST', N'T07', N'vw_PedidosOperaciones', N'Grano: COUNT(*) = COUNT(DISTINCT LineaID)',
           N'iguales',
           CAST((SELECT COUNT(*) FROM dbo.vw_PedidosOperaciones) AS NVARCHAR(20)) + N' / '
           + CAST((SELECT COUNT(DISTINCT LineaID) FROM dbo.vw_PedidosOperaciones) AS NVARCHAR(20)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_PedidosOperaciones)
                   = (SELECT COUNT(DISTINCT LineaID) FROM dbo.vw_PedidosOperaciones)
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T08', N'vw_PedidosOperaciones', N'Duplicados por LineaID', N'0',
           CAST((SELECT COUNT(*) FROM (SELECT LineaID FROM dbo.vw_PedidosOperaciones GROUP BY LineaID HAVING COUNT(*) > 1) d) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM (SELECT LineaID FROM dbo.vw_PedidosOperaciones GROUP BY LineaID HAVING COUNT(*) > 1) d) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T09', N'vw_PedidosOperaciones', N'LineaID de FactPedidoDetalle ausentes en la vista', N'0',
           CAST((SELECT COUNT(*) FROM dbo.FactPedidoDetalle d LEFT JOIN dbo.vw_PedidosOperaciones v ON v.LineaID = d.LineaID WHERE v.LineaID IS NULL) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.FactPedidoDetalle d LEFT JOIN dbo.vw_PedidosOperaciones v ON v.LineaID = d.LineaID WHERE v.LineaID IS NULL) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T10', N'vw_PedidosOperaciones', N'LineaID en la vista inexistentes en base', N'0',
           CAST((SELECT COUNT(*) FROM dbo.vw_PedidosOperaciones v LEFT JOIN dbo.FactPedidoDetalle d ON d.LineaID = v.LineaID WHERE d.LineaID IS NULL) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_PedidosOperaciones v LEFT JOIN dbo.FactPedidoDetalle d ON d.LineaID = v.LineaID WHERE d.LineaID IS NULL) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T11', N'vw_PedidosOperaciones', N'Campos derivados vs base + DimEstado (PedidoID, ClienteID, SKUID, TiendaID, FechaID, Cantidad, EstadoActual)', N'0 mismatches',
           CAST((SELECT COUNT(*)
                 FROM dbo.FactPedidoDetalle d
                 JOIN dbo.vw_PedidosOperaciones v ON v.LineaID = d.LineaID
                 JOIN dbo.DimEstado e ON e.EstadoID = d.EstadoActualID
                 WHERE v.PedidoID <> d.PedidoID
                    OR v.ClienteID <> d.ClienteID
                    OR v.SKUID <> d.SKUID
                    OR ISNULL(v.TiendaID, -1) <> ISNULL(d.TiendaID, -1)
                    OR v.FechaID <> d.FechaID
                    OR v.Cantidad <> d.Cantidad
                    OR ISNULL(v.EstadoActual, N'~') <> ISNULL(e.NombreEstado, N'~')) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*)
                 FROM dbo.FactPedidoDetalle d
                 JOIN dbo.vw_PedidosOperaciones v ON v.LineaID = d.LineaID
                 JOIN dbo.DimEstado e ON e.EstadoID = d.EstadoActualID
                 WHERE v.PedidoID <> d.PedidoID
                    OR v.ClienteID <> d.ClienteID
                    OR v.SKUID <> d.SKUID
                    OR ISNULL(v.TiendaID, -1) <> ISNULL(d.TiendaID, -1)
                    OR v.FechaID <> d.FechaID
                    OR v.Cantidad <> d.Cantidad
                    OR ISNULL(v.EstadoActual, N'~') <> ISNULL(e.NombreEstado, N'~')) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T12', N'vw_PedidosOperaciones', N'NIncidencias vs conteo independiente de FactIncidencia por LineaID', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_PedidosOperaciones v
                 WHERE v.NIncidencias <> (SELECT COUNT(*) FROM dbo.FactIncidencia i WHERE i.LineaID = v.LineaID)) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_PedidosOperaciones v
                 WHERE v.NIncidencias <> (SELECT COUNT(*) FROM dbo.FactIncidencia i WHERE i.LineaID = v.LineaID)) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T13', N'vw_PedidosOperaciones', N'TieneIncidencia coherente con NIncidencias > 0', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_PedidosOperaciones v
                 WHERE v.TieneIncidencia <> CASE WHEN v.NIncidencias > 0 THEN 1 ELSE 0 END) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_PedidosOperaciones v
                 WHERE v.TieneIncidencia <> CASE WHEN v.NIncidencias > 0 THEN 1 ELSE 0 END) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T14', N'vw_PedidosOperaciones', N'Cancelada coherente con el estado real (DimEstado.NombreEstado = Cancelado)', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_PedidosOperaciones v
                 JOIN dbo.FactPedidoDetalle d ON d.LineaID = v.LineaID
                 JOIN dbo.DimEstado e ON e.EstadoID = d.EstadoActualID
                 WHERE v.Cancelada <> CASE WHEN e.NombreEstado = N'Cancelado' THEN 1 ELSE 0 END) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_PedidosOperaciones v
                 JOIN dbo.FactPedidoDetalle d ON d.LineaID = v.LineaID
                 JOIN dbo.DimEstado e ON e.EstadoID = d.EstadoActualID
                 WHERE v.Cancelada <> CASE WHEN e.NombreEstado = N'Cancelado' THEN 1 ELSE 0 END) = 0
                THEN N'PASS' ELSE N'FAIL' END

    -- ========================================================================
    -- SECCIÓN 4 — vw_TiemposEstados (T15-T23)
    -- ========================================================================
    UNION ALL
    SELECT N'TEST', N'T15', N'vw_TiemposEstados', N'Grano: COUNT(*) vista vs FactHistorialEstadoLinea', N'iguales',
           CAST((SELECT COUNT(*) FROM dbo.vw_TiemposEstados) AS NVARCHAR(20)) + N' / '
           + CAST((SELECT COUNT(*) FROM dbo.FactHistorialEstadoLinea) AS NVARCHAR(20)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_TiemposEstados)
                   = (SELECT COUNT(*) FROM dbo.FactHistorialEstadoLinea)
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T16', N'vw_TiemposEstados', N'HistorialID duplicados', N'0',
           CAST((SELECT COUNT(*) FROM (SELECT HistorialID FROM dbo.vw_TiemposEstados GROUP BY HistorialID HAVING COUNT(*) > 1) d) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM (SELECT HistorialID FROM dbo.vw_TiemposEstados GROUP BY HistorialID HAVING COUNT(*) > 1) d) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T17', N'vw_TiemposEstados', N'HistorialID de base ausentes en la vista', N'0',
           CAST((SELECT COUNT(*) FROM dbo.FactHistorialEstadoLinea h LEFT JOIN dbo.vw_TiemposEstados v ON v.HistorialID = h.HistorialID WHERE v.HistorialID IS NULL) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.FactHistorialEstadoLinea h LEFT JOIN dbo.vw_TiemposEstados v ON v.HistorialID = h.HistorialID WHERE v.HistorialID IS NULL) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T18', N'vw_TiemposEstados', N'HistorialID en la vista inexistentes en base', N'0',
           CAST((SELECT COUNT(*) FROM dbo.vw_TiemposEstados v LEFT JOIN dbo.FactHistorialEstadoLinea h ON h.HistorialID = v.HistorialID WHERE h.HistorialID IS NULL) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_TiemposEstados v LEFT JOIN dbo.FactHistorialEstadoLinea h ON h.HistorialID = v.HistorialID WHERE h.HistorialID IS NULL) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T19', N'vw_TiemposEstados', N'FechaEntrada = FactHistorialEstadoLinea.FechaHora', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.FactHistorialEstadoLinea h
                 JOIN dbo.vw_TiemposEstados v ON v.HistorialID = h.HistorialID
                 WHERE ISNULL(v.FechaEntrada, '19000101') <> h.FechaHora) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.FactHistorialEstadoLinea h
                 JOIN dbo.vw_TiemposEstados v ON v.HistorialID = h.HistorialID
                 WHERE ISNULL(v.FechaEntrada, '19000101') <> h.FechaHora) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T20', N'vw_TiemposEstados', N'FechaSalida = LEAD(FechaHora) independiente (FechaHora, HistorialID)', N'0 mismatches',
           CAST((SELECT COUNT(*)
                 FROM (SELECT HistorialID, LineaID, FechaHora,
                              LEAD(FechaHora) OVER (PARTITION BY LineaID ORDER BY FechaHora, HistorialID) AS SigFecha
                       FROM dbo.FactHistorialEstadoLinea) b
                 JOIN dbo.vw_TiemposEstados v ON v.HistorialID = b.HistorialID
                 WHERE ISNULL(v.FechaSalida, '19000101') <> ISNULL(b.SigFecha, '19000101')) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*)
                 FROM (SELECT HistorialID, LineaID, FechaHora,
                              LEAD(FechaHora) OVER (PARTITION BY LineaID ORDER BY FechaHora, HistorialID) AS SigFecha
                       FROM dbo.FactHistorialEstadoLinea) b
                 JOIN dbo.vw_TiemposEstados v ON v.HistorialID = b.HistorialID
                 WHERE ISNULL(v.FechaSalida, '19000101') <> ISNULL(b.SigFecha, '19000101')) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T21', N'vw_TiemposEstados', N'DuracionMinutos = DATEDIFF(MINUTE) independiente sobre la base', N'0 mismatches',
           CAST((SELECT COUNT(*)
                 FROM (SELECT HistorialID, LineaID, FechaHora,
                              LEAD(FechaHora) OVER (PARTITION BY LineaID ORDER BY FechaHora, HistorialID) AS SigFecha
                       FROM dbo.FactHistorialEstadoLinea) b
                 JOIN dbo.vw_TiemposEstados v ON v.HistorialID = b.HistorialID
                 WHERE ISNULL(v.DuracionMinutos, -1) <> ISNULL(DATEDIFF(MINUTE, b.FechaHora, b.SigFecha), -1)) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*)
                 FROM (SELECT HistorialID, LineaID, FechaHora,
                              LEAD(FechaHora) OVER (PARTITION BY LineaID ORDER BY FechaHora, HistorialID) AS SigFecha
                       FROM dbo.FactHistorialEstadoLinea) b
                 JOIN dbo.vw_TiemposEstados v ON v.HistorialID = b.HistorialID
                 WHERE ISNULL(v.DuracionMinutos, -1) <> ISNULL(DATEDIFF(MINUTE, b.FechaHora, b.SigFecha), -1)) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T22', N'vw_TiemposEstados', N'Duraciones negativas', N'0',
           CAST((SELECT COUNT(*) FROM dbo.vw_TiemposEstados WHERE DuracionMinutos IS NOT NULL AND DuracionMinutos < 0) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_TiemposEstados WHERE DuracionMinutos IS NOT NULL AND DuracionMinutos < 0) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T23', N'vw_TiemposEstados', N'Ultimo episodio de cada linea con FechaSalida/Duracion NULL (y solo ese)', N'0 inconsistencias',
           CAST((SELECT COUNT(*)
                 FROM (SELECT HistorialID, LineaID, FechaHora,
                              LEAD(FechaHora) OVER (PARTITION BY LineaID ORDER BY FechaHora, HistorialID) AS SigFecha
                       FROM dbo.FactHistorialEstadoLinea) b
                 JOIN dbo.vw_TiemposEstados v ON v.HistorialID = b.HistorialID
                 WHERE (b.SigFecha IS NULL AND (v.FechaSalida IS NOT NULL OR v.DuracionMinutos IS NOT NULL))
                    OR (b.SigFecha IS NOT NULL AND v.FechaSalida IS NULL)) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*)
                 FROM (SELECT HistorialID, LineaID, FechaHora,
                              LEAD(FechaHora) OVER (PARTITION BY LineaID ORDER BY FechaHora, HistorialID) AS SigFecha
                       FROM dbo.FactHistorialEstadoLinea) b
                 JOIN dbo.vw_TiemposEstados v ON v.HistorialID = b.HistorialID
                 WHERE (b.SigFecha IS NULL AND (v.FechaSalida IS NOT NULL OR v.DuracionMinutos IS NOT NULL))
                    OR (b.SigFecha IS NOT NULL AND v.FechaSalida IS NULL)) = 0
                THEN N'PASS' ELSE N'FAIL' END

    -- ========================================================================
    -- SECCIÓN 5 — vw_IncidenciasPicking (T24-T33)
    -- ========================================================================
    UNION ALL
    SELECT N'TEST', N'T24', N'vw_IncidenciasPicking', N'Grano: COUNT(*) vista vs FactIncidencia', N'iguales',
           CAST((SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking) AS NVARCHAR(20)) + N' / '
           + CAST((SELECT COUNT(*) FROM dbo.FactIncidencia) AS NVARCHAR(20)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking)
                   = (SELECT COUNT(*) FROM dbo.FactIncidencia)
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T25', N'vw_IncidenciasPicking', N'IncidenciaID duplicados', N'0',
           CAST((SELECT COUNT(*) FROM (SELECT IncidenciaID FROM dbo.vw_IncidenciasPicking GROUP BY IncidenciaID HAVING COUNT(*) > 1) d) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM (SELECT IncidenciaID FROM dbo.vw_IncidenciasPicking GROUP BY IncidenciaID HAVING COUNT(*) > 1) d) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T26', N'vw_IncidenciasPicking', N'Incidencias de base ausentes en la vista', N'0',
           CAST((SELECT COUNT(*) FROM dbo.FactIncidencia i LEFT JOIN dbo.vw_IncidenciasPicking v ON v.IncidenciaID = i.IncidenciaID WHERE v.IncidenciaID IS NULL) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.FactIncidencia i LEFT JOIN dbo.vw_IncidenciasPicking v ON v.IncidenciaID = i.IncidenciaID WHERE v.IncidenciaID IS NULL) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T27', N'vw_IncidenciasPicking', N'Incidencias en la vista inexistentes en base', N'0',
           CAST((SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v LEFT JOIN dbo.FactIncidencia i ON i.IncidenciaID = v.IncidenciaID WHERE i.IncidenciaID IS NULL) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v LEFT JOIN dbo.FactIncidencia i ON i.IncidenciaID = v.IncidenciaID WHERE i.IncidenciaID IS NULL) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T28', N'vw_IncidenciasPicking', N'Motivo: vs base y vs DimMotivo (MotivoID, NombreMotivo, TipoMotivo)', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.FactIncidencia i ON i.IncidenciaID = v.IncidenciaID
                 WHERE ISNULL(v.MotivoID, -1) <> ISNULL(i.MotivoID, -1))
               + (SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.DimMotivo m ON m.MotivoID = v.MotivoID
                  WHERE v.NombreMotivo <> m.NombreMotivo OR v.TipoMotivo <> m.TipoMotivo) AS NVARCHAR(10)),
           CASE WHEN ((SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.FactIncidencia i ON i.IncidenciaID = v.IncidenciaID
                 WHERE ISNULL(v.MotivoID, -1) <> ISNULL(i.MotivoID, -1))
               + (SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.DimMotivo m ON m.MotivoID = v.MotivoID
                  WHERE v.NombreMotivo <> m.NombreMotivo OR v.TipoMotivo <> m.TipoMotivo)) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T29', N'vw_IncidenciasPicking', N'Area de atencion: vs base (AreaAtencionID) y vs DimArea (NombreArea)', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.FactIncidencia i ON i.IncidenciaID = v.IncidenciaID
                 WHERE ISNULL(v.AreaID, -1) <> ISNULL(i.AreaAtencionID, -1))
               + (SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.DimArea a ON a.AreaID = v.AreaID
                  WHERE v.NombreArea <> a.NombreArea) AS NVARCHAR(10)),
           CASE WHEN ((SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.FactIncidencia i ON i.IncidenciaID = v.IncidenciaID
                 WHERE ISNULL(v.AreaID, -1) <> ISNULL(i.AreaAtencionID, -1))
               + (SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.DimArea a ON a.AreaID = v.AreaID
                  WHERE v.NombreArea <> a.NombreArea)) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T30', N'vw_IncidenciasPicking', N'Area escalada: AreaEscaladaID vs base y nombre vs DimArea (NULL permitido)', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.FactIncidencia i ON i.IncidenciaID = v.IncidenciaID
                 WHERE ISNULL(v.AreaEscaladaID, -1) <> ISNULL(i.AreaEscaladaID, -1))
               + (SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v LEFT JOIN dbo.DimArea a ON a.AreaID = v.AreaEscaladaID
                  WHERE (v.AreaEscaladaID IS NOT NULL AND (a.AreaID IS NULL OR v.NombreAreaEscalada <> a.NombreArea))
                     OR (v.AreaEscaladaID IS NULL AND v.NombreAreaEscalada IS NOT NULL)) AS NVARCHAR(10)),
           CASE WHEN ((SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.FactIncidencia i ON i.IncidenciaID = v.IncidenciaID
                 WHERE ISNULL(v.AreaEscaladaID, -1) <> ISNULL(i.AreaEscaladaID, -1))
               + (SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v LEFT JOIN dbo.DimArea a ON a.AreaID = v.AreaEscaladaID
                  WHERE (v.AreaEscaladaID IS NOT NULL AND (a.AreaID IS NULL OR v.NombreAreaEscalada <> a.NombreArea))
                     OR (v.AreaEscaladaID IS NULL AND v.NombreAreaEscalada IS NOT NULL))) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T31', N'vw_IncidenciasPicking', N'Fecha: FechaID vs base y atributos vs DimFecha', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.FactIncidencia i ON i.IncidenciaID = v.IncidenciaID
                 WHERE v.FechaID <> i.FechaID)
               + (SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.DimFecha f ON f.FechaID = v.FechaID
                  WHERE v.Fecha <> f.Fecha OR v.Anio <> f.Anio OR v.Mes <> f.Mes OR v.NombreMes <> f.NombreMes) AS NVARCHAR(10)),
           CASE WHEN ((SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.FactIncidencia i ON i.IncidenciaID = v.IncidenciaID
                 WHERE v.FechaID <> i.FechaID)
               + (SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.DimFecha f ON f.FechaID = v.FechaID
                  WHERE v.Fecha <> f.Fecha OR v.Anio <> f.Anio OR v.Mes <> f.Mes OR v.NombreMes <> f.NombreMes)) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T32', N'vw_IncidenciasPicking', N'DuracionMinutos = DATEDIFF(deteccion, resolucion) independiente', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.FactIncidencia i ON i.IncidenciaID = v.IncidenciaID
                 WHERE ISNULL(v.DuracionMinutos, -1) <> ISNULL(DATEDIFF(MINUTE, i.FechaDeteccion, i.FechaResolucion), -1)) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v JOIN dbo.FactIncidencia i ON i.IncidenciaID = v.IncidenciaID
                 WHERE ISNULL(v.DuracionMinutos, -1) <> ISNULL(DATEDIFF(MINUTE, i.FechaDeteccion, i.FechaResolucion), -1)) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T33', N'vw_IncidenciasPicking', N'LineaID (opcional): si no es NULL existe en FactPedidoDetalle', N'0 huerfanos (NULL permitido)',
           CAST((SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v
                 WHERE v.LineaID IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d WHERE d.LineaID = v.LineaID)) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_IncidenciasPicking v
                 WHERE v.LineaID IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d WHERE d.LineaID = v.LineaID)) = 0
                THEN N'PASS' ELSE N'FAIL' END

    -- ========================================================================
    -- SECCIÓN 6 — vw_MovimientosInventario (T34-T44)
    -- ========================================================================
    UNION ALL
    SELECT N'TEST', N'T34', N'vw_MovimientosInventario', N'Grano: COUNT(*) vista vs FactMovimientoInventario', N'iguales',
           CAST((SELECT COUNT(*) FROM dbo.vw_MovimientosInventario) AS NVARCHAR(20)) + N' / '
           + CAST((SELECT COUNT(*) FROM dbo.FactMovimientoInventario) AS NVARCHAR(20)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_MovimientosInventario)
                   = (SELECT COUNT(*) FROM dbo.FactMovimientoInventario)
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T35', N'vw_MovimientosInventario', N'MovimientoID duplicados', N'0',
           CAST((SELECT COUNT(*) FROM (SELECT MovimientoID FROM dbo.vw_MovimientosInventario GROUP BY MovimientoID HAVING COUNT(*) > 1) d) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM (SELECT MovimientoID FROM dbo.vw_MovimientosInventario GROUP BY MovimientoID HAVING COUNT(*) > 1) d) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T36', N'vw_MovimientosInventario', N'MovimientoID de base ausentes en la vista', N'0',
           CAST((SELECT COUNT(*) FROM dbo.FactMovimientoInventario m LEFT JOIN dbo.vw_MovimientosInventario v ON v.MovimientoID = m.MovimientoID WHERE v.MovimientoID IS NULL) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.FactMovimientoInventario m LEFT JOIN dbo.vw_MovimientosInventario v ON v.MovimientoID = m.MovimientoID WHERE v.MovimientoID IS NULL) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T37', N'vw_MovimientosInventario', N'MovimientoID en la vista inexistentes en base', N'0',
           CAST((SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v LEFT JOIN dbo.FactMovimientoInventario m ON m.MovimientoID = v.MovimientoID WHERE m.MovimientoID IS NULL) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v LEFT JOIN dbo.FactMovimientoInventario m ON m.MovimientoID = v.MovimientoID WHERE m.MovimientoID IS NULL) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T38', N'vw_MovimientosInventario', N'SKU/Producto: vs base y vs DimSKU/DimProducto', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.FactMovimientoInventario m ON m.MovimientoID = v.MovimientoID
                 WHERE v.SKUID <> m.SKUID)
               + (SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v
                  JOIN dbo.DimSKU s ON s.SKUID = v.SKUID
                  JOIN dbo.DimProducto p ON p.ProductoID = s.ProductoID
                  WHERE v.CodigoSKU <> s.CodigoSKU OR v.ProductoID <> s.ProductoID
                     OR v.NombreProducto <> p.NombreProducto OR v.Categoria <> p.Categoria) AS NVARCHAR(10)),
           CASE WHEN ((SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.FactMovimientoInventario m ON m.MovimientoID = v.MovimientoID
                 WHERE v.SKUID <> m.SKUID)
               + (SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v
                  JOIN dbo.DimSKU s ON s.SKUID = v.SKUID
                  JOIN dbo.DimProducto p ON p.ProductoID = s.ProductoID
                  WHERE v.CodigoSKU <> s.CodigoSKU OR v.ProductoID <> s.ProductoID
                     OR v.NombreProducto <> p.NombreProducto OR v.Categoria <> p.Categoria)) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T39', N'vw_MovimientosInventario', N'Tienda: vs base y vs DimTienda', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.FactMovimientoInventario m ON m.MovimientoID = v.MovimientoID
                 WHERE ISNULL(v.TiendaID, -1) <> ISNULL(m.TiendaID, -1))
               + (SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.DimTienda t ON t.TiendaID = v.TiendaID
                  WHERE v.NombreTienda <> t.NombreTienda) AS NVARCHAR(10)),
           CASE WHEN ((SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.FactMovimientoInventario m ON m.MovimientoID = v.MovimientoID
                 WHERE ISNULL(v.TiendaID, -1) <> ISNULL(m.TiendaID, -1))
               + (SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.DimTienda t ON t.TiendaID = v.TiendaID
                  WHERE v.NombreTienda <> t.NombreTienda)) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T40', N'vw_MovimientosInventario', N'Fecha: FechaID vs base y atributos vs DimFecha', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.FactMovimientoInventario m ON m.MovimientoID = v.MovimientoID
                 WHERE v.FechaID <> m.FechaID)
               + (SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.DimFecha f ON f.FechaID = v.FechaID
                  WHERE v.Fecha <> f.Fecha OR v.Anio <> f.Anio OR v.Mes <> f.Mes OR v.NombreMes <> f.NombreMes) AS NVARCHAR(10)),
           CASE WHEN ((SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.FactMovimientoInventario m ON m.MovimientoID = v.MovimientoID
                 WHERE v.FechaID <> m.FechaID)
               + (SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.DimFecha f ON f.FechaID = v.FechaID
                  WHERE v.Fecha <> f.Fecha OR v.Anio <> f.Anio OR v.Mes <> f.Mes OR v.NombreMes <> f.NombreMes)) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T41', N'vw_MovimientosInventario', N'Motivo: vs base (NULL posible) y vs DimMotivo cuando no es NULL', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.FactMovimientoInventario m ON m.MovimientoID = v.MovimientoID
                 WHERE ISNULL(v.MotivoID, -1) <> ISNULL(m.MotivoID, -1))
               + (SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.DimMotivo mo ON mo.MotivoID = v.MotivoID
                  WHERE v.NombreMotivo <> mo.NombreMotivo OR v.TipoMotivo <> mo.TipoMotivo) AS NVARCHAR(10)),
           CASE WHEN ((SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.FactMovimientoInventario m ON m.MovimientoID = v.MovimientoID
                 WHERE ISNULL(v.MotivoID, -1) <> ISNULL(m.MotivoID, -1))
               + (SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.DimMotivo mo ON mo.MotivoID = v.MotivoID
                  WHERE v.NombreMotivo <> mo.NombreMotivo OR v.TipoMotivo <> mo.TipoMotivo)) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T42', N'vw_MovimientosInventario', N'LineaID/PedidoID: si LineaID no es NULL, PedidoID corresponde a FactPedidoDetalle', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v
                 WHERE v.LineaID IS NOT NULL
                   AND (v.PedidoID IS NULL
                        OR NOT EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
                                       WHERE d.LineaID = v.LineaID AND d.PedidoID = v.PedidoID))) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v
                 WHERE v.LineaID IS NOT NULL
                   AND (v.PedidoID IS NULL
                        OR NOT EXISTS (SELECT 1 FROM dbo.FactPedidoDetalle d
                                       WHERE d.LineaID = v.LineaID AND d.PedidoID = v.PedidoID))) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T43', N'vw_MovimientosInventario', N'Campos de recepcion coherentes con la base (CantidadEsperada/Recibida/Discrepancia)', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.FactMovimientoInventario m ON m.MovimientoID = v.MovimientoID
                 WHERE ISNULL(v.CantidadEsperada, -1) <> ISNULL(m.CantidadEsperada, -1)
                    OR ISNULL(v.CantidadRecibida, -1) <> ISNULL(m.CantidadRecibida, -1)
                    OR ISNULL(v.Discrepancia, -1) <> ISNULL(m.Discrepancia, -1)) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_MovimientosInventario v JOIN dbo.FactMovimientoInventario m ON m.MovimientoID = v.MovimientoID
                 WHERE ISNULL(v.CantidadEsperada, -1) <> ISNULL(m.CantidadEsperada, -1)
                    OR ISNULL(v.CantidadRecibida, -1) <> ISNULL(m.CantidadRecibida, -1)
                    OR ISNULL(v.Discrepancia, -1) <> ISNULL(m.Discrepancia, -1)) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T44', N'vw_MovimientosInventario', N'Agregado TipoMovimiento+Origen (COUNT y SUM(Cantidad) con signo, sin ABS)', N'0 mismatches',
           CAST((SELECT COUNT(*)
                 FROM (SELECT TipoMovimiento, Origen, COUNT(*) AS N, SUM(Cantidad) AS S
                       FROM dbo.FactMovimientoInventario GROUP BY TipoMovimiento, Origen) b
                 FULL OUTER JOIN (SELECT TipoMovimiento, Origen, COUNT(*) AS N, SUM(Cantidad) AS S
                                  FROM dbo.vw_MovimientosInventario GROUP BY TipoMovimiento, Origen) v
                    ON v.TipoMovimiento = b.TipoMovimiento AND v.Origen = b.Origen
                 WHERE ISNULL(b.N, -1) <> ISNULL(v.N, -1) OR ISNULL(b.S, -1) <> ISNULL(v.S, -1)) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*)
                 FROM (SELECT TipoMovimiento, Origen, COUNT(*) AS N, SUM(Cantidad) AS S
                       FROM dbo.FactMovimientoInventario GROUP BY TipoMovimiento, Origen) b
                 FULL OUTER JOIN (SELECT TipoMovimiento, Origen, COUNT(*) AS N, SUM(Cantidad) AS S
                                  FROM dbo.vw_MovimientosInventario GROUP BY TipoMovimiento, Origen) v
                    ON v.TipoMovimiento = b.TipoMovimiento AND v.Origen = b.Origen
                 WHERE ISNULL(b.N, -1) <> ISNULL(v.N, -1) OR ISNULL(b.S, -1) <> ISNULL(v.S, -1)) = 0
                THEN N'PASS' ELSE N'FAIL' END

    -- ========================================================================
    -- SECCIÓN 7 — vw_StockHistorico (T45-T53)
    -- ========================================================================
    UNION ALL
    SELECT N'TEST', N'T45', N'vw_StockHistorico', N'Conteo vs esperado independiente DimSKU x DimTienda x DimFecha', N'iguales',
           CAST((SELECT COUNT(*) FROM dbo.vw_StockHistorico) AS NVARCHAR(20)) + N' / '
           + CAST((SELECT COUNT(*) FROM dbo.DimSKU) * (SELECT COUNT(*) FROM dbo.DimTienda) * (SELECT COUNT(*) FROM dbo.DimFecha) AS NVARCHAR(20)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_StockHistorico)
                   = (SELECT COUNT(*) FROM dbo.DimSKU) * (SELECT COUNT(*) FROM dbo.DimTienda) * (SELECT COUNT(*) FROM dbo.DimFecha)
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T46', N'vw_StockHistorico', N'Duplicados por SKUID+TiendaID+FechaID', N'0',
           CAST((SELECT COUNT(*) FROM (SELECT SKUID, TiendaID, FechaID FROM dbo.vw_StockHistorico GROUP BY SKUID, TiendaID, FechaID HAVING COUNT(*) > 1) d) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM (SELECT SKUID, TiendaID, FechaID FROM dbo.vw_StockHistorico GROUP BY SKUID, TiendaID, FechaID HAVING COUNT(*) > 1) d) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T47', N'vw_StockHistorico', N'Densidad: pares SKU/Tienda con COUNT(DISTINCT FechaID) <> COUNT(DimFecha)', N'0',
           CAST((SELECT COUNT(*) FROM (SELECT SKUID, TiendaID FROM dbo.vw_StockHistorico
                 GROUP BY SKUID, TiendaID
                 HAVING COUNT(DISTINCT FechaID) <> (SELECT COUNT(*) FROM dbo.DimFecha)) p) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM (SELECT SKUID, TiendaID FROM dbo.vw_StockHistorico
                 GROUP BY SKUID, TiendaID
                 HAVING COUNT(DISTINCT FechaID) <> (SELECT COUNT(*) FROM dbo.DimFecha)) p) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T48', N'vw_StockHistorico', N'Movimientos diarios vs ledger independiente (RN-013: Sistema=INGRESO/AJUSTE/DESCUENTO_DEFINITIVO; Reservado=RESERVA/LIBERACION_RESERVA/DESCUENTO_DEFINITIVO)', N'0 mismatches',
           CAST((SELECT COUNT(*)
                 FROM (SELECT SKUID, TiendaID, FechaID,
                              SUM(CASE WHEN TipoMovimiento IN (N'INGRESO', N'AJUSTE', N'DESCUENTO_DEFINITIVO') THEN Cantidad ELSE 0 END) AS MovSis,
                              SUM(CASE WHEN TipoMovimiento IN (N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO') THEN Cantidad ELSE 0 END) AS MovRes
                       FROM dbo.FactMovimientoInventario
                       GROUP BY SKUID, TiendaID, FechaID) i
                 FULL OUTER JOIN (SELECT SKUID, TiendaID, FechaID, MovimientoStockSistema AS VS, MovimientoStockReservado AS VR
                                  FROM dbo.vw_StockHistorico
                                  WHERE MovimientoStockSistema <> 0 OR MovimientoStockReservado <> 0) v
                    ON v.SKUID = i.SKUID AND v.TiendaID = i.TiendaID AND v.FechaID = i.FechaID
                 WHERE ISNULL(i.MovSis, 0) <> ISNULL(v.VS, 0) OR ISNULL(i.MovRes, 0) <> ISNULL(v.VR, 0)) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*)
                 FROM (SELECT SKUID, TiendaID, FechaID,
                              SUM(CASE WHEN TipoMovimiento IN (N'INGRESO', N'AJUSTE', N'DESCUENTO_DEFINITIVO') THEN Cantidad ELSE 0 END) AS MovSis,
                              SUM(CASE WHEN TipoMovimiento IN (N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO') THEN Cantidad ELSE 0 END) AS MovRes
                       FROM dbo.FactMovimientoInventario
                       GROUP BY SKUID, TiendaID, FechaID) i
                 FULL OUTER JOIN (SELECT SKUID, TiendaID, FechaID, MovimientoStockSistema AS VS, MovimientoStockReservado AS VR
                                  FROM dbo.vw_StockHistorico
                                  WHERE MovimientoStockSistema <> 0 OR MovimientoStockReservado <> 0) v
                    ON v.SKUID = i.SKUID AND v.TiendaID = i.TiendaID AND v.FechaID = i.FechaID
                 WHERE ISNULL(i.MovSis, 0) <> ISNULL(v.VS, 0) OR ISNULL(i.MovRes, 0) <> ISNULL(v.VR, 0)) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T49', N'vw_StockHistorico', N'Acumulados StockSistema/StockReservado recalculados desde el ledger sobre la grilla completa (sin usar la vista)', N'0 mismatches',
           CAST((SELECT COUNT(*)
                 FROM (SELECT g.SKUID, g.TiendaID, g.FechaID,
                              SUM(ISNULL(d.MovSis, 0)) OVER (PARTITION BY g.SKUID, g.TiendaID ORDER BY g.FechaID ROWS UNBOUNDED PRECEDING) AS AccSis,
                              SUM(ISNULL(d.MovRes, 0)) OVER (PARTITION BY g.SKUID, g.TiendaID ORDER BY g.FechaID ROWS UNBOUNDED PRECEDING) AS AccRes
                       FROM (SELECT s.SKUID, t.TiendaID, f.FechaID
                             FROM dbo.DimSKU s CROSS JOIN dbo.DimTienda t CROSS JOIN dbo.DimFecha f) g
                       LEFT JOIN (SELECT SKUID, TiendaID, FechaID,
                                         SUM(CASE WHEN TipoMovimiento IN (N'INGRESO', N'AJUSTE', N'DESCUENTO_DEFINITIVO') THEN Cantidad ELSE 0 END) AS MovSis,
                                         SUM(CASE WHEN TipoMovimiento IN (N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO') THEN Cantidad ELSE 0 END) AS MovRes
                                  FROM dbo.FactMovimientoInventario
                                  GROUP BY SKUID, TiendaID, FechaID) d
                         ON d.SKUID = g.SKUID AND d.TiendaID = g.TiendaID AND d.FechaID = g.FechaID) x
                 JOIN dbo.vw_StockHistorico v ON v.SKUID = x.SKUID AND v.TiendaID = x.TiendaID AND v.FechaID = x.FechaID
                 WHERE x.AccSis <> v.StockSistema OR x.AccRes <> v.StockReservado) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*)
                 FROM (SELECT g.SKUID, g.TiendaID, g.FechaID,
                              SUM(ISNULL(d.MovSis, 0)) OVER (PARTITION BY g.SKUID, g.TiendaID ORDER BY g.FechaID ROWS UNBOUNDED PRECEDING) AS AccSis,
                              SUM(ISNULL(d.MovRes, 0)) OVER (PARTITION BY g.SKUID, g.TiendaID ORDER BY g.FechaID ROWS UNBOUNDED PRECEDING) AS AccRes
                       FROM (SELECT s.SKUID, t.TiendaID, f.FechaID
                             FROM dbo.DimSKU s CROSS JOIN dbo.DimTienda t CROSS JOIN dbo.DimFecha f) g
                       LEFT JOIN (SELECT SKUID, TiendaID, FechaID,
                                         SUM(CASE WHEN TipoMovimiento IN (N'INGRESO', N'AJUSTE', N'DESCUENTO_DEFINITIVO') THEN Cantidad ELSE 0 END) AS MovSis,
                                         SUM(CASE WHEN TipoMovimiento IN (N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO') THEN Cantidad ELSE 0 END) AS MovRes
                                  FROM dbo.FactMovimientoInventario
                                  GROUP BY SKUID, TiendaID, FechaID) d
                         ON d.SKUID = g.SKUID AND d.TiendaID = g.TiendaID AND d.FechaID = g.FechaID) x
                 JOIN dbo.vw_StockHistorico v ON v.SKUID = x.SKUID AND v.TiendaID = x.TiendaID AND v.FechaID = x.FechaID
                 WHERE x.AccSis <> v.StockSistema OR x.AccRes <> v.StockReservado) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T50', N'vw_StockHistorico', N'StockDisponible = StockSistema - StockReservado', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_StockHistorico
                 WHERE StockDisponible <> StockSistema - StockReservado
                    OR StockDisponible IS NULL OR StockSistema IS NULL OR StockReservado IS NULL) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_StockHistorico
                 WHERE StockDisponible <> StockSistema - StockReservado
                    OR StockDisponible IS NULL OR StockSistema IS NULL OR StockReservado IS NULL) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T51', N'vw_StockHistorico', N'Valores negativos (Sistema/Reservado/Disponible) — se reportan, no se corrigen', N'0 / 0 / 0',
           CAST((SELECT COUNT(*) FROM dbo.vw_StockHistorico WHERE StockSistema < 0) AS NVARCHAR(10)) + N' / '
           + CAST((SELECT COUNT(*) FROM dbo.vw_StockHistorico WHERE StockReservado < 0) AS NVARCHAR(10)) + N' / '
           + CAST((SELECT COUNT(*) FROM dbo.vw_StockHistorico WHERE StockDisponible < 0) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_StockHistorico WHERE StockSistema < 0) = 0
                  AND (SELECT COUNT(*) FROM dbo.vw_StockHistorico WHERE StockReservado < 0) = 0
                  AND (SELECT COUNT(*) FROM dbo.vw_StockHistorico WHERE StockDisponible < 0) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T52', N'vw_StockHistorico', N'Reconciliacion: ultimo dia (MAX(DimFecha) independiente) por SKU/Tienda vs StockSKUTienda (Sistema/Reservado/Disponible)', N'0 discrepancias',
           CAST((SELECT COUNT(*)
                 FROM dbo.StockSKUTienda k
                 LEFT JOIN (SELECT SKUID, TiendaID, StockSistema, StockReservado
                            FROM dbo.vw_StockHistorico
                            WHERE FechaID = (SELECT MAX(FechaID) FROM dbo.DimFecha)) u
                   ON u.SKUID = k.SKUID AND u.TiendaID = k.TiendaID
                 WHERE u.SKUID IS NULL
                    OR u.StockSistema <> k.StockSistema
                    OR u.StockReservado <> k.StockReservado
                    OR (u.StockSistema - u.StockReservado) <> (k.StockSistema - k.StockReservado))
               + (SELECT COUNT(*)
                  FROM (SELECT SKUID, TiendaID
                        FROM dbo.vw_StockHistorico
                        WHERE FechaID = (SELECT MAX(FechaID) FROM dbo.DimFecha)) u2
                  LEFT JOIN dbo.StockSKUTienda k2 ON k2.SKUID = u2.SKUID AND k2.TiendaID = u2.TiendaID
                  WHERE k2.SKUID IS NULL) AS NVARCHAR(10)),
           CASE WHEN ((SELECT COUNT(*)
                 FROM dbo.StockSKUTienda k
                 LEFT JOIN (SELECT SKUID, TiendaID, StockSistema, StockReservado
                            FROM dbo.vw_StockHistorico
                            WHERE FechaID = (SELECT MAX(FechaID) FROM dbo.DimFecha)) u
                   ON u.SKUID = k.SKUID AND u.TiendaID = k.TiendaID
                 WHERE u.SKUID IS NULL
                    OR u.StockSistema <> k.StockSistema
                    OR u.StockReservado <> k.StockReservado
                    OR (u.StockSistema - u.StockReservado) <> (k.StockSistema - k.StockReservado))
               + (SELECT COUNT(*)
                  FROM (SELECT SKUID, TiendaID
                        FROM dbo.vw_StockHistorico
                        WHERE FechaID = (SELECT MAX(FechaID) FROM dbo.DimFecha)) u2
                  LEFT JOIN dbo.StockSKUTienda k2 ON k2.SKUID = u2.SKUID AND k2.TiendaID = u2.TiendaID
                  WHERE k2.SKUID IS NULL)) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T53', N'vw_StockHistorico', N'Caso seed SKU 4 / Tienda 6 / ultimo dia (Sistema, Reservado, Disponible)', N'8 / 0 / 8',
           CAST(ISNULL((SELECT StockSistema FROM dbo.vw_StockHistorico
                        WHERE SKUID = 4 AND TiendaID = 6 AND FechaID = (SELECT MAX(FechaID) FROM dbo.DimFecha)), -1) AS NVARCHAR(10)) + N' / '
           + CAST(ISNULL((SELECT StockReservado FROM dbo.vw_StockHistorico
                          WHERE SKUID = 4 AND TiendaID = 6 AND FechaID = (SELECT MAX(FechaID) FROM dbo.DimFecha)), -1) AS NVARCHAR(10)) + N' / '
           + CAST(ISNULL((SELECT StockDisponible FROM dbo.vw_StockHistorico
                          WHERE SKUID = 4 AND TiendaID = 6 AND FechaID = (SELECT MAX(FechaID) FROM dbo.DimFecha)), -1) AS NVARCHAR(10)),
           CASE WHEN ISNULL((SELECT StockSistema FROM dbo.vw_StockHistorico
                             WHERE SKUID = 4 AND TiendaID = 6 AND FechaID = (SELECT MAX(FechaID) FROM dbo.DimFecha)), -1) = 8
                  AND ISNULL((SELECT StockReservado FROM dbo.vw_StockHistorico
                              WHERE SKUID = 4 AND TiendaID = 6 AND FechaID = (SELECT MAX(FechaID) FROM dbo.DimFecha)), -1) = 0
                  AND ISNULL((SELECT StockDisponible FROM dbo.vw_StockHistorico
                              WHERE SKUID = 4 AND TiendaID = 6 AND FechaID = (SELECT MAX(FechaID) FROM dbo.DimFecha)), -1) = 8
                THEN N'PASS' ELSE N'FAIL' END

    -- ========================================================================
    -- SECCIÓN 8 — vw_Devoluciones (T54-T59) — base con 0 registros: 0/0 PASS
    -- ========================================================================
    UNION ALL
    SELECT N'TEST', N'T54', N'vw_Devoluciones', N'Grano: COUNT(*) vista vs FactDevolucion', N'iguales',
           CAST((SELECT COUNT(*) FROM dbo.vw_Devoluciones) AS NVARCHAR(20)) + N' / '
           + CAST((SELECT COUNT(*) FROM dbo.FactDevolucion) AS NVARCHAR(20)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_Devoluciones)
                   = (SELECT COUNT(*) FROM dbo.FactDevolucion)
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T55', N'vw_Devoluciones', N'DevolucionID duplicados', N'0',
           CAST((SELECT COUNT(*) FROM (SELECT DevolucionID FROM dbo.vw_Devoluciones GROUP BY DevolucionID HAVING COUNT(*) > 1) d) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM (SELECT DevolucionID FROM dbo.vw_Devoluciones GROUP BY DevolucionID HAVING COUNT(*) > 1) d) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T56', N'vw_Devoluciones', N'DevolucionID de base ausentes en la vista', N'0',
           CAST((SELECT COUNT(*) FROM dbo.FactDevolucion b LEFT JOIN dbo.vw_Devoluciones v ON v.DevolucionID = b.DevolucionID WHERE v.DevolucionID IS NULL) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.FactDevolucion b LEFT JOIN dbo.vw_Devoluciones v ON v.DevolucionID = b.DevolucionID WHERE v.DevolucionID IS NULL) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T57', N'vw_Devoluciones', N'DevolucionID en la vista inexistentes en base', N'0',
           CAST((SELECT COUNT(*) FROM dbo.vw_Devoluciones v LEFT JOIN dbo.FactDevolucion b ON b.DevolucionID = v.DevolucionID WHERE b.DevolucionID IS NULL) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_Devoluciones v LEFT JOIN dbo.FactDevolucion b ON b.DevolucionID = v.DevolucionID WHERE b.DevolucionID IS NULL) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T58', N'vw_Devoluciones', N'LineaID: existe en FactPedidoDetalle (FK NOT NULL)', N'0 huerfanos',
           CAST((SELECT COUNT(*) FROM dbo.vw_Devoluciones v LEFT JOIN dbo.FactPedidoDetalle d ON d.LineaID = v.LineaID WHERE d.LineaID IS NULL) AS NVARCHAR(10)),
           CASE WHEN (SELECT COUNT(*) FROM dbo.vw_Devoluciones v LEFT JOIN dbo.FactPedidoDetalle d ON d.LineaID = v.LineaID WHERE d.LineaID IS NULL) = 0
                THEN N'PASS' ELSE N'FAIL' END
    UNION ALL
    SELECT N'TEST', N'T59', N'vw_Devoluciones', N'Dimensiones usadas por la vista (Cliente, SKU/Producto, Tienda si no es NULL, Fecha, Motivo)', N'0 mismatches',
           CAST((SELECT COUNT(*) FROM dbo.vw_Devoluciones v JOIN dbo.DimCliente c ON c.ClienteID = v.ClienteID
                 WHERE v.NombreCliente <> c.NombreCliente)
               + (SELECT COUNT(*) FROM dbo.vw_Devoluciones v
                  JOIN dbo.DimSKU s ON s.SKUID = v.SKUID
                  JOIN dbo.DimProducto p ON p.ProductoID = s.ProductoID
                  WHERE v.CodigoSKU <> s.CodigoSKU OR v.ProductoID <> s.ProductoID
                     OR v.NombreProducto <> p.NombreProducto OR v.Categoria <> p.Categoria)
               + (SELECT COUNT(*) FROM dbo.vw_Devoluciones v JOIN dbo.DimTienda t ON t.TiendaID = v.TiendaID
                  WHERE v.NombreTienda <> t.NombreTienda OR v.Ciudad <> t.Ciudad)
               + (SELECT COUNT(*) FROM dbo.vw_Devoluciones v
                  WHERE (v.TiendaID IS NULL AND v.NombreTienda IS NOT NULL)
                     OR (v.TiendaID IS NOT NULL AND v.NombreTienda IS NULL))
               + (SELECT COUNT(*) FROM dbo.vw_Devoluciones v JOIN dbo.DimFecha f ON f.FechaID = v.FechaID
                  WHERE v.Fecha <> f.Fecha OR v.Anio <> f.Anio OR v.Mes <> f.Mes OR v.NombreMes <> f.NombreMes)
               + (SELECT COUNT(*) FROM dbo.vw_Devoluciones v JOIN dbo.DimMotivo m ON m.MotivoID = v.MotivoID
                  WHERE v.NombreMotivo <> m.NombreMotivo OR v.TipoMotivo <> m.TipoMotivo) AS NVARCHAR(10)),
           CASE WHEN ((SELECT COUNT(*) FROM dbo.vw_Devoluciones v JOIN dbo.DimCliente c ON c.ClienteID = v.ClienteID
                  WHERE v.NombreCliente <> c.NombreCliente)
               + (SELECT COUNT(*) FROM dbo.vw_Devoluciones v
                  JOIN dbo.DimSKU s ON s.SKUID = v.SKUID
                  JOIN dbo.DimProducto p ON p.ProductoID = s.ProductoID
                  WHERE v.CodigoSKU <> s.CodigoSKU OR v.ProductoID <> s.ProductoID
                     OR v.NombreProducto <> p.NombreProducto OR v.Categoria <> p.Categoria)
               + (SELECT COUNT(*) FROM dbo.vw_Devoluciones v JOIN dbo.DimTienda t ON t.TiendaID = v.TiendaID
                  WHERE v.NombreTienda <> t.NombreTienda OR v.Ciudad <> t.Ciudad)
               + (SELECT COUNT(*) FROM dbo.vw_Devoluciones v
                  WHERE (v.TiendaID IS NULL AND v.NombreTienda IS NOT NULL)
                     OR (v.TiendaID IS NOT NULL AND v.NombreTienda IS NULL))
               + (SELECT COUNT(*) FROM dbo.vw_Devoluciones v JOIN dbo.DimFecha f ON f.FechaID = v.FechaID
                  WHERE v.Fecha <> f.Fecha OR v.Anio <> f.Anio OR v.Mes <> f.Mes OR v.NombreMes <> f.NombreMes)
               + (SELECT COUNT(*) FROM dbo.vw_Devoluciones v JOIN dbo.DimMotivo m ON m.MotivoID = v.MotivoID
                  WHERE v.NombreMotivo <> m.NombreMotivo OR v.TipoMotivo <> m.TipoMotivo)) = 0
                THEN N'PASS' ELSE N'FAIL' END

    -- ========================================================================
    -- SECCIÓN 9 — Prueba global de duplicados (T60)
    -- ========================================================================
    UNION ALL
    SELECT N'TEST', N'T60', N'GLOBAL', N'Duplicados globales: suma de los 6 granos (LineaID, HistorialID, IncidenciaID, MovimientoID, SKU+Tienda+Fecha, DevolucionID)', N'0',
           CAST((SELECT COUNT(*) FROM (SELECT LineaID FROM dbo.vw_PedidosOperaciones GROUP BY LineaID HAVING COUNT(*) > 1) x)
               + (SELECT COUNT(*) FROM (SELECT HistorialID FROM dbo.vw_TiemposEstados GROUP BY HistorialID HAVING COUNT(*) > 1) x)
               + (SELECT COUNT(*) FROM (SELECT IncidenciaID FROM dbo.vw_IncidenciasPicking GROUP BY IncidenciaID HAVING COUNT(*) > 1) x)
               + (SELECT COUNT(*) FROM (SELECT MovimientoID FROM dbo.vw_MovimientosInventario GROUP BY MovimientoID HAVING COUNT(*) > 1) x)
               + (SELECT COUNT(*) FROM (SELECT SKUID, TiendaID, FechaID FROM dbo.vw_StockHistorico GROUP BY SKUID, TiendaID, FechaID HAVING COUNT(*) > 1) x)
               + (SELECT COUNT(*) FROM (SELECT DevolucionID FROM dbo.vw_Devoluciones GROUP BY DevolucionID HAVING COUNT(*) > 1) x) AS NVARCHAR(10)),
           CASE WHEN ((SELECT COUNT(*) FROM (SELECT LineaID FROM dbo.vw_PedidosOperaciones GROUP BY LineaID HAVING COUNT(*) > 1) x)
               + (SELECT COUNT(*) FROM (SELECT HistorialID FROM dbo.vw_TiemposEstados GROUP BY HistorialID HAVING COUNT(*) > 1) x)
               + (SELECT COUNT(*) FROM (SELECT IncidenciaID FROM dbo.vw_IncidenciasPicking GROUP BY IncidenciaID HAVING COUNT(*) > 1) x)
               + (SELECT COUNT(*) FROM (SELECT MovimientoID FROM dbo.vw_MovimientosInventario GROUP BY MovimientoID HAVING COUNT(*) > 1) x)
               + (SELECT COUNT(*) FROM (SELECT SKUID, TiendaID, FechaID FROM dbo.vw_StockHistorico GROUP BY SKUID, TiendaID, FechaID HAVING COUNT(*) > 1) x)
               + (SELECT COUNT(*) FROM (SELECT DevolucionID FROM dbo.vw_Devoluciones GROUP BY DevolucionID HAVING COUNT(*) > 1) x)) = 0
                THEN N'PASS' ELSE N'FAIL' END
)
-- ==============================================================================
-- SECCIÓN 11 — Detalle, resumen por vista, total, global, mensaje y fallos
-- (las secciones finales se construyen sobre la CTE "Tests" en la MISMA
--  sentencia; los fallos se listan como filas extra que valen 0 si no hay)
-- ==============================================================================
SELECT * FROM (
SELECT Seccion, TestID, Vista, Validacion, Esperado, Obtenido, Estado
FROM Tests
UNION ALL
SELECT N'RESUMEN', N'', Vista, N'Tests / PASS / FAIL por vista', N'0 FAIL',
       CAST(COUNT(*) AS NVARCHAR(10)) + N' / '
       + CAST(SUM(CASE WHEN Estado = N'PASS' THEN 1 ELSE 0 END) AS NVARCHAR(10)) + N' / '
       + CAST(SUM(CASE WHEN Estado = N'FAIL' THEN 1 ELSE 0 END) AS NVARCHAR(10)),
       CASE WHEN SUM(CASE WHEN Estado = N'FAIL' THEN 1 ELSE 0 END) = 0 THEN N'PASS' ELSE N'FAIL' END
FROM Tests
GROUP BY Vista
UNION ALL
SELECT N'TOTAL', N'', N'TODAS', N'Tests ejecutados / PASS / FAIL', N'0 FAIL',
       CAST(COUNT(*) AS NVARCHAR(10)) + N' / '
       + CAST(SUM(CASE WHEN Estado = N'PASS' THEN 1 ELSE 0 END) AS NVARCHAR(10)) + N' / '
       + CAST(SUM(CASE WHEN Estado = N'FAIL' THEN 1 ELSE 0 END) AS NVARCHAR(10)),
       CASE WHEN SUM(CASE WHEN Estado = N'FAIL' THEN 1 ELSE 0 END) = 0 THEN N'PASS' ELSE N'FAIL' END
FROM Tests
UNION ALL
SELECT N'GLOBAL', N'', N'RESULTADO GLOBAL', N'RESULTADO GLOBAL: PASS', N'0 FAIL',
       CASE WHEN SUM(CASE WHEN Estado = N'FAIL' THEN 1 ELSE 0 END) = 0
            THEN N'RESULTADO GLOBAL: PASS' ELSE N'RESULTADO GLOBAL: FAIL' END,
       CASE WHEN SUM(CASE WHEN Estado = N'FAIL' THEN 1 ELSE 0 END) = 0 THEN N'PASS' ELSE N'FAIL' END
FROM Tests
UNION ALL
SELECT N'MENSAJE', N'', N'FASE 3', N'Mensaje de cierre', N'CAPA ANALITICA FASE 3: VALIDADA',
       CASE WHEN SUM(CASE WHEN Estado = N'FAIL' THEN 1 ELSE 0 END) = 0
            THEN N'CAPA ANALITICA FASE 3: VALIDADA'
            ELSE N'DETENERSE: revisar seccion FALLO (no modificar vistas ni datos)' END,
       CASE WHEN SUM(CASE WHEN Estado = N'FAIL' THEN 1 ELSE 0 END) = 0 THEN N'PASS' ELSE N'FAIL' END
FROM Tests
UNION ALL
SELECT N'FALLO', TestID, Vista, Validacion, Esperado, Obtenido, Estado
FROM Tests
WHERE Estado = N'FAIL'
) r
ORDER BY CASE r.Seccion WHEN N'TEST' THEN 1 WHEN N'RESUMEN' THEN 2 WHEN N'TOTAL' THEN 3
                         WHEN N'GLOBAL' THEN 4 WHEN N'MENSAJE' THEN 5 ELSE 6 END,
         r.TestID;

-- ==============================================================================
-- SECCIÓN 10 — Resumen de filas y grano de cada vista (informativo)
--   Vista | Filas | Clave/grano | Duplicados
-- ==============================================================================
SELECT N'vw_PedidosOperaciones' AS Vista,
       CAST(COUNT(*) AS INT) AS Filas,
       N'LineaID' AS Grano,
       (SELECT COUNT(*) FROM (SELECT LineaID FROM dbo.vw_PedidosOperaciones GROUP BY LineaID HAVING COUNT(*) > 1) d) AS Duplicados
FROM dbo.vw_PedidosOperaciones
UNION ALL
SELECT N'vw_TiemposEstados', CAST(COUNT(*) AS INT), N'HistorialID',
       (SELECT COUNT(*) FROM (SELECT HistorialID FROM dbo.vw_TiemposEstados GROUP BY HistorialID HAVING COUNT(*) > 1) d)
FROM dbo.vw_TiemposEstados
UNION ALL
SELECT N'vw_IncidenciasPicking', CAST(COUNT(*) AS INT), N'IncidenciaID',
       (SELECT COUNT(*) FROM (SELECT IncidenciaID FROM dbo.vw_IncidenciasPicking GROUP BY IncidenciaID HAVING COUNT(*) > 1) d)
FROM dbo.vw_IncidenciasPicking
UNION ALL
SELECT N'vw_MovimientosInventario', CAST(COUNT(*) AS INT), N'MovimientoID',
       (SELECT COUNT(*) FROM (SELECT MovimientoID FROM dbo.vw_MovimientosInventario GROUP BY MovimientoID HAVING COUNT(*) > 1) d)
FROM dbo.vw_MovimientosInventario
UNION ALL
SELECT N'vw_StockHistorico', CAST(COUNT(*) AS INT), N'SKUID + TiendaID + FechaID',
       (SELECT COUNT(*) FROM (SELECT SKUID, TiendaID, FechaID FROM dbo.vw_StockHistorico GROUP BY SKUID, TiendaID, FechaID HAVING COUNT(*) > 1) d)
FROM dbo.vw_StockHistorico
UNION ALL
SELECT N'vw_Devoluciones', CAST(COUNT(*) AS INT), N'DevolucionID',
       (SELECT COUNT(*) FROM (SELECT DevolucionID FROM dbo.vw_Devoluciones GROUP BY DevolucionID HAVING COUNT(*) > 1) d)
FROM dbo.vw_Devoluciones;

