/*
===============================================================================
ORIGEN — Tabla de hechos: FactPedidoDetalle
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: 02_modelo_de_datos.md, sección 4.1.
Grano: 1 fila = 1 línea de pedido (Pedido × SKU).

Nota sobre pedidos Rechazados: una línea con EstadoActualID = 'Rechazado'
SÍ genera fila aquí (registra demanda insatisfecha, sección 2.2 de
01_procesos_y_reglas.md), pero nunca tiene un movimiento de RESERVA
asociado en FactMovimientoInventario, porque la reserva es precisamente
lo que falló. Por eso TiendaID permite NULL: un pedido rechazado nunca
llega a asignarse a una tienda para picking.
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.FactPedidoDetalle', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FactPedidoDetalle
    (
        LineaID             INT             IDENTITY(1,1) NOT NULL,
        PedidoID            INT             NOT NULL,   -- agrupa líneas del mismo pedido; no hay tabla de cabecera (Fase 2, sección 4.7)
        ClienteID           INT             NOT NULL,
        SKUID               INT             NOT NULL,
        TiendaID            INT             NULL,        -- NULL si la línea nunca llegó a asignarse (ej. Rechazado)
        FechaID             INT             NOT NULL,
        Canal               VARCHAR(10)     NOT NULL,
        Cantidad            INT             NOT NULL,
        EstadoActualID      INT             NOT NULL,   -- denormalizado; ver Fase 2, sección 4.7
        MotivoCancelacionID INT             NULL,        -- solo poblado si el estado actual es Cancelado

        CONSTRAINT PK_FactPedidoDetalle PRIMARY KEY (LineaID),

        CONSTRAINT FK_FactPedidoDetalle_Cliente FOREIGN KEY (ClienteID)
            REFERENCES dbo.DimCliente (ClienteID),
        CONSTRAINT FK_FactPedidoDetalle_SKU FOREIGN KEY (SKUID)
            REFERENCES dbo.DimSKU (SKUID),
        CONSTRAINT FK_FactPedidoDetalle_Tienda FOREIGN KEY (TiendaID)
            REFERENCES dbo.DimTienda (TiendaID),
        CONSTRAINT FK_FactPedidoDetalle_Fecha FOREIGN KEY (FechaID)
            REFERENCES dbo.DimFecha (FechaID),
        CONSTRAINT FK_FactPedidoDetalle_Estado FOREIGN KEY (EstadoActualID)
            REFERENCES dbo.DimEstado (EstadoID),
        CONSTRAINT FK_FactPedidoDetalle_MotivoCancelacion FOREIGN KEY (MotivoCancelacionID)
            REFERENCES dbo.DimMotivo (MotivoID),

        -- Cantidad debe ser positiva: una línea de pedido no puede pedir 0 o menos unidades
        CONSTRAINT CK_FactPedidoDetalle_Cantidad CHECK (Cantidad > 0),

        -- Canal restringido a los dos únicos valores definidos en Fase 0/1
        CONSTRAINT CK_FactPedidoDetalle_Canal CHECK (Canal IN (N'despacho', N'recojo'))
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
WHERE t.name = N'FactPedidoDetalle'
ORDER BY c.column_id;
GO