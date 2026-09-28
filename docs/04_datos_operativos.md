# ORIGEN — Datos operativos
## Fase 4 🟡 En curso

> Estado: Bloque 3 **escrito, pendiente de ejecución en SSMS**. No se marca como completado hasta reportar las 7 validaciones en OK.

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

### 2.4. Validaciones

| # | Validación | Esperado |
|---|---|---|
| 1 | Cobertura de todas las combinaciones SKU × Tienda | 0 faltantes, 56 filas |
| 2 | Sin duplicados SKU+Tienda | 0 |
| 3 | Sin stock negativo (RN-015) | 0 |
| 4 | `StockReservado <= StockSistema` | 0 excepciones |
| 5 | Coherencia ledger vs `StockSKUTienda` (recalculado con las reglas del trigger) | 0 discrepancias |
| 6 | Disponibilidad (`Sistema − Reservado`, RN-010) | 5 filas con stock, 20 unidades, sin desvíos |
| 7 | Compatibilidad con `sp_CrearPedido`, con `ROLLBACK` | CREADO, RECHAZADO, RECHAZADO; estado restaurado sin filas residuales |

### 2.5. Nota sobre la validación 7

La lección técnica de Fase 3 es no envolver pruebas en una transacción externa, porque `XACT_ABORT` y el `ROLLBACK` del `CATCH` del SP pueden destruirla. Esa lección aplica cuando el SP **lanza error**. Los tres casos de la validación 7 son resultados normales (`CREADO` / `RECHAZADO`), por lo que la transacción llega intacta al `ROLLBACK` final. El `ROLLBACK` no devuelve los valores `IDENTITY` consumidos: las tablas de hechos quedan con huecos en sus IDs, sin filas residuales.

---

## 3. Pendiente

- Ejecutar el script en SSMS y reportar la tabla de validaciones.
- Bloque 4 y siguientes: por definir.
