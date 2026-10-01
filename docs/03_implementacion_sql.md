# ORIGEN — Implementación SQL Server
## Fase 3 ✅ VALIDADA — Base de datos, dimensiones, hechos, flujo de estados, vistas analíticas y pruebas

> **Estado: Fase 3 — Estado: VALIDADA.** La capa analítica SQL (6 vistas) está implementada y validada con `sql/07_tests/test_vistas.sql` (**60/60 PASS, 0 FAIL**, prueba de solo lectura). La Fase 4 (datos operativos y escenarios) **no** está completada, ni el proyecto completo.

---

---

## 1. Propósito del documento

Este documento explica las decisiones de diseño detrás de los scripts en `sql/`. Los archivos `.sql` contienen comentarios de código (qué hace cada bloque); este documento explica las decisiones de arquitectura que no caben cómodamente como comentario en el código — por qué se eligió una restricción y no otra, y qué reglas de negocio quedan deliberadamente fuera del alcance de un `CHECK`.

---

## 2. Base de datos

`sql/01_database/01_create_database.sql` crea `OrigenDB` con collation `Modern_Spanish_100_CI_AS` (case-insensitive, sensible a tildes, familia de reglas de ordenación moderna desde SQL Server 2008). El script usa `IF DB_ID(...) IS NULL` para ser idempotente — se puede volver a ejecutar sin fallar si la base ya existe.

### 2.1. Capas de scripts (estado real tras el cierre de Fase 3)

| Carpeta | Contenido | Estado |
|---|---|---|
| `sql/01_database/` | `01_create_database.sql` — creación de `OrigenDB` | Implementado |
| `sql/02_tables/` | 9 scripts → **14 tablas**: 8 dimensiones (§3), 5 hechos (§4) y `StockSKUTienda` (§4.6) | Implementado |
| `sql/03_constraints/` | `01_movimiento_linea_segun_tipo.sql` (`CK_MovInventario_LineaSegunTipo`); el resto de restricciones viven dentro de los scripts de cada tabla. En total la BD tiene **16 restricciones `CHECK`** y **26 claves foráneas** (catálogo real) | Implementado |
| `sql/04_triggers/` | **2 triggers**: `trg_ActualizarEstadoActual` y `trg_ActualizarStockSKUTienda` (§6.1) | Implementado |
| `sql/05_stored_procedures/` | **14 stored procedures** del flujo de estados (§6.2) + scripts de pruebas (`02`, `08`, `09`, `18`) | Implementado |
| `sql/06_seed_data/` | `01_datos_maestros.sql` (datos maestros de las dimensiones) y `02_presiembra_stock_sku_tienda.sql` (presiembra de `StockSKUTienda`); decisiones documentadas en `04_datos_operativos.md` | Implementado |
| `sql/06_views/` | **6 vistas analíticas** (`01` a `06`) — §7 | Implementado y validado |
| `sql/07_tests/` | `test_vistas.sql` (§8, ejecutado: 60/60 PASS), `test_concurrencia_picking.sql` y `test_concurrencia_stock.sql` | Ejecutado (ver §8) |

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

### 4.6. `StockSKUTienda`

`02_tables/09_stock_sku_tienda.sql`. Grano: 1 fila por SKU × Tienda (56 filas con el seed actual: 14 SKU × 4 tiendas).

- Es el **resumen** de stock actual que consulta la operación; la fuente de verdad del stock sigue siendo el ledger `FactMovimientoInventario` (RN-013). No es una tabla de hechos transaccional, por eso se documenta aparte de las 5 anteriores.
- Tres restricciones: `CK_StockSKUTienda_StockNoNegativo`, `CK_StockSKUTienda_ReservadoNoNegativo` y `CK_StockSKUTienda_ReservadoNoExcedeSistema`.
- Se mantiene únicamente mediante `trg_ActualizarStockSKUTienda` (§6.1): ningún stored procedure hace `UPDATE` directo sobre ella.
- Es la tabla contra la que se reconcilia `vw_StockHistorico` (§7.5): **0 discrepancias**.

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

### 6.1. Triggers

La fase implementa exactamente **dos** triggers (verificados en catálogo: no hay ningún otro).

#### `dbo.trg_ActualizarEstadoActual` — sincronización de `EstadoActualID`

`sql/04_triggers/04_actualizar_estado_actual.sql`. Trigger `AFTER INSERT` sobre `FactHistorialEstadoLinea`: por cada inserción en el historial, actualiza `FactPedidoDetalle.EstadoActualID` con el estado insertado para esa línea.

Su responsabilidad es exactamente esa — y solo esa: **mantener la copia denormalizada al día**. Los stored procedures nunca escriben `EstadoActualID` a mano; validan la transición contra la última fila del historial (la fuente de verdad) y registran el cambio allí, y el trigger propaga el resultado a la copia. Así la sincronización vive en un solo punto en lugar de duplicarse en cada procedimiento.

