/*
===============================================================================
ORIGEN — Tablas de dimensiones: DimEstado, DimArea, DimMotivo
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: 02_modelo_de_datos.md, sección 3.
Con estas tres se completan las 8 dimensiones del modelo.
===============================================================================
*/

USE OrigenDB;
GO

-- -----------------------------------------------------------------------------
-- DimEstado
-- Estandariza los 14 estados de línea de pedido definidos en
-- 01_procesos_y_reglas.md, sección 3.2. Sin esta tabla, el estado quedaría
-- como texto libre en cada fila de FactHistorialEstadoLinea, lo cual
-- permitiría inconsistencias como 'Completado' vs 'completado' vs 'COMPLETADO'.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.DimEstado', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimEstado
    (
        EstadoID        INT             IDENTITY(1,1) NOT NULL,
        NombreEstado    VARCHAR(40)     NOT NULL,
        EsFinal         BIT             NOT NULL DEFAULT (0),   -- Fase 1, sección 3.2: Rechazado/Completado/Cancelado

        CONSTRAINT PK_DimEstado PRIMARY KEY (EstadoID),
        CONSTRAINT UQ_DimEstado_Nombre UNIQUE (NombreEstado)
    );
END
GO

-- -----------------------------------------------------------------------------
-- DimArea
-- Las áreas que aparecen como responsables en la matriz de resolución
-- (01_procesos_y_reglas.md, sección 6.3): Tienda/Picking, Operaciones
-- E-commerce, Abastecimiento, CD.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.DimArea', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimArea
    (
        AreaID          INT             IDENTITY(1,1) NOT NULL,
        NombreArea      VARCHAR(50)     NOT NULL,

        CONSTRAINT PK_DimArea PRIMARY KEY (AreaID),
        CONSTRAINT UQ_DimArea_Nombre UNIQUE (NombreArea)
    );
END
GO

-- -----------------------------------------------------------------------------
-- DimMotivo
-- Tabla compartida entre 4 contextos distintos (Fase 2, sección 3), separados
-- por TipoMotivo. Un CHECK restringe TipoMotivo a los 4 valores válidos,
-- para que nadie inserte accidentalmente un quinto tipo no contemplado
-- en el diseño.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.DimMotivo', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimMotivo
    (
        MotivoID        INT             IDENTITY(1,1) NOT NULL,
        TipoMotivo      VARCHAR(20)     NOT NULL,
        NombreMotivo    VARCHAR(50)     NOT NULL,

        CONSTRAINT PK_DimMotivo PRIMARY KEY (MotivoID),
        CONSTRAINT CK_DimMotivo_Tipo CHECK (TipoMotivo IN
            (N'incidencia', N'cancelacion', N'ajuste_stock', N'devolucion'))
    );
END
GO

-- Verificación
SELECT
    t.name AS Tabla,
    c.name AS Columna,
    ty.name AS TipoDato,
    c.is_nullable AS PermiteNulo
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.name IN (N'DimEstado', N'DimArea', N'DimMotivo')
ORDER BY t.name, c.column_id;
GO