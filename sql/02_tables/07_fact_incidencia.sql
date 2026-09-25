/*
===============================================================================
ORIGEN — Tabla de hechos: FactIncidencia
Fase 3 — Implementación SQL Server
===============================================================================
Referencia: 02_modelo_de_datos.md, sección 4.4. Reglas: RN-003, RN-004,
RN-019 a RN-022 (01_procesos_y_reglas.md, sección 6).

Grano: 1 fila = 1 incidencia puntual (no incluye incidencias de monitoreo,
que se calculan en Fase 6 a partir de KPIs — Fase 2, sección 4.6).

Regla de integridad clave (Fase 2, sección 4.4): exactamente una de
LineaID / MovimientoID debe estar poblada, según TipoIncidencia:
- no_encontrado / cantidad_insuficiente / dañado  → nace de un pedido (LineaID)
- recepcion_incompleta                            → nace de una recepción (MovimientoID)
Ambas referencias viven en la misma fila, así que esta regla SÍ puede
expresarse como CHECK (no requiere consultar otra tabla).
===============================================================================
*/

USE OrigenDB;
GO

IF OBJECT_ID(N'dbo.FactIncidencia', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.FactIncidencia
    (
        IncidenciaID        INT             IDENTITY(1,1) NOT NULL,
        TipoIncidencia       VARCHAR(25)     NOT NULL,

        LineaID              INT             NULL,   -- poblado solo si TipoIncidencia ∈ {no_encontrado, cantidad_insuficiente, dañado}
        MovimientoID         INT             NULL,   -- poblado solo si TipoIncidencia = recepcion_incompleta

        MotivoID             INT             NOT NULL,
        AreaAtencionID       INT             NOT NULL,   -- primer respondedor (Fase 1, sección 6.1) — casi siempre Tienda/Picking
        AreaEscaladaID       INT             NULL,       -- poblado solo si hubo escalamiento (RN-019)

        FechaID              INT             NOT NULL,
        FechaDeteccion       DATETIME2(0)    NOT NULL,
        EstadoResolucion     VARCHAR(15)     NOT NULL,   -- en_atencion / resuelta / escalada / no_resuelta
        FechaResolucion      DATETIME2(0)    NULL,       -- poblado solo cuando EstadoResolucion es un desenlace final

        CONSTRAINT PK_FactIncidencia PRIMARY KEY (IncidenciaID),

        CONSTRAINT FK_Incidencia_Linea FOREIGN KEY (LineaID)
            REFERENCES dbo.FactPedidoDetalle (LineaID),
        CONSTRAINT FK_Incidencia_Movimiento FOREIGN KEY (MovimientoID)
            REFERENCES dbo.FactMovimientoInventario (MovimientoID),
        CONSTRAINT FK_Incidencia_Motivo FOREIGN KEY (MotivoID)
            REFERENCES dbo.DimMotivo (MotivoID),
        CONSTRAINT FK_Incidencia_AreaAtencion FOREIGN KEY (AreaAtencionID)
            REFERENCES dbo.DimArea (AreaID),
        CONSTRAINT FK_Incidencia_AreaEscalada FOREIGN KEY (AreaEscaladaID)
            REFERENCES dbo.DimArea (AreaID),
        CONSTRAINT FK_Incidencia_Fecha FOREIGN KEY (FechaID)
            REFERENCES dbo.DimFecha (FechaID),

        -- Restringe TipoIncidencia a los 4 valores puntuales definidos
        -- en 01_procesos_y_reglas.md, sección 6.2 (excluye monitoreo)
        CONSTRAINT CK_Incidencia_Tipo CHECK (TipoIncidencia IN
            (N'no_encontrado', N'cantidad_insuficiente', N'dañado', N'recepcion_incompleta')),

        -- Restringe EstadoResolucion a los 4 estados del flujo de
        -- escalamiento (Fase 1, sección 6.4)
        CONSTRAINT CK_Incidencia_EstadoResolucion CHECK (EstadoResolucion IN
            (N'en_atencion', N'resuelta', N'escalada', N'no_resuelta')),

        -- Regla de integridad central de esta tabla: exactamente un origen,
        -- nunca ambos ni ninguno, según el tipo de incidencia.
        CONSTRAINT CK_Incidencia_OrigenSegunTipo CHECK (
            (TipoIncidencia = N'recepcion_incompleta' AND MovimientoID IS NOT NULL AND LineaID IS NULL)
            OR
            (TipoIncidencia <> N'recepcion_incompleta' AND LineaID IS NOT NULL AND MovimientoID IS NULL)
        ),

        -- Mientras la incidencia sigue "en atención" (primer nivel, tienda/
        -- picking), todavía no pudo haberse escalado.
        CONSTRAINT CK_Incidencia_AreaEscaladaSegunEstado CHECK (
            EstadoResolucion <> N'en_atencion' OR AreaEscaladaID IS NULL
        ),

        -- FechaResolucion solo tiene sentido cuando la incidencia llegó a
        -- un desenlace final (resuelta o no_resuelta) — mientras está en
        -- atención o escalada, todavía no hay fecha de cierre.
        CONSTRAINT CK_Incidencia_FechaResolucionSegunEstado CHECK (
            (EstadoResolucion IN (N'resuelta', N'no_resuelta') AND FechaResolucion IS NOT NULL)
            OR
            (EstadoResolucion IN (N'en_atencion', N'escalada') AND FechaResolucion IS NULL)
        )
    );
END
GO

-- Índice sobre LineaID: para responder rápido "¿esta línea tuvo
-- incidencias?" al calcular la matriz de causas en Fase 6.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_Incidencia_LineaID'
    AND object_id = OBJECT_ID(N'dbo.FactIncidencia')
)
BEGIN
    CREATE INDEX IX_Incidencia_LineaID
        ON dbo.FactIncidencia (LineaID);
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
WHERE t.name = N'FactIncidencia'
ORDER BY c.column_id;
GO