Decisiones de diseño: agrupa las filas `inserted` por `LineaID` (soporta inserciones multi-fila en una sola sentencia); el estado nuevo se toma por orden de inserción (`HistorialID`), **no** por `MAX(FechaHora)`, para no degradar registros con fechas históricas; se ejecuta dentro de la transacción del procedimiento que hizo el INSERT (si ese hace ROLLBACK, el UPDATE se revierte con él); no hay recursividad porque solo actualiza `FactPedidoDetalle`.

#### `dbo.trg_ActualizarStockSKUTienda` — resumen de stock por SKU/tienda

`sql/04_triggers/03_actualizar_stock_sku_tienda.sql`. Se dispara con cada `INSERT` en `FactMovimientoInventario` y actualiza la fila resumen correspondiente de `StockSKUTienda`, aplicando el efecto de cada `TipoMovimiento` sobre los dos contadores (el signo de `Cantidad` ya es correcto según `CK_MovInventario_SignoCantidad`, RN-013):

| TipoMovimiento | Efecto |
|---|---|
| `INGRESO` | `+StockSistema` |
| `AJUSTE` | `±StockSistema` |
| `RESERVA` | `+StockReservado` |
| `LIBERACION_RESERVA` | `−StockReservado` |
| `DESCUENTO_DEFINITIVO` | `−StockSistema` **y** `−StockReservado` (misma `Cantidad`) |

Decisiones de diseño: **no crea filas** — exige que la combinación SKU×Tienda exista pre-sembrada y, si no existe, se detiene con un error explícito (problema de datos/configuración, no "stock 0"); usa una variable de tabla en lugar de un CTE porque un CTE solo es válido para la sentencia inmediatamente siguiente; ningún stored procedure escribe `StockSKUTienda` a mano: el ledger es la fuente de verdad y el trigger propaga su efecto.

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

## 7. Vistas analíticas (capa de consumo)

`sql/06_views/` — **6 vistas**, creadas con la convención del repo: `USE OrigenDB; GO` + `IF OBJECT_ID(..., 'V') IS NOT NULL DROP VIEW ...` + `CREATE VIEW` (sin `CREATE OR ALTER`). Son una capa **descriptiva de consumo**: no implementan SLA, ni KPIs, ni tasas, ni porcentajes, ni clasificaciones — eso pertenece a fases posteriores.

### 7.1. `vw_PedidosOperaciones` (`06_views/01_vw_pedidos_operaciones.sql`)

- **Grano**: 1 fila por `LineaID`.
- **Propósito**: operación de pedidos — estado actual y si es final, cancelación (`Cancelada`, coherente con `DimEstado.NombreEstado = 'Cancelado'`), motivo de cancelación e incidencias de la línea (`NIncidencias`, `TieneIncidencia`, `TipoIncidencia`, `MotivoIncidencia`, agregadas con `OUTER APPLY` para preservar las líneas sin incidencia).
- Las cancelaciones se reportan con `COUNT` + `STRING_AGG` de motivos distintos: no se elige un motivo arbitrario cuando una línea tiene varios.

### 7.2. `vw_TiemposEstados` (`06_views/02_vw_tiempos_estados.sql`)

- **Grano**: 1 episodio de estado por `HistorialID` (un registro de `FactHistorialEstadoLinea`) — no 1 fila por `LineaID`×`EstadoID`, porque los reingresos a un mismo estado son reales en los datos.
- **Propósito**: entrada (`FechaEntrada` = `FechaHora`), salida (`FechaSalida` = `LEAD(FechaHora)` por `LineaID`) y duración de cada estado (`DuracionMinutos`). El último episodio de cada línea queda con `FechaSalida`/`DuracionMinutos` en `NULL`.
- **No implementa SLA**: no hay niveles, ventanas ni criticidad; solo mide duraciones.

### 7.3. `vw_IncidenciasPicking` (`06_views/03_vw_incidencias_picking.sql`)

- **Grano**: 1 fila por `IncidenciaID`.
- **Propósito**: análisis descriptivo y trazabilidad de incidencias — motivo (`DimMotivo`), área de atención y área escalada (`DimArea`), fechas de detección/resolución (`FechaHoraDeteccion`/`FechaHoraResolucion`), duración y estados de resolución.
- Usa `LEFT JOIN` contra `FactPedidoDetalle` para preservar las incidencias de recepción cuya `LineaID` es `NULL`.

### 7.4. `vw_MovimientosInventario` (`06_views/04_vw_movimientos_inventario.sql`)

- **Grano**: 1 fila por `MovimientoID`.
- **Propósito**: ledger analítico completo de movimientos, con sus dimensiones y los campos de recepción (`CantidadEsperada`, `CantidadRecibida`, `Discrepancia`) tal como están en la base.
- **Mantiene los signos almacenados**: `Cantidad` se expone con el signo del ledger, sin `ABS`.

### 7.5. `vw_StockHistorico` (`06_views/05_vw_stock_historico.sql`)

