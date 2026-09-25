/*
===============================================================================
ORIGEN — Tabla de hechos: FactHistorialEstadoLinea
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: 02_modelo_de_datos.md, sección 4.2.
Grano: 1 fila = 1 transición de estado de una línea de pedido.

Es la fuente de verdad de la trayectoria del pedido (RN-008/RN-028): de aquí
se calculan tiempos de picking, cumplimiento de SLA y la brecha entre
cancelación y notificación al cliente (RN-005). EstadoActualID en
FactPedidoDetalle es una copia rápida del último estado; esta tabla nunca
se sobreescribe, solo se le agregan filas.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.FactHistorialEstadoLinea', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FactHistorialEstadoLinea
    (
        HistorialID     INT             IDENTITY(1,1) NOT NULL,
        LineaID         INT             NOT NULL,
        EstadoID        INT             NOT NULL,
        FechaID         INT             NOT NULL,
        FechaHora       DATETIME2(0)    NOT NULL,   -- timestamp completo, para precisión de hora (Fase 2, sección 4.2)

        CONSTRAINT PK_FactHistorialEstadoLinea PRIMARY KEY (HistorialID),

        CONSTRAINT FK_HistorialEstado_Linea FOREIGN KEY (LineaID)
            REFERENCES dbo.FactPedidoDetalle (LineaID),
        CONSTRAINT FK_HistorialEstado_Estado FOREIGN KEY (EstadoID)
            REFERENCES dbo.DimEstado (EstadoID),
        CONSTRAINT FK_HistorialEstado_Fecha FOREIGN KEY (FechaID)
            REFERENCES dbo.DimFecha (FechaID)
    );
END
GO

-- Índice sobre LineaID: esta tabla se va a consultar constantemente
-- filtrando por línea (ej. "dame todo el historial del pedido X" o
-- "dame el último estado de la línea X"), así que un índice aquí evita
-- que SQL Server tenga que recorrer toda la tabla en cada consulta.
-- No es una PK ni una FK — es una decisión de rendimiento, distinta de
-- una decisión de integridad.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_HistorialEstado_LineaID'
    AND object_id = OBJECT_ID(N'dbo.FactHistorialEstadoLinea')
)
BEGIN
    CREATE INDEX IX_HistorialEstado_LineaID
        ON dbo.FactHistorialEstadoLinea (LineaID);
END
GO

-- Verificación
SELECT
    c.name AS Columna,
    ty.name AS TipoDato,
    c.is_nullable AS PermiteNulo
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.name = N'FactHistorialEstadoLinea'
ORDER BY c.column_id;
GO