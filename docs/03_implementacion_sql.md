# ORIGEN — Implementación SQL Server
## Fase 3 🟡 En progreso — Parte 1: Base de datos, dimensiones y hechos

---

## 1. Propósito del documento

Este documento explica las decisiones de diseño detrás de los scripts en `sql/`. Los archivos `.sql` contienen comentarios de código (qué hace cada bloque); este documento explica las decisiones de arquitectura que no caben cómodamente como comentario en el código — por qué se eligió una restricción y no otra, y qué reglas de negocio quedan deliberadamente fuera del alcance de un `CHECK`.

---

## 2. Base de datos

`sql/01_database/01_create_database.sql` crea `OrigenDB` con collation `Modern_Spanish_100_CI_AS` (case-insensitive, sensible a tildes, familia de reglas de ordenación moderna desde SQL Server 2008). El script usa `IF DB_ID(...) IS NULL` para ser idempotente — se puede volver a ejecutar sin fallar si la base ya existe.

---

## 3. Dimensiones (8 tablas — completas)

| Tabla | Script | Decisión destacada |
|---|---|---|
| `DimProducto` | `02_tables/01_dim_producto_sku.sql` | Separada de `DimSKU` para no repetir nombre/categoría/marca por cada variante |
| `DimSKU` | `02_tables/01_dim_producto_sku.sql` | `CodigoSKU` es atributo único del negocio (`VARCHAR(10)`), **no** la clave primaria — la PK técnica es `SKUID` (surrogate key) |
| `DimTienda` | `02_tables/02_dim_tienda_cliente_fecha.sql` | `Distrito` permite `NULL`, `Ciudad` no — solo se exige lo que el negocio realmente requiere |
| `DimCliente` | `02_tables/02_dim_tienda_cliente_fecha.sql` | `Email` sin `UNIQUE` — no hay ninguna regla de negocio de Fase 1 que identifique al cliente por su correo; agregar esa restricción habría sido una suposición no pedida |
| `DimFecha` | `02_tables/02_dim_tienda_cliente_fecha.sql` | `FechaID` = fecha en formato `AAAAMMDD`, no `IDENTITY` — convención estándar de modelado dimensional que permite filtrar por rango de fecha sin unir contra la tabla. Incluye `EsCampania`/`NombreCampania` para responder las preguntas de negocio sobre campañas |
| `DimEstado` | `02_tables/03_dim_estado_area_motivo.sql` | `EsFinal` replica el atributo ya definido en la tabla de estados de Fase 1 (sección 3.2) |
| `DimArea` | `02_tables/03_dim_estado_area_motivo.sql` | Las áreas de la matriz de resolución (Fase 1, sección 6.3) |
| `DimMotivo` | `02_tables/03_dim_estado_area_motivo.sql` | Tabla compartida entre 4 contextos (`incidencia`/`cancelacion`/`ajuste_stock`/`devolucion`), restringida con `CHECK` sobre `TipoMotivo` |

---

## 4. Tablas de hechos (5 tablas — completas)

### 4.1. `FactPedidoDetalle`

`02_tables/04_fact_pedido_detalle.sql`. Grano: 1 línea de pedido × SKU.

- `TiendaID` permite `NULL`: un pedido `Rechazado` (RN-001) nunca llega a asignarse a una tienda para picking, pero sí debe existir la fila — representa demanda insatisfecha (Fase 1, sección 2.2).
- `CHECK (Cantidad > 0)` y `CHECK (Canal IN ('despacho', 'recojo'))`.
- No existe tabla de cabecera de pedido separada (Fase 2, sección 4.7) — repetir cliente/fecha/canal por línea es aceptable a esta escala.

### 4.2. `FactHistorialEstadoLinea`

`02_tables/05_fact_historial_estado_linea.sql`. Grano: 1 transición de estado.

- Es la fuente de verdad de la trayectoria del pedido (RN-008/RN-028). `EstadoActualID` en `FactPedidoDetalle` es una copia rápida del último estado, no un reemplazo de este historial.
- Índice `(LineaID)`: la consulta más frecuente sobre esta tabla es "todo el historial de esta línea", indispensable para calcular tiempos de picking y SLA.

### 4.3. `FactMovimientoInventario`

`02_tables/06_fact_movimiento_inventario.sql`. Grano: 1 movimiento individual (`MovimientoID` propio, no la combinación SKU+Tienda+Tipo+Fecha).

