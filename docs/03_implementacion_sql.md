# ORIGEN — Implementación SQL Server
## Fase 3 🟡 En progreso — Base de datos, dimensiones, hechos y flujo de estados

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

**Fuera de los `CHECK`**: las reglas que comparan contra **otra tabla** — que `MotivoCancelacionID` sea de tipo `cancelacion`, que `EstadoActualID` refleje el historial, que la devolución sea sobre una línea `Completada` — se resuelven en la capa procedural/trigger (sección 5). En cambio, la regla de `LineaID` según `TipoMovimiento` SÍ es un `CHECK` (`CK_MovInventario_LineaSegunTipo`, `03_constraints/01_movimiento_linea_segun_tipo.sql`): ambos campos viven en la misma fila, como se detalla en la corrección registrada en ese archivo.

### 4.4. `FactIncidencia`

`02_tables/07_fact_incidencia.sql`. Grano: 1 incidencia puntual (excluye monitoreo — sección 5).

- `CK_Incidencia_OrigenSegunTipo`: exactamente una de `LineaID`/`MovimientoID` según `TipoIncidencia` — `recepcion_incompleta` nace de un movimiento, las otras tres nacen de una línea de pedido.
- `CK_Incidencia_AreaEscaladaSegunEstado` y `CK_Incidencia_FechaResolucionSegunEstado`: coherencia entre el estado de resolución y los campos que solo tienen sentido en ciertos estados.
- Índice `(LineaID)`: para el análisis de causas de Fase 6.

### 4.5. `FactDevolucion`

`02_tables/08_fact_devolucion.sql`. Grano: 1 devolución, vinculada a una línea `Completada`.

Es la tabla con menos `CHECK` de las 5, porque sus dos reglas más importantes (RN-026: la línea debe estar Completada; RN-027: dentro de la ventana de devolución) requieren consultar el estado de **otra tabla** — no pueden expresarse como `CHECK` (ver sección 5).

---

## 5. Reglas que NO se implementaron como `CHECK` (y dónde quedaron resueltas)

Un `CHECK` en SQL Server solo puede validar columnas de la **misma fila**. Estas reglas comparan contra otra tabla y se resuelven en la capa procedural/trigger, ya construida en esta fase:

| Regla | Por qué no es un `CHECK` | Dónde se resuelve (implementado) |
|---|---|---|
| `MotivoCancelacionID` debe tener `TipoMotivo = 'cancelacion'` en `DimMotivo` | Compara contra otra tabla | `sp_CancelarPedido` — validación previa, error 51030 |
| `EstadoActualID` en `FactPedidoDetalle` debe reflejar la última fila de `FactHistorialEstadoLinea` | Compara contra otra tabla | `trg_ActualizarEstadoActual` (sección 6.1) |
| La línea de `FactDevolucion` debe estar en estado `Completado` (RN-026) | El estado vive en otra tabla | `sp_RegistrarDevolucion` — error 51016, leyendo el historial |
| `FechaDevolucion` dentro de la ventana de devolución (RN-027) | La fecha de completado vive en `FactHistorialEstadoLinea` | `sp_RegistrarDevolucion` — error 51017 |

La cuarta regla que esta tabla listaba originalmente (`LineaID` poblado solo para ciertos `TipoMovimiento`) **sí** terminó como `CHECK` — `CK_MovInventario_LineaSegunTipo` en `03_constraints/01_movimiento_linea_segun_tipo.sql` — y se retiró de esta lista por esa razón.

---

## 6. Implementación transaccional

### 6.1. Sincronización de `EstadoActualID` — `dbo.trg_ActualizarEstadoActual`

`sql/04_triggers/04_actualizar_estado_actual.sql`. Trigger `AFTER INSERT` sobre `FactHistorialEstadoLinea`: por cada inserción en el historial, actualiza `FactPedidoDetalle.EstadoActualID` con el estado insertado para esa línea.

Su responsabilidad es exactamente esa — y solo esa: **mantener la copia denormalizada al día**. Los stored procedures nunca escriben `EstadoActualID` a mano; validan la transición contra la última fila del historial (la fuente de verdad) y registran el cambio allí, y el trigger propaga el resultado a la copia. Así la sincronización vive en un solo punto en lugar de duplicarse en cada procedimiento.

Decisiones de diseño: agrupa las filas `inserted` por `LineaID` (soporta inserciones multi-fila en una sola sentencia); el estado nuevo se toma por orden de inserción (`HistorialID`), **no** por `MAX(FechaHora)`, para no degradar registros con fechas históricas; se ejecuta dentro de la transacción del procedimiento que hizo el INSERT (si ese hace ROLLBACK, el UPDATE se revierte con él); no hay recursividad porque solo actualiza `FactPedidoDetalle`.

### 6.2. Stored procedures del flujo de estados

Cada procedimiento valida un **estado origen exacto** (leído de `FactHistorialEstadoLinea` dentro del bloqueo de la línea) y produce **un solo destino** registrado en el historial — no hay tabla genérica de transiciones ni framework de workflow. Sobre los procedimientos ya existentes (`sp_CrearPedido`, `sp_ConfirmarPicking`, `sp_RegistrarIncidenciaPicking`, `sp_CancelarPedido`, `sp_ProcesarVencimientosRecojo`, `sp_RegistrarDevolucion`), la máquina de estados se completó con:

| Procedimiento | Transición |
|---|---|
| `sp_AsignarPicking` | Pedido creado → Asignado a picking |
| `sp_IniciarPicking` | Asignado a picking → Picking en proceso |
| `sp_ResolverIncidencia` | Incidencia de picking → Picking en proceso |
| `sp_PrepararDespacho` | Empaquetado → En tránsito (solo canal `despacho`) |
| `sp_RegistrarEntrega` | En tránsito → Entregado |
| `sp_PrepararRecojo` | Empaquetado → Disponible para recojo (solo canal `recojo`) |
| `sp_RegistrarRecojo` | Disponible para recojo → Recojo por cliente |
| `sp_CompletarPedido` | Entregado \| Recojo por cliente → Completado |

El fork desde `Empaquetado` es el único punto donde el canal se valida explícitamente (error 51041): a partir de ahí, cada operación queda determinada por su estado origen. La devolución es un evento posterior a `Completado` (`FactDevolucion`) y no participa en la máquina de estados. El flujo completo y los errores de validación están en `01_procesos_y_reglas.md` (sección 3) y en las cabeceras de cada script.

---

## 7. Siguiente paso

Con el flujo de estados cerrado y probado (scripts `08`, `09` y `18` de `05_stored_procedures/`), sigue la capa de **views de consumo analítico** (`06_views/`) que alimentarán los KPIs y el modelo de Power BI.