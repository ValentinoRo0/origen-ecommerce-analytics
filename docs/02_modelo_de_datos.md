# ORIGEN — Modelo de Datos
## Fase 2 ✅ Completa

---

## 1. Propósito del documento

Este documento traduce los procesos y reglas de negocio definidos en `01_procesos_y_reglas.md` a un modelo de datos conceptual y lógico: qué entidades existen, qué grano tiene cada tabla de hechos, y cómo se relacionan entre sí.

No contiene código SQL (`CREATE TABLE`, tipos de dato exactos de motor, índices) — eso corresponde a `03_implementacion_sql.md`. Aquí se definen las decisiones de diseño; en Fase 3 se implementan.

---

## 2. Decisión de granularidad

**Confirmado por el usuario**: el inventario, el picking y las incidencias se registran a nivel de **Variante/SKU** (producto × talla × color), no a nivel de producto genérico.

**Consecuencia directa**: se separan dos dimensiones en lugar de una:

- `DimProducto` — el concepto comercial (ej. "Camisa Oxford": nombre, categoría, marca).
- `DimSKU` — la unidad real de inventario (esa camisa en una talla y color específicos), con `ProductoID` como FK hacia `DimProducto`.

**Motivo**: evita repetir nombre, categoría y marca en cada una de las variantes de un mismo producto, y refleja correctamente que el stock se agota por variante, no por producto completo.

### 2.1. Convención del código de SKU

El código de SKU visible (ej. `A58214`) es un **atributo del negocio**, único, pero **no es la clave primaria técnica** de `DimSKU`. La clave primaria es `SKUID`, un identificador interno simple (autoincremental) que usan las demás tablas para referenciar la fila.

- Formato único y consistente: una letra + 5 dígitos (ej. `A58214`), sin guiones y sin significado codificado (el código no debe poder "leerse" para inferir talla/color — esa información vive en las columnas de `DimSKU`, no en el código).
- Se almacena siempre como texto (no numérico), con restricción de unicidad (`UNIQUE`, a implementar en Fase 3).
- Motivo de usar una clave técnica (`SKUID`) separada del código de negocio: si el formato del código cambiara en el futuro, no obliga a reescribir las tablas de hechos que lo referencian.

---

## 3. Dimensiones

| Dimensión | Contenido | Notas |
|---|---|---|
| `DimProducto` | Producto comercial: nombre, categoría, marca | 1 fila = 1 producto |
| `DimSKU` | Variante concreta: código de SKU, talla, color, `ProductoID` (FK) | 1 fila = 1 SKU; grano del inventario |
| `DimTienda` | Tiendas de Origen | 1 fila = 1 tienda |
| `DimCliente` | Datos mínimos del cliente | Sin CRM — solo lo necesario para vincular pedido y devolución |
| `DimFecha` | Calendario, con marca de periodo de campaña | Conectada a casi todas las tablas de hechos (ver sección 5) |
| `DimEstado` | Los 14 estados de línea de pedido (Fase 1, sección 3.2), con indicador `EsFinal` | Estandariza el texto libre de estado |
| `DimArea` | Tienda/Picking, Operaciones E-commerce, Abastecimiento, CD | Áreas que aparecen como responsables en la matriz de resolución (Fase 1, sección 6.3) |
| `DimMotivo` | Todos los motivos del proyecto, con columna `TipoMotivo` (`incidencia` / `cancelacion` / `ajuste_stock` / `devolucion`) | Tabla compartida entre 4 contextos distintos — ver sección 4.6 |

**Excluidas deliberadamente**: `DimCanal` (solo dos modalidades — despacho/recojo — se maneja como atributo, no como dimensión propia) y `DimVariante` separado de `DimSKU` (sería un snowflake innecesario a esta escala).

---

## 4. Tablas de hechos

### 4.1. `FactPedidoDetalle`

**Grano**: 1 fila = 1 línea de pedido (Pedido × SKU).

| Columna | Tipo de referencia | Notas |
|---|---|---|
| `LineaID` | PK | |
| `PedidoID` | — | Agrupa líneas del mismo pedido (no existe tabla de cabecera separada — ver sección 4.7) |
| `ClienteID` | FK → `DimCliente` | |
| `SKUID` | FK → `DimSKU` | |
| `TiendaID` | FK → `DimTienda` | |
| `FechaID` | FK → `DimFecha` | Fecha de creación del pedido |
| `Canal` | — | `despacho` / `recojo` |
| `Cantidad` | — | |
| `EstadoActualID` | FK → `DimEstado` | Denormalizado — ver sección 4.5 |
| `MotivoCancelacionID` | FK → `DimMotivo` (nulo salvo cancelado) | |

