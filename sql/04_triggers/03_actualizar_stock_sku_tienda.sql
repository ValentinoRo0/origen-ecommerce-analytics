/*
===============================================================================
ORIGEN — Trigger: sincronización de StockSKUTienda
Fase 3 — Implementación SQL Server
===============================================================================
Se dispara con cada INSERT en FactMovimientoInventario y actualiza la fila
resumen correspondiente en StockSKUTienda.

CORRECCIÓN IMPORTANTE respecto a la versión anterior: un CTE (WITH ... AS)
en SQL Server solo es válido para la sentencia inmediatamente siguiente —
no se puede definir un CTE, usarlo en un IF EXISTS, y luego volver a
referenciarlo en un UPDATE posterior; la segunda referencia falla con
"Invalid object name". La versión anterior tenía exactamente ese error y
no habría llegado a ejecutarse. Se reemplaza el CTE por una VARIABLE DE
TABLA (@Efectos), que sí persiste durante toda la ejecución del trigger y
puede consultarse tantas veces como haga falta.

Con la pre-siembra obligatoria (Fase 4 carga una fila 0/0 por cada
combinación válida SKU×Tienda antes de simular pedidos — ver
02_tables/09_stock_sku_tienda.sql), este trigger NO crea filas nuevas.
Si un movimiento llega para una combinación inexistente, es un problema
de datos/configuración y se detiene con un error explícito.

Efecto de cada TipoMovimiento sobre los dos contadores (signo ya correcto
en Cantidad, según CK_MovInventario_SignoCantidad):
- INGRESO               → +StockSistema
- AJUSTE                → ±StockSistema
- RESERVA               → +StockReservado
- LIBERACION_RESERVA    → -StockReservado
- DESCUENTO_DEFINITIVO  → -StockSistema Y -StockReservado (misma Cantidad)
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.trg_ActualizarStockSKUTienda', N'TR') IS NOT NULL
    DROP TRIGGER dbo.trg_ActualizarStockSKUTienda;
GO

CREATE TRIGGER dbo.trg_ActualizarStockSKUTienda
ON dbo.FactMovimientoInventario
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Variable de tabla: a diferencia de un CTE, persiste durante toda la
    -- ejecución del trigger, así que puede usarse tanto en la validación
    -- como en el UPDATE posterior.
    DECLARE @Efectos TABLE
    (
        SKUID               INT NOT NULL,
        TiendaID            INT NOT NULL,
        DeltaStockSistema   INT NOT NULL,
        DeltaStockReservado INT NOT NULL,
        PRIMARY KEY (SKUID, TiendaID)
    );

    -- Agregamos por SKU+Tienda antes de aplicar el cambio, para no perder
    -- movimientos si se insertan varias filas en una sola sentencia.
    INSERT INTO @Efectos (SKUID, TiendaID, DeltaStockSistema, DeltaStockReservado)
    SELECT
        SKUID,
        TiendaID,
        SUM(CASE
                WHEN TipoMovimiento IN (N'INGRESO', N'AJUSTE', N'DESCUENTO_DEFINITIVO')
                THEN Cantidad ELSE 0
            END),
        SUM(CASE
                WHEN TipoMovimiento IN (N'RESERVA', N'LIBERACION_RESERVA', N'DESCUENTO_DEFINITIVO')
                THEN Cantidad ELSE 0
            END)
    FROM inserted
    GROUP BY SKUID, TiendaID;

    -- Validación de integridad: con pre-siembra, toda combinación SKU+Tienda
    -- que reciba un movimiento DEBE existir ya en StockSKUTienda.
    IF EXISTS (
        SELECT 1
        FROM @Efectos e
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.StockSKUTienda s
            WHERE s.SKUID = e.SKUID AND s.TiendaID = e.TiendaID
        )
    )
    BEGIN
        RAISERROR(N'Movimiento de inventario registrado para una combinación SKU+Tienda no presembrada en StockSKUTienda.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    UPDATE s
    SET
        s.StockSistema   = s.StockSistema + e.DeltaStockSistema,
        s.StockReservado = s.StockReservado + e.DeltaStockReservado
    FROM dbo.StockSKUTienda s
    INNER JOIN @Efectos e
        ON e.SKUID = s.SKUID AND e.TiendaID = s.TiendaID;
END
GO
