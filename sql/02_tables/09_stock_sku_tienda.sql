/*
===============================================================================
ORIGEN — Tabla de apoyo: StockSKUTienda
Fase 3 — Implementación SQL Server
===============================================================================
IMPORTANTE: esta tabla NO es una de las 8 dimensiones ni de las 5 tablas de
hechos definidas en 02_modelo_de_datos.md. No representa una regla de
negocio nueva (no es RN-031) — es un mecanismo de IMPLEMENTACIÓN para
resolver RN-002 (reserva atómica) bajo concurrencia real.

Por qué existe: FactMovimientoInventario es un ledger — el stock disponible
se calcula sumando movimientos, no leyendo una fila fija. Eso significa que
no hay ninguna fila que SQL Server pueda "bloquear" para evitar que dos
compras simultáneas por la última unidad lean el mismo resultado antes de
que ninguna haya escrito todavía. StockSKUTienda es una tabla resumen — una
fila por SKU+Tienda — que sí se puede bloquear con UPDLOCK/ROWLOCK.

FactMovimientoInventario sigue siendo la ÚNICA fuente de verdad histórica
(auditoría, RN-013). Esta tabla es una caché operativa que se mantiene
sincronizada automáticamente por trigger (ver 04_triggers/03) cada vez que
se inserta un movimiento — nunca se actualiza a mano.

REQUISITO OPERATIVO PARA FASE 4: para que el bloqueo funcione incluso en la
primera compra de un SKU en una tienda (evitar una "carrera de inserción"
donde dos transacciones intenten crear la fila al mismo tiempo), Fase 4
debe precargar una fila con StockSistema=0 y StockReservado=0 para CADA
combinación válida de SKU × Tienda antes de simular ningún pedido. Sin esto,
el mecanismo de bloqueo tiene un hueco en el caso "primera vez".
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.StockSKUTienda', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.StockSKUTienda
    (
        SKUID           INT NOT NULL,
        TiendaID        INT NOT NULL,
        StockSistema    INT NOT NULL DEFAULT (0),
        StockReservado  INT NOT NULL DEFAULT (0),

        CONSTRAINT PK_StockSKUTienda PRIMARY KEY (SKUID, TiendaID),

        CONSTRAINT FK_StockSKUTienda_SKU FOREIGN KEY (SKUID)
            REFERENCES dbo.DimSKU (SKUID),
        CONSTRAINT FK_StockSKUTienda_Tienda FOREIGN KEY (TiendaID)
            REFERENCES dbo.DimTienda (TiendaID),

        -- RN-015: el stock sistema nunca puede ser negativo
        CONSTRAINT CK_StockSKUTienda_StockNoNegativo CHECK (StockSistema >= 0),

        -- El stock reservado nunca puede ser negativo
        CONSTRAINT CK_StockSKUTienda_ReservadoNoNegativo CHECK (StockReservado >= 0),

        -- Invariante central: nunca se puede reservar más de lo que existe
        -- en el sistema (si esto se violara, stock disponible sería
        -- negativo, que es precisamente lo que RN-002 debe evitar)
        CONSTRAINT CK_StockSKUTienda_ReservadoNoExcedeSistema CHECK (StockReservado <= StockSistema)
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
WHERE t.name = N'StockSKUTienda'
ORDER BY c.column_id;
GO