### 4.2. `FactHistorialEstadoLinea`

**Grano**: 1 fila = 1 transición de estado de una línea de pedido.

| Columna | Tipo de referencia | Notas |
|---|---|---|
| `HistorialID` | PK | |
| `LineaID` | FK → `FactPedidoDetalle` | |
| `EstadoID` | FK → `DimEstado` | |
| `FechaID` | FK → `DimFecha` | |
| `FechaHora` | — | Timestamp completo, para precisión de hora |

Es la **fuente de verdad** de la trayectoria del pedido — de aquí se calculan tiempos de picking, cumplimiento de SLA y la brecha cancelación–notificación (Fase 1, RN-005/RN-008).

### 4.3. `FactMovimientoInventario`

**Grano**: 1 fila = 1 movimiento individual de inventario, identificado por `MovimientoID` propio (no por la combinación SKU+Tienda+Tipo+Fecha, que no garantiza unicidad).

| Columna | Tipo de referencia | Notas |
|---|---|---|
| `MovimientoID` | PK | |
| `SKUID` | FK → `DimSKU` | |
| `TiendaID` | FK → `DimTienda` | |
| `FechaID` | FK → `DimFecha` | |
| `FechaHora` | — | |
| `TipoMovimiento` | — | `INGRESO` / `RESERVA` / `LIBERACION_RESERVA` / `DESCUENTO_DEFINITIVO` / `AJUSTE` |
| `Origen` | — | Ej. `RECEPCION_CD`, `PEDIDO`, `CANCELACION`, `CONTEO_FISICO` |
| `Cantidad` | — | Con signo (+ ingreso, − salida) |
| `LineaID` | FK → `FactPedidoDetalle` (opcional) | Poblado solo cuando el movimiento es `RESERVA`, `LIBERACION_RESERVA` o `DESCUENTO_DEFINITIVO` |
| `CantidadEsperada` / `CantidadRecibida` / `Discrepancia` | — (opcional) | Poblados solo cuando `Origen = RECEPCION_CD` |
| `MotivoID` | FK → `DimMotivo` (opcional) | Poblado cuando `TipoMovimiento = AJUSTE` |

Incluye la recepción del CD como un caso particular de `INGRESO` — no existe una tabla `FactRecepcionCD` independiente (ver sección 4.7).

### 4.4. `FactIncidencia`

**Grano**: 1 fila = 1 incidencia puntual (no incluye incidencias de monitoreo — ver sección 4.6).

| Columna | Tipo de referencia | Notas |
|---|---|---|
| `IncidenciaID` | PK | |
| `TipoIncidencia` | — | `no_encontrado` / `cantidad_insuficiente` / `dañado` / `recepcion_incompleta` |
| `LineaID` | FK → `FactPedidoDetalle` (opcional) | Poblado si el tipo es `no_encontrado`, `cantidad_insuficiente` o `dañado` |
| `MovimientoID` | FK → `FactMovimientoInventario` (opcional) | Poblado si el tipo es `recepcion_incompleta` |
| `MotivoID` | FK → `DimMotivo` | |
| `AreaAtencionID` | FK → `DimArea` | Primer respondedor (Fase 1, sección 6.1) |
| `AreaEscaladaID` | FK → `DimArea` (opcional) | Solo si hubo escalamiento (RN-019) |
| `FechaID` | FK → `DimFecha` | |
| `FechaDeteccion` | — | |
| `EstadoResolucion` | — | `en_atencion` / `resuelta` / `escalada` / `no_resuelta` |
| `FechaResolucion` | — (opcional) | |

**Regla de integridad**: exactamente una de `LineaID` / `MovimientoID` debe estar poblada, según `TipoIncidencia` — nunca ambas, nunca ninguna.

### 4.5. `FactDevolucion`

**Grano**: 1 fila = 1 devolución, vinculada a una línea de pedido en estado `Completado`.

| Columna | Tipo de referencia | Notas |
|---|---|---|
| `DevolucionID` | PK | |
| `LineaID` | FK → `FactPedidoDetalle` | Debe estar en estado `Completado` (RN-026) |
| `MotivoID` | FK → `DimMotivo` | |
| `FechaID` | FK → `DimFecha` | |
| `FechaDevolucion` | — | Debe estar dentro de la ventana de devolución (RN-027) |

