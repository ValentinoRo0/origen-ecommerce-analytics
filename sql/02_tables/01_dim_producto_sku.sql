/*
===============================================================================
ORIGEN — Tablas de dimensiones: DimProducto y DimSKU
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: 02_modelo_de_datos.md, secciones 2 y 3.

Por qué estas dos primero: todas las demás tablas de hechos dependen de
DimSKU (directa o indirectamente vía DimProducto), así que deben existir
antes de crear cualquier FOREIGN KEY que las referencie.
===============================================================================
*/

USE OrigenDB;
GO

-- -----------------------------------------------------------------------------
-- DimProducto: el concepto comercial (ej. "Camisa Oxford"), sin talla ni color.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.DimProducto', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimProducto
    (
        ProductoID      INT             IDENTITY(1,1) NOT NULL,
        NombreProducto  VARCHAR(100)    NOT NULL,
        Categoria       VARCHAR(50)     NOT NULL,
        Marca           VARCHAR(50)     NULL,

        CONSTRAINT PK_DimProducto PRIMARY KEY (ProductoID)
    );
END
GO

-- -----------------------------------------------------------------------------
-- DimSKU: la unidad real de inventario (producto + talla + color).
-- Es el grano confirmado para stock, picking e incidencias (Fase 2, sección 2).
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.DimSKU', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimSKU
    (
        SKUID           INT             IDENTITY(1,1) NOT NULL,
        CodigoSKU       VARCHAR(10)     NOT NULL,   -- ej. 'A58214' — dato de negocio, no PK
        ProductoID      INT             NOT NULL,
        Talla           VARCHAR(10)     NOT NULL,
        Color           VARCHAR(30)     NOT NULL,

        CONSTRAINT PK_DimSKU PRIMARY KEY (SKUID),
        CONSTRAINT UQ_DimSKU_CodigoSKU UNIQUE (CodigoSKU),
        CONSTRAINT FK_DimSKU_DimProducto FOREIGN KEY (ProductoID)
            REFERENCES dbo.DimProducto (ProductoID)
    );
END
GO

-- Verificación: confirma que ambas tablas se crearon correctamente
SELECT
    t.name AS Tabla,
    c.name AS Columna,
    ty.name AS TipoDato,
    c.max_length AS LongitudMax,
    c.is_nullable AS PermiteNulo
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.name IN (N'DimProducto', N'DimSKU')
ORDER BY t.name, c.column_id;
GO