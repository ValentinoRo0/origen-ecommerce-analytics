# ORIGEN — Datos operativos
## Fase 4 🟡 En curso

> Estado: Bloque 3 **implementado y validado — 7/7 validaciones OK** (resultado en §2.4). Bloque 4: pendiente (§3).

---

## 1. Propósito

Documenta las decisiones detrás de los scripts de `sql/06_seed_data/`. Aquí se explica el porqué; el detalle de cada bloque está en los comentarios del `.sql`.

---

## 2. Bloque 3 — Pre-siembra de `StockSKUTienda`

`sql/06_seed_data/02_presiembra_stock_sku_tienda.sql`

### 2.1. Por qué hace falta

`sp_CrearPedido` y `trg_ActualizarStockSKUTienda` exigen que exista una fila en `StockSKUTienda` para cada combinación SKU × Tienda (errores 51002 y del trigger). Ninguno de los dos crea filas: la ausencia se trata como un problema de configuración, no como "stock 0".

### 2.2. Diseño

| Decisión | Resolución | Motivo |
|---|---|---|
| Filas base | 56 filas (14 SKU × 4 tiendas) con `StockSistema = 0` y `StockReservado = 0`, por `INSERT` directo | Cero movimientos en el ledger equivale a cero stock, así que la fila 0/0 es coherente con la fuente de verdad |
| Stock inicial | Solo mediante movimientos `INGRESO` con `Origen = 'CONFIGURACION_INICIAL'`, `FechaID = 20260101`, `LineaID = NULL` | El ledger sigue siendo la fuente de verdad (RN-013); el trigger propaga el efecto. Nunca se hace `UPDATE` directo sobre el resumen |
| `Origen` | Valor nuevo, sin `CHECK` que lo restrinja | El modelo lo define como texto abierto (Fase 2, sección 4.3) |
| Idempotencia | `NOT EXISTS` por SKU+Tienda en las filas base, y por SKU+Tienda+`INGRESO`+`CONFIGURACION_INICIAL` en los ingresos | Re-ejecutar no duplica stock |
| Atomicidad | Siembra dentro de una transacción con `TRY/CATCH` | Si falla el trigger o un `CHECK`, no queda una siembra a medias |

### 2.3. Stock inicial

| SKU | Tienda | Cantidad |
|---|---|---|
| A10001 | Jockey Plaza | +10 |
| A10001 | Real Plaza Arequipa | +4 |
| A30001 | Real Plaza Arequipa | +3 |
| A30002 | Real Plaza Arequipa | +1 |
| A40001 | Mall Aventura Trujillo | +2 |

Las otras 51 combinaciones quedan en 0. `A20001 @ Jockey Plaza` es stock cero explícito, útil para simular una demanda rechazada.

#### Stock sembrado vs. saldo operativo actual

Son dos magnitudes distintas y no deben confundirse:

| Concepto | Valor | Qué es |
|---|---|---|
| **Stock inicial sembrado** | **20 unidades** en 5 combinaciones (10/4/3/1/2) | Diseño aprobado del Bloque 3, registrado en el ledger exactamente como `INGRESO / CONFIGURACION_INICIAL` (`FechaID = 20260101`, `LineaID = NULL`). Es un **invariante**: la validación V6 lo exige tal cual. |
| **Stock operativo actual (tras los movimientos de Fase 3)** | **18 unidades** en 5 combinaciones | Estado derivado de los movimientos operativos ya ejecutados: `A10001 @ Jockey Plaza = 8/0` (−3 `DESCUENTO_DEFINITIVO` de las líneas 53, 1054 y 1055, y +1 `AJUSTE` del movimiento 1137, sobre el +10 sembrado). Las otras cuatro combinaciones permanecen en 4 / 3 / 1 / 2 y las 51 restantes en 0. Es un **snapshot variable**: puede cambiar durante la Fase 4, por eso V6 lo reporta como valor observado (informativo) y no como expectativa fija. |

### 2.4. Validaciones

| # | Validación | Esperado | Resultado |
|---|---|---|---|
| 1 | Cobertura de todas las combinaciones SKU × Tienda | 0 faltantes, 56 filas | `faltantes=0; filas=56` |
| 2 | Sin duplicados SKU+Tienda | 0 | `0` |
| 3 | Sin stock negativo (RN-015) | 0 | `0` |
| 4 | `StockReservado <= StockSistema` | 0 excepciones | `0` |
| 5 | Coherencia ledger vs `StockSKUTienda` (recalculado con las reglas del trigger) | 0 discrepancias | `0` |
| 6 | Disponibilidad por invariantes: **(A)** siembra aprobada en el ledger y **(B)** disponibilidad derivada del ledger vs `StockSKUTienda` (RN-010 / RN-015) | **A:** exactamente 1 `INGRESO / CONFIGURACION_INICIAL` por cada una de las 5 combinaciones (`FechaID 20260101`, `LineaID NULL`), con cantidades 10/4/3/1/2 = 20 u. sembradas; 0 movimientos `CONFIGURACION_INICIAL` duplicados o fuera de esas combinaciones. **B:** 0 discrepancias ledger ↔ resumen, cobertura de las 56 combinaciones, `StockReservado <= StockSistema`, `Disponible = Sistema − Reservado >= 0` (RN-010) y sin stock negativo (RN-015). Las filas/unidades con stock son **informativas**, no una expectativa | `sembrado=5/5, 20 u. (conf=5, fuera=0); disc=0; falt=0; res>sis=0; neg=0; disp<0=0; observado=5 comb./18 u.` |
| 7 | Compatibilidad con `sp_CrearPedido`, con `ROLLBACK` | CREADO, RECHAZADO, RECHAZADO; estado restaurado sin filas residuales | `CREADO; RECHAZADO; RECHAZADO; restaurado` |

**Resultado de la ejecución: 7/7 `OK` (2026-10-01).** Verificación posterior sin residuos: 0 líneas de los pedidos 900001–900003, 0 movimientos/historial huérfanos, `A10001 @ Jockey Plaza` sigue en 8/0, conteos idénticos a la línea base (56 filas de stock, 6 líneas, 27 historial, 14 movimientos, 1 incidencia, 0 devoluciones) y 0 transacciones abiertas.

### 2.5. Nota sobre la validación 7

La lección técnica de Fase 3 es no envolver pruebas en una transacción externa, porque `XACT_ABORT` y el `ROLLBACK` del `CATCH` del SP pueden destruirla. Esa lección aplica cuando el SP **lanza error**. Los tres casos de la validación 7 son resultados normales (`CREADO` / `RECHAZADO`), por lo que la transacción llega intacta al `ROLLBACK` final. El `ROLLBACK` no devuelve los valores `IDENTITY` consumidos: las tablas de hechos quedan con huecos en sus IDs, sin filas residuales.

---

## 3. Pendiente

- ~~Ejecutar el script en SSMS y reportar la tabla de validaciones.~~ Completado el 2026-10-01: **7/7 validaciones OK** (§2.4).
- Bloque 4 y siguientes: por definir.