### 4.6. Decisión: incidencias de monitoreo quedan fuera de `FactIncidencia`

Las incidencias de monitoreo (SLA próximo a incumplir, stock crítico, tasa anómala — Fase 1, sección 6.2) **no se modelan como tabla de hechos**. No son un evento que ocurre y se registra; son una condición calculada cuando un KPI cruza un umbral. Se resuelven en Fase 6 mediante vistas/medidas sobre los KPIs ya calculados. Si en el futuro se necesita historial de cuándo se disparó cada alerta, se agrega entonces — no antes, porque hoy ninguna pregunta de negocio lo exige.

### 4.7. Decisiones de diseño que evitan tablas innecesarias

| Decisión | Resolución | Motivo |
|---|---|---|
| ¿Tabla de cabecera de pedido separada de la línea? | No | A esta escala, repetir cliente/fecha/canal por línea es aceptable; una tabla aparte solo para eso sería sobreingeniería |
| ¿`FactRecepcionCD` como tabla independiente? | No | Es un caso particular de `FactMovimientoInventario` (RN-017) |
| ¿Estado del pedido completo como campo propio? | No, se deriva | Se calcula a partir de `EstadoActualID` de todas sus líneas (Completado solo si todas lo están; Cancelado solo si todas lo están; si no, `Parcial`) — evita mantener dos estados sincronizados |
| ¿`EstadoActualID` denormalizado en `FactPedidoDetalle`? | Sí | El historial es la fuente de verdad; el campo actual evita recorrer el historial en cada consulta simple de KPI. Se mantiene sincronizado por un mecanismo a decidir en Fase 3 (SP, trigger o transacción — no se fija aquí) |

---

## 5. Conexión a `DimFecha`

`DimFecha` se conecta explícitamente (mediante `FechaID`) a las siguientes tablas de hechos, no solo a `FactPedidoDetalle`: `FactHistorialEstadoLinea`, `FactMovimientoInventario`, `FactIncidencia`, `FactDevolucion`. Motivo: las preguntas de negocio piden constantemente segmentación "por periodo", y sin esta conexión explícita Power BI tendría que extraer la fecha del timestamp en tiempo de consulta — más lento y menos limpio para el modelo semántico de Fase 7.

---

## 6. Mapa de relaciones

```
DimProducto (1) ── (N) DimSKU
                              │
DimCliente (1) ── (N) ────────┤
DimTienda  (1) ── (N) ────────┼──── FactPedidoDetalle ──(N:1)── DimFecha
                              │              │
                              │              ├──(1:N)── FactHistorialEstadoLinea ──(N:1)── DimEstado
                              │              │                                    ──(N:1)── DimFecha
                              │              │
                              │              ├──(1:N, opcional)── FactIncidencia ──(N:1)── DimArea (atención)
                              │              │                                   ──(N:1)── DimArea (escalada, opcional)
                              │              │                                   ──(N:1)── DimMotivo
                              │              │                                   ──(N:1)── DimFecha
                              │              │
                              │              └──(1:N)── FactDevolucion ──(N:1)── DimMotivo
                              │                                         ──(N:1)── DimFecha
                              │
                              └──── FactMovimientoInventario ──(N:1)── DimTienda
                                            │              ──(N:1)── DimFecha
                                            ├──(N:1, opcional)── FactPedidoDetalle (vía LineaID)
                                            ├──(N:1, opcional)── FactIncidencia (referenciada desde ahí, vía MovimientoID)
                                            └──(N:1, opcional)── DimMotivo
```

---

## 7. Resumen de tablas

**Dimensiones (8)**: `DimProducto`, `DimSKU`, `DimTienda`, `DimCliente`, `DimFecha`, `DimEstado`, `DimArea`, `DimMotivo`

**Hechos (5)**: `FactPedidoDetalle`, `FactHistorialEstadoLinea`, `FactMovimientoInventario`, `FactIncidencia`, `FactDevolucion`

Cada tabla de hechos se justifica contra al menos una pregunta de negocio de `00_contexto_y_alcance.md` (sección 7) — ninguna se agregó por completitud.

---

## 8. Siguiente paso

Fase 3 — Implementación SQL Server (`03_implementacion_sql.md`): convertir este modelo en `CREATE TABLE`, definir tipos de dato exactos, constraints (`CHECK`, `UNIQUE`, `FOREIGN KEY`), y decidir la implementación de `EstadoActualID` (trigger, stored procedure o transacción — pendiente de la sección 4.7).