- **Grano**: 1 fila por `SKU × Tienda × Fecha` — grilla densa sobre `DimSKU × DimTienda × DimFecha` (5040 filas = 14 × 4 × 90 con el seed actual).
- **Reconstrucción desde `FactMovimientoInventario`** (el ledger es la fuente de verdad, RN-013). **No utiliza `StockSKUTienda` dentro de la definición** — esa tabla entra únicamente en la reconciliación externa (§8).
- Fórmulas (RN-013, `DESCUENTO_DEFINITIVO` afecta a **ambos** contadores):
  - `StockSistema` ← `INGRESO` + `AJUSTE` + `DESCUENTO_DEFINITIVO`
  - `StockReservado` ← `RESERVA` + `LIBERACION_RESERVA` + `DESCUENTO_DEFINITIVO`
  - `StockDisponible = StockSistema − StockReservado`
- **Reconciliación final contra `StockSKUTienda` (último día): 0 discrepancias.**

### 7.6. `vw_Devoluciones` (`06_views/06_vw_devoluciones.sql`)

- **Grano**: 1 fila por `DevolucionID`.
- `FactDevolucion` está **vacía en el seed actual** → la vista devuelve 0 filas por ahora; es esperado, no un fallo.
- **No existe una FK modelada entre `FactDevolucion` y `FactMovimientoInventario`**, y tampoco una cantidad devuelta en la tabla — por eso **no se infiere** un movimiento de reingreso de stock ni se inventa una columna de cantidad: se expone `CantidadLinea` (la cantidad de la línea pedida), sin relación con movimientos.

---

## 8. Pruebas

### 8.1. `sql/07_tests/test_vistas.sql` — test de regresión de la capa analítica

Batería de pruebas de **solo lectura** (exclusivamente `SELECT`, CTE, subconsultas, `JOIN` y `UNION ALL`: sin sentencias de escritura, sin tablas auxiliares, sin ejecución de procedimientos) que valida las 6 vistas. La salida usa el formato `Seccion | TestID | Vista | Validacion | Esperado | Obtenido | Estado` (`PASS`/`FAIL`), sin ocultar los valores reales.

**Resultado de la ejecución actual:**

| Métrica | Valor |
|---|---|
| Tests | **60** |
| PASS | **60** |
| FAIL | **0** |

→ `RESULTADO GLOBAL: PASS` (sección de cierre: `CAPA ANALITICA FASE 3: VALIDADA`).

Las validaciones incluyen:

- **Grano** de cada vista (conteo = clave/distinta) y prueba **global de duplicados** de los 6 granos.
- **Correspondencia base↔vista**: claves ausentes y claves extra, en las 6 vistas.
- **Dimensiones**: cliente, SKU/producto, tienda, fecha, estado, motivo y área contra sus `Dim*`.
- **Movimientos**: agregado independiente por `TipoMovimiento + Origen` con `COUNT(*)` y `SUM(Cantidad)` **sin cambiar signos ni usar `ABS`**.
- **Estados**: `FechaEntrada` vs `FechaHora`; `FechaSalida` vs `LEAD` recalculado independientemente; `DuracionMinutos` vs `DATEDIFF`; duraciones negativas; último episodio cerrado.
- **Incidencias**: motivo, área, área escalada, fechas, duración recalculada y `LineaID` opcional (los `NULL` de recepción no se marcan como error).
- **Reconstrucción histórica de stock**: conteo esperado calculado desde las dimensiones (sin hardcodear 5040), densidad por par SKU/tienda, movimientos diarios y acumulados recalculados desde el ledger, `StockDisponible = StockSistema − StockReservado`, y negativos (reportados, no corregidos: 0/0/0).
- **Reconciliación contra `StockSKUTienda`**: último día (`MAX(DimFecha)` calculado **sin usar la vista**) por SKU/tienda → **0 discrepancias**, más el caso semilla SKU 4 / Tienda 6 (`8 / 0 / 8`).
- **Devoluciones**: grano, `LineaID` y dimensiones — 0/0 con la base vacía, sin fabricar datos.

### 8.2. Otras pruebas de la fase

- `sql/07_tests/test_concurrencia_picking.sql` — su informe está en `docs/pruebas/prueba_concurrencia_picking.md`.
- `sql/07_tests/test_concurrencia_stock.sql`.
- Scripts de pruebas de los stored procedures en `05_stored_procedures/` (`02`, `08`, `09`, `18`).

---

## 9. Cierre

**Fase 3 — Estado: VALIDADA**

La capa analítica SQL está **implementada y validada**:

- Base de datos completa: creación de `OrigenDB`, 14 tablas, 16 restricciones `CHECK`, 26 claves foráneas, 2 triggers, 14 stored procedures y datos semilla/master (`06_seed_data/`).
- **6 vistas analíticas** en `sql/06_views/` (§7).
- **Prueba integral** `sql/07_tests/test_vistas.sql`: **60/60 PASS, 0 FAIL** (§8).

**No** se ha completado la Fase 4 (datos operativos y escenarios), ni el proyecto completo (ETL, análisis Python, KPIs, Power BI, hallazgos) — esos siguen siendo las etapas pendientes.

> **Nota de consistencia**: las cabeceras de los scripts de `sql/06_seed_data/` conservan la etiqueta "Fase 4" de la planificación original (bloques aprobados); unificar esa etiqueta con el alcance de cierre de la Fase 3 queda pendiente de decisión.