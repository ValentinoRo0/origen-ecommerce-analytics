/*
===============================================================================
ORIGEN — Tabla de hechos: FactMovimientoInventario
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: 02_modelo_de_datos.md, sección 4.3. Reglas: RN-010 a RN-015
(01_procesos_y_reglas.md, sección 4.4).

Grano: 1 fila = 1 movimiento individual, identificado por MovimientoID
(no por SKU+Tienda+Tipo+Fecha, que no garantiza unicidad — dos recepciones
el mismo día del mismo SKU son eventos distintos).

Incluye la recepción del CD como caso particular de TipoMovimiento=INGRESO
(RN-017) — no existe FactRecepcionCD como tabla independiente.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.FactMovimientoInventario', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FactMovimientoInventario
    (
        MovimientoID        INT             IDENTITY(1,1) NOT NULL,
        SKUID                INT             NOT NULL,
        TiendaID             INT             NOT NULL,
        FechaID              INT             NOT NULL,
        FechaHora            DATETIME2(0)    NOT NULL,

        TipoMovimiento       VARCHAR(25)     NOT NULL,   -- INGRESO / RESERVA / LIBERACION_RESERVA / DESCUENTO_DEFINITIVO / AJUSTE
        Origen               VARCHAR(25)     NOT NULL,   -- RECEPCION_CD / PEDIDO / CANCELACION / PICKING / CONTEO_FISICO
        Cantidad             INT             NOT NULL,   -- con signo, según TipoMovimiento (ver CK_MovInventario_SignoCantidad)

        LineaID              INT             NULL,       -- FK opcional: solo RESERVA/LIBERACION_RESERVA/DESCUENTO_DEFINITIVO (RN-011, RN-012)

        CantidadEsperada     INT             NULL,       -- solo si Origen = RECEPCION_CD (RN-016)
        CantidadRecibida     INT             NULL,       -- solo si Origen = RECEPCION_CD
        Discrepancia         INT             NULL,       -- solo si Origen = RECEPCION_CD

        MotivoID             INT             NULL,       -- FK opcional: solo si TipoMovimiento = AJUSTE (RN-014)

        CONSTRAINT PK_FactMovimientoInventario PRIMARY KEY (MovimientoID),

        CONSTRAINT FK_MovInventario_SKU FOREIGN KEY (SKUID)
            REFERENCES dbo.DimSKU (SKUID),
        CONSTRAINT FK_MovInventario_Tienda FOREIGN KEY (TiendaID)
            REFERENCES dbo.DimTienda (TiendaID),
        CONSTRAINT FK_MovInventario_Fecha FOREIGN KEY (FechaID)
            REFERENCES dbo.DimFecha (FechaID),
        CONSTRAINT FK_MovInventario_Linea FOREIGN KEY (LineaID)
            REFERENCES dbo.FactPedidoDetalle (LineaID),
        CONSTRAINT FK_MovInventario_Motivo FOREIGN KEY (MotivoID)
            REFERENCES dbo.DimMotivo (MotivoID),

        -- Restringe TipoMovimiento a los 5 valores definidos en el modelo (Fase 2, sección 4.3)
        CONSTRAINT CK_MovInventario_Tipo CHECK (TipoMovimiento IN
            (N'INGRESO', N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO', N'AJUSTE')),

        -- Coherencia dentro de la misma fila (no cruza tablas, por eso SÍ es
        -- válido como CHECK, a diferencia del caso MotivoCancelacionID):
        -- si es una recepción del CD, los 3 campos de recepción deben venir
        -- juntos; si no lo es, ninguno de los 3 debe tener valor.
        CONSTRAINT CK_MovInventario_CamposRecepcion CHECK (
            (Origen = N'RECEPCION_CD' AND CantidadEsperada IS NOT NULL
                AND CantidadRecibida IS NOT NULL AND Discrepancia IS NOT NULL)
            OR
            (Origen <> N'RECEPCION_CD' AND CantidadEsperada IS NULL
                AND CantidadRecibida IS NULL AND Discrepancia IS NULL)
        ),

        -- Si guardamos Discrepancia como dato físico (no calculado), SQL
        -- Server debe impedir que se guarde un valor matemáticamente
        -- incorrecto respecto a CantidadEsperada y CantidadRecibida.
        CONSTRAINT CK_MovInventario_Discrepancia CHECK (
            Origen <> N'RECEPCION_CD'
            OR Discrepancia = CantidadEsperada - CantidadRecibida
        ),

        -- RN-013: el signo de Cantidad no es libre — depende de qué
        -- contador afecta cada tipo de movimiento (tabla 01_procesos_y_reglas.md,
        -- sección 4.3). RESERVA y LIBERACION_RESERVA nunca tocan el stock
        -- sistema, solo el stock reservado, así que su signo se define por
        -- ese efecto, no por la idea genérica de "ingreso/salida física".
        CONSTRAINT CK_MovInventario_SignoCantidad CHECK (
            (TipoMovimiento = N'INGRESO' AND Cantidad > 0)
            OR (TipoMovimiento = N'RESERVA' AND Cantidad > 0)
            OR (TipoMovimiento = N'LIBERACION_RESERVA' AND Cantidad < 0)
            OR (TipoMovimiento = N'DESCUENTO_DEFINITIVO' AND Cantidad < 0)
            OR (TipoMovimiento = N'AJUSTE' AND Cantidad <> 0)   -- signo libre: el conteo físico puede dar sobrante o faltante, pero nunca cero
        )
    );
END
GO

-- Índice sobre SKUID + TiendaID: el cálculo de stock disponible
-- (stock sistema - stock reservado) requiere sumar movimientos filtrando
-- por SKU y tienda constantemente — es la consulta más frecuente que
-- va a recibir esta tabla.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_MovInventario_SKU_Tienda'
    AND object_id = OBJECT_ID(N'dbo.FactMovimientoInventario')
)
BEGIN
    CREATE INDEX IX_MovInventario_SKU_Tienda
        ON dbo.FactMovimientoInventario (SKUID, TiendaID);
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
WHERE t.name = N'FactMovimientoInventario'
ORDER BY c.column_id;
GO