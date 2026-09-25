/*
===============================================================================
ORIGEN — Tabla de hechos: FactDevolucion
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: 02_modelo_de_datos.md, sección 4.5. Reglas: RN-026, RN-027
(01_procesos_y_reglas.md, sección 8).

Grano: 1 fila = 1 devolución, vinculada a una línea de pedido en estado
Completado.

Nota importante: las dos reglas de negocio más relevantes de esta tabla
(RN-026: la línea debe estar Completada; RN-027: debe estar dentro de la
ventana de devolución) NO se implementan aquí como CHECK, porque ambas
requieren consultar OTRA tabla (el estado vive en FactPedidoDetalle /
FactHistorialEstadoLinea, no en esta). Mismo caso que MotivoCancelacionID
en FactPedidoDetalle — se resuelven con un procedimiento/trigger en la
siguiente sección de esta fase, no con un constraint declarativo.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.FactDevolucion', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FactDevolucion
    (
        DevolucionID    INT             IDENTITY(1,1) NOT NULL,
        LineaID         INT             NOT NULL,   -- debe estar en estado Completado (RN-026) — validado por procedimiento
        MotivoID        INT             NOT NULL,   -- debe ser TipoMotivo = 'devolucion' — validado por procedimiento
        FechaID         INT             NOT NULL,
        FechaDevolucion DATETIME2(0)    NOT NULL,   -- debe estar dentro de la ventana de devolución (RN-027) — validado por procedimiento

        CONSTRAINT PK_FactDevolucion PRIMARY KEY (DevolucionID),

        CONSTRAINT FK_Devolucion_Linea FOREIGN KEY (LineaID)
            REFERENCES dbo.FactPedidoDetalle (LineaID),
        CONSTRAINT FK_Devolucion_Motivo FOREIGN KEY (MotivoID)
            REFERENCES dbo.DimMotivo (MotivoID),
        CONSTRAINT FK_Devolucion_Fecha FOREIGN KEY (FechaID)
            REFERENCES dbo.DimFecha (FechaID)
    );
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
WHERE t.name = N'FactDevolucion'
ORDER BY c.column_id;
GO

-- Verificación general: confirma que las 5 tablas de hechos + 8 dimensiones
-- ya existen en la base de datos
SELECT
    name AS Tabla,
    create_date AS FechaCreacion
FROM sys.tables
ORDER BY create_date;
GO