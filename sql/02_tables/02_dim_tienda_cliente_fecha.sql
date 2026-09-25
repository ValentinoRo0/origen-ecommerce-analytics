/*
===============================================================================
ORIGEN — Tablas de dimensiones: DimTienda, DimCliente, DimFecha
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: 02_modelo_de_datos.md, sección 3.
===============================================================================
*/

USE OrigenDB;
GO

-- -----------------------------------------------------------------------------
-- DimTienda
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.DimTienda', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimTienda
    (
        TiendaID        INT             IDENTITY(1,1) NOT NULL,
        NombreTienda    VARCHAR(80)     NOT NULL,
        Distrito        VARCHAR(60)     NULL,
        Ciudad          VARCHAR(60)     NOT NULL,

        CONSTRAINT PK_DimTienda PRIMARY KEY (TiendaID)
    );
END
GO

-- -----------------------------------------------------------------------------
-- DimCliente
-- Deliberadamente mínima (Fase 0, alcance): sin CRM, sin segmentación de
-- marketing. Solo lo necesario para vincular un pedido y una devolución
-- a una persona.
-- NOTA: Email NO tiene UNIQUE — no existe ninguna regla de negocio en
-- Fase 1 que identifique al cliente por su correo. Agregar esa restricción
-- habría sido una suposición no pedida por el diseño.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.DimCliente', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimCliente
    (
        ClienteID       INT             IDENTITY(1,1) NOT NULL,
        NombreCliente   VARCHAR(100)    NOT NULL,
        Email           VARCHAR(100)    NOT NULL,

        CONSTRAINT PK_DimCliente PRIMARY KEY (ClienteID)
    );
END
GO

-- -----------------------------------------------------------------------------
-- DimFecha
-- No usa IDENTITY: la clave es la fecha misma en formato numérico AAAAMMDD.
-- Esto es una convención estándar de modelado dimensional (Kimball) porque
-- permite filtrar y ordenar directamente por el ID sin tener que unir con
-- la tabla primero, y hace que las particiones/índices por fecha sean más
-- simples si el proyecto llegara a necesitarlo.
-- -----------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.DimFecha', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DimFecha
    (
        FechaID         INT             NOT NULL,   -- formato AAAAMMDD, ej. 20260315
        Fecha           DATE            NOT NULL,
        Anio            SMALLINT        NOT NULL,
        Mes             TINYINT         NOT NULL,
        NombreMes       VARCHAR(20)     NOT NULL,
        Dia             TINYINT         NOT NULL,
        DiaSemana       VARCHAR(20)     NOT NULL,
        EsCampania      BIT             NOT NULL DEFAULT (0),   -- Fase 1: marca periodos de campaña
        NombreCampania  VARCHAR(50)     NULL,                    -- ej. 'Cyber Wow', NULL si no aplica

        CONSTRAINT PK_DimFecha PRIMARY KEY (FechaID),
        CONSTRAINT UQ_DimFecha_Fecha UNIQUE (Fecha)
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
WHERE t.name IN (N'DimTienda', N'DimCliente', N'DimFecha')
ORDER BY t.name, c.column_id;
GO