Es la tabla con más restricciones del modelo, porque sostiene directamente RN-010 a RN-015:

- `CK_MovInventario_CamposRecepcion`: los campos de recepción (`CantidadEsperada`, `CantidadRecibida`, `Discrepancia`) vienen todos juntos o ninguno, según `Origen`.
- `CK_MovInventario_Discrepancia`: `Discrepancia` debe ser exactamente `CantidadEsperada − CantidadRecibida` — impide guardar un valor matemáticamente incorrecto.
- `CK_MovInventario_SignoCantidad`: el signo de `Cantidad` depende de qué contador afecta cada tipo de movimiento (tabla de RN-013 en Fase 1, sección 4.3) — `RESERVA`/`LIBERACION_RESERVA` solo afectan al stock reservado, nunca al stock sistema, así que su signo no sigue la lógica genérica de "ingreso/salida física".
- Índice compuesto `(SKUID, TiendaID)`: el cálculo de stock disponible siempre filtra por ambos a la vez.

**Deliberadamente fuera de los `CHECK`**: que `LineaID` esté poblado solo para `RESERVA`/`LIBERACION_RESERVA`/`DESCUENTO_DEFINITIVO` — se resuelve con lógica procedural (sección 6), no con un constraint declarativo, para no mezclar dos dimensiones de validación distintas (recepción vs. tipo de movimiento) en un mismo `CHECK`.

### 4.4. `FactIncidencia`

`02_tables/07_fact_incidencia.sql`. Grano: 1 incidencia puntual (excluye monitoreo — sección 5).

- `CK_Incidencia_OrigenSegunTipo`: exactamente una de `LineaID`/`MovimientoID` según `TipoIncidencia` — `recepcion_incompleta` nace de un movimiento, las otras tres nacen de una línea de pedido.
- `CK_Incidencia_AreaEscaladaSegunEstado` y `CK_Incidencia_FechaResolucionSegunEstado`: coherencia entre el estado de resolución y los campos que solo tienen sentido en ciertos estados.
- Índice `(LineaID)`: para el análisis de causas de Fase 6.

### 4.5. `FactDevolucion`

`02_tables/08_fact_devolucion.sql`. Grano: 1 devolución, vinculada a una línea `Completada`.

Es la tabla con menos `CHECK` de las 5, porque sus dos reglas más importantes (RN-026: la línea debe estar Completada; RN-027: dentro de la ventana de devolución) requieren consultar el estado de **otra tabla** — no pueden expresarse como `CHECK` (ver sección 5).

---

## 5. Reglas que NO se implementaron como `CHECK` (y por qué)

Un `CHECK` en SQL Server solo puede validar columnas de la **misma fila**. Toda regla que necesita comparar contra otra tabla queda pendiente para la siguiente parte de esta fase (stored procedures, triggers o lógica transaccional):

| Regla | Por qué no es un `CHECK` | Dónde se resuelve |
|---|---|---|
| `MotivoCancelacionID` debe tener `TipoMotivo = 'cancelacion'` en `DimMotivo` | Compara contra otra tabla | Procedimiento/trigger de cancelación |
| `EstadoActualID` en `FactPedidoDetalle` debe reflejar la última fila de `FactHistorialEstadoLinea` | Compara contra otra tabla | Trigger o procedimiento al insertar en el historial |
| `LineaID` en `FactMovimientoInventario` poblado solo para ciertos `TipoMovimiento` | Aunque es la misma tabla, se decidió no mezclarlo con el `CHECK` de recepción por claridad | Procedimiento de inserción de movimientos |
| La línea de `FactDevolucion` debe estar en estado `Completado` (RN-026) | El estado vive en otra tabla | Procedimiento de registro de devolución |
| `FechaDevolucion` dentro de la ventana de devolución (RN-027) | La fecha de completado vive en `FactHistorialEstadoLinea` | Procedimiento de registro de devolución |

Ninguna de estas reglas se pierde — quedan documentadas aquí para no olvidarlas al construir la sección 6.

---

## 6. Siguiente paso

Con las 8 dimensiones y 5 tablas de hechos creadas, sigue: constraints cruzados vía trigger/procedimiento (tabla de la sección 5), la sincronización de `EstadoActualID`, las transacciones críticas (reserva atómica RN-002, descuento definitivo), y finalmente las views de consumo analítico. Se documentan en la Parte 2 de este archivo cuando se construyan.