/*
===============================================================================
ORIGEN — Constraint adicional: LineaID según TipoMovimiento
Fase 3 — Implementación SQL Server
===============================================================================
Corrección respecto a 03_implementacion_sql.md, sección 5: esta regla se
había descartado como CHECK por error. TipoMovimiento y LineaID viven en
la MISMA fila de FactMovimientoInventario, así que sí puede validarse con
un CHECK — no hacía falta lógica procedural para esto.

Regla (Fase 2, sección 4.3 / RN-011, RN-012):
- INGRESO y AJUSTE nunca tienen pedido asociado → LineaID debe ser NULL
- RESERVA, LIBERACION_RESERVA, DESCUENTO_DEFINITIVO siempre nacen de una
  línea de pedido → LineaID debe estar poblado
===============================================================================
*/

USE OrigenDB;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.check_constraints
    WHERE name = N'CK_MovInventario_LineaSegunTipo'
)
BEGIN
    ALTER TABLE dbo.FactMovimientoInventario
    ADD CONSTRAINT CK_MovInventario_LineaSegunTipo CHECK (
        (TipoMovimiento IN (N'INGRESO', N'AJUSTE') AND LineaID IS NULL)
        OR
        (TipoMovimiento IN (N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO') AND LineaID IS NOT NULL)
    );
END
GO

-- Verificación: confirma que el constraint se agregó
SELECT
    name AS NombreConstraint,
    definition AS Definicion
FROM sys.check_constraints
WHERE parent_object_id = OBJECT_ID(N'dbo.FactMovimientoInventario');
GO