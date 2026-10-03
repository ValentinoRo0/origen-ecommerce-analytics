# ORIGEN — Datos operativos
## Fase 4 🟡 En curso

> Estado: Bloque 3 **implementado y validado — 7/7 validaciones OK** (resultado en §2.4). Bloque 4 **implementado parcialmente**: sesión 1 ejecutada con validaciones H **37/37 OK** y regresión `test_vistas.sql` **60/60 PASS** (2026-10-02); sesión 2 pendiente de cumplir el gate temporal real (§3).

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

#### Stock sembrado vs. snapshot histórico de stock

Son dos magnitudes distintas y no deben confundirse:

| Concepto | Valor | Qué es |
|---|---|---|
| **Stock inicial sembrado** | **20 unidades** en 5 combinaciones (10/4/3/1/2) | Diseño aprobado del Bloque 3, registrado en el ledger exactamente como `INGRESO / CONFIGURACION_INICIAL` (`FechaID = 20260101`, `LineaID = NULL`). Es un **invariante**: la validación V6 lo exige tal cual. |
| **Snapshot de stock al cierre de la Fase 3 (2026-10-01)** | **18 unidades** en 5 combinaciones | Estado histórico derivado de los movimientos operativos ejecutados durante la Fase 3: `A10001 @ Jockey Plaza = 8/0` (−3 `DESCUENTO_DEFINITIVO` de las líneas 53, 1054 y 1055, y +1 `AJUSTE` del movimiento 1137, sobre el +10 sembrado). Las otras cuatro combinaciones quedaron en 4 / 3 / 1 / 2 y las 51 restantes en 0. **Es un estado previo al Bloque 4, no el stock operativo actual** (V6 lo reporta como valor observado, informativo). |

> **2026-10-02 — después de la sesión 1 del Bloque 4:**
>
> - `SUM(StockSistema) = **45**` en **12 combinaciones** SKU × Tienda con stock.
> - `A10001 @ Jockey Plaza = **8 / 0**` se mantiene como ancla.
> - Las cuatro combinaciones de la pre-siembra distintas del ancla quedaron en:
>
>   | Combinación | Stock |
>   |---|---|
>   | `A10001 @ Real Plaza Arequipa` | 0 / 0 |
>   | `A30001 @ Real Plaza Arequipa` | 2 / 1 |
>   | `A30002 @ Real Plaza Arequipa` | 0 / 0 |
>   | `A40001 @ Mall Aventura Trujillo` | 0 / 0 |
>
> Este segundo bloque es el estado vigente tras la sesión 1; las 18 unidades de la tabla anterior son el snapshot histórico del cierre de la Fase 3.

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

## 3. Bloque 4 — Escenario operativo en dos sesiones

`sql/06_seed_data/03_seed_bloque4.sql`

### 3.1. Propósito

El Bloque 4 completa el escenario operativo que las vistas analíticas necesitan para ser creíbles:

- pedidos que recorren los estados operativos (desde creado hasta completado, cancelado, rechazado o en incidencia);
- incidencias de picking (`no_encontrado`, `cantidad_insuficiente`, `dañado`);
- incidencias de recepción desde el CD (`recepcion_incompleta`);
- cancelaciones por los tres motivos (voluntaria, incidencia, vencimiento);
- devoluciones;
- vencimientos de recojo.

Se divide en **dos sesiones** porque dos de esos flujos exigen un intervalo temporal real entre operaciones: la recepción del CD y el vencimiento de la ventana de recojo. No se fabrican timestamps futuros: el tiempo transcurrido debe existir de verdad.

### 3.2. Diseño

| Decisión | Resolución |
|---|---|
| Alcance | 45 pedidos (`100001`–`100045`), 52 líneas, 6 clientes, canal 27 recojo / 18 despacho |
| Operaciones de negocio | Los **14 procedimientos almacenados** del proyecto para toda operación (creación de pedidos, picking, despacho, recojo, cancelación, devolución, incidencias, vencimientos) |
| DML directo documentado (4 excepciones) | Recepciones del CD (`INGRESO` / `RECEPCION_CD`); ajustes de conteo físico (`AJUSTE` / `CONTEO_FISICO`); incidencias `recepcion_incompleta` (creación y resolución); asignación de `AreaEscaladaID` en los escalamientos |
| Stock | Solo a través de `FactMovimientoInventario` → `trg_ActualizarStockSKUTienda`; **sin `UPDATE` directo sobre `StockSKUTienda`** |
| Aleatoriedad y tiempo | Sin `RAND()`; `FechaHora = SYSDATETIME()` real; en las operaciones que lo requieren, `SYSDATETIME()` se asigna a una variable (T-SQL no admite funciones como valor de parámetro de un `EXEC`) |
| Idempotencia | Marcadores por sesión, **sin `DELETE`**: re-ejecutar omite lo ya hecho y solo re-valida |
| Atomicidad | Cada sesión dentro de una transacción con `TRY/CATCH`: ante cualquier fallo, `ROLLBACK` + reporte de estado + `THROW` |

### 3.3. Sesión 1 — ejecutada 2026-10-02

Operaciones ejecutadas: recepciones CD, ajustes de conteo, creación de 45 pedidos / 52 líneas, flujo de picking, despacho y recojo, 2 incidencias de recepción con su escalamiento **D-I** a Abastecimiento (`AreaEscaladaID = 3`) y 6 devoluciones.

Resultado observado:

| Métrica | Valor |
|---|---|
| Estados de líneas (Com/Can/Rech/Inc/Disp) | **30 / 6 / 8 / 6 / 2** |
| Ledger de movimientos | **110** |
| Incidencias generadas por el Bloque 4 | **11** |
| Devoluciones | **6** |
| Líneas en "Disponible para recojo" | **2** |

- Validaciones H (Q01–Q13 + C01–C24): **37/37 OK**.
- Regresión `sql/07_tests/test_vistas.sql`: **60/60 PASS** (prueba de solo lectura, sin modificar).
- Reejecución: confirmó **idempotencia** (omite las operaciones) y volvió a obtener **37/37 OK**.

### 3.4. Gate temporal

La sesión 2 solo se ejecuta cuando se cumple, con tiempo real, un día natural completo desde la primera recepción del CD:

`DATEDIFF(DAY, MIN(FechaHora), SYSDATETIME()) >= 1`

Mientras no se cumple, el script imprime el aviso correspondiente, ejecuta `RETURN` y **no** se ejecuta la sesión 2 (comprobado el 2026-10-02: la BD permanece en el estado de la sesión 1).

Nota de control de flujo: el guard que decide si las validaciones H se omiten (el escenario ya avanzó a sesión 2) se encuentra **en el mismo batch que las validaciones H**, de modo que `RETURN` termina ese batch completo y evita ejecutar validaciones propias del estado de sesión 1. Es una corrección de control de flujo, no un cambio de arquitectura.

### 3.5. Sesión 2 — pendiente del gate temporal

Operaciones previstas (ya implementadas en el script, pendientes de ejecutar):

- escalar las 4 incidencias de picking al área de Operaciones (`AreaEscaladaID = 2`);
- cancelar 3 líneas por incidencia;
- resolver la incidencia de recepción del pedido `100040` hasta **Completado**;
- escalar la recepción pendiente a Abastecimiento (`AreaEscaladaID = 3`);
- procesar los 2 vencimientos de recojo con `sp_ProcesarVencimientosRecojo`.

Resultado **esperado** (aún no ejecutado, por eso son expectativas y no resultados):

| Métrica | Esperado |
|---|---|
| Estados de líneas (Com/Can/Rech/Inc/Disp) | **31 / 11 / 8 / 2 / 0** |
| Ledger de movimientos | **116** |
| Devoluciones | **6** |
| Líneas en "Disponible para recojo" | **0** |
| Matriz de incidencias | la que exigen las validaciones J del script |
| Reporte final | `ESTADO BLOQUE 4: IMPLEMENTADO Y VALIDADO` |

---

## 4. Pendiente

- ~~Ejecutar el script en SSMS y reportar la tabla de validaciones (Bloque 3).~~ Completado el 2026-10-01: **7/7 validaciones OK** (§2.4).
- ~~Bloque 4, sesión 1.~~ Completada el 2026-10-02: **H 37/37 OK** y regresión **60/60 PASS** (§3.3).
- Bloque 4, sesión 2: **pendiente** del gate temporal real (§3.4).
- Validaciones J (resultado final del Bloque 4): **pendientes** de la sesión 2.
- Regresión final de `test_vistas.sql` después de la sesión 2: **pendiente**.
- Actualización final de esta documentación después de la sesión 2: **pendiente**.
