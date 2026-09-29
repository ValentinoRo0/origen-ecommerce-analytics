/*
===============================================================================
ORIGEN — Trigger: sincronización de EstadoActualID
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: RN-008 (trayectoria de la línea en FactHistorialEstadoLinea,
la fuente de verdad); 02_modelo_de_datos.md (EstadoActualID como copia
denormalizada del último estado); 03_implementacion_sql.md.

Se dispara con cada INSERT en FactHistorialEstadoLinea y mantiene al día
FactPedidoDetalle.EstadoActualID — la fila que los SP de negocio y los KPI
leen sin recorrer el historial. Los procedimientos almacenados validan la
transición y registran el cambio en el historial; la sincronización de la
copia la hace SOLO este trigger (no se duplica en cada SP).

Diseño — requisitos del contrato de implementación:

1. AFTER INSERT puro. El historial es append-only (nunca se sobreescribe,
   ver cabecera de 05_fact_historial_estado_linea.sql), así que UPDATE y
   DELETE no necesitan tratamiento.

2. Inserciones de varias filas soportadas: se agrupa por LineaID en una
   variable de tabla (@Nuevos, mismo patrón que @Efectos en
   trg_ActualizarStockSKUTienda) y cada línea se actualiza UNA sola vez.

3. NO depende de MAX(FechaHora): dentro de una misma sentencia INSERT, la
   fila que representa el nuevo estado es la recién insertada — el orden de
   inserción (HistorialID), no el timestamp. Esto es deliberado: los tests
   insertan registros con fechas históricas (DATEADD sobre FechaHora) para
   simular estados alcanzados hace días; con MAX(FechaHora) esas filas
   quedarían "antepuestas" al estado real y EstadoActualID volvería a
   quedar obsoleto. Regla de diseño: la fila insertada POR ESA OPERACIÓN es
   siempre el nuevo estado, sin importar qué FechaHora tenga.

4. Misma transacción: un trigger AFTER INSERT se ejecuta dentro de la
   transacción que originó el INSERT — si el SP hace ROLLBACK, este UPDATE
   se revierte junto con el historial. No abre transacciones propias.

5. Sin recursividad ni efectos secundarios: actualiza FactPedidoDetalle,
   que no dispara este trigger (cuelga de FactHistorialEstadoLinea), y no
   toca FactMovimientoInventario, así que tampoco encadena con
   trg_ActualizarStockSKUTienda.

Si la fila destino no existiera, la inserción en el historial ya habría
fallado antes por FK_HistorialEstado_Linea — en ese caso el UPDATE
simplemente no encuentra filas que actualizar.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.trg_ActualizarEstadoActual', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_ActualizarEstadoActual;
GO

CREATE TRIGGER dbo.trg_ActualizarEstadoActual
ON dbo.FactHistorialEstadoLinea
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Un estado por línea: si una misma sentencia insertó varias filas para
    -- una misma línea, gana la última (mayor HistorialID = orden de
    -- inserción). PRIMARY KEY sobre LineaID garantiza una sola fila.
    DECLARE @Nuevos TABLE
    (
        LineaID  INT NOT NULL PRIMARY KEY,
        EstadoID INT NOT NULL
    );

    INSERT INTO @Nuevos (LineaID, EstadoID)
    SELECT LineaID, EstadoID
    FROM (
        SELECT
            LineaID,
            EstadoID,
            ROW_NUMBER() OVER (PARTITION BY LineaID ORDER BY HistorialID DESC) AS Orden
        FROM inserted
    ) AS i
    WHERE i.Orden = 1;

    UPDATE fd
    SET EstadoActualID = n.EstadoID
    FROM dbo.FactPedidoDetalle fd
    INNER JOIN @Nuevos n
        ON n.LineaID = fd.LineaID;
END
GO
