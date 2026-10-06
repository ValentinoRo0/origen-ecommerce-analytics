# ORIGEN — KPIs operativos

## Fase 5 · Paso 3 — Definición de KPIs

---

## 1. Propósito y principios

Este documento **define** el conjunto de KPIs del proyecto. Los valores se calculan de forma
reproducible en **`python/analysis/02_kpis.ipynb`**, leyendo los 6 CSV de `data/raw/`
(extraídos en el Paso 1 desde las vistas de `OrigenDB`).

Principios aplicados:

- Cada KPI responde al menos una pregunta de negocio de `docs/00_contexto_y_alcance.md` §7.
- **No se inventan métricas para llenar un dashboard**: 11 KPIs base, todos con fórmula explícita.
- **Sin métricas financieras** (no existen precios ni montos en los datos).
- Los KPIs principales se calculan sobre **Fase 4** (criterio de alcance validado en el EDA).
- **SLA:** no hay meta definida en el proyecto → no se calcula cumplimiento SLA (sección 7).
- No se crea `data/processed/`: los resultados viven en el notebook y son reproducibles
  directo desde `data/raw/`. Si Power BI necesita extractos derivados, se definirá y documentará
  en su propia fase (qué, por qué y con qué reglas), no por inercia.

---

## 2. Criterios de alcance por fuente

| Dataset | Alcance usado en los KPIs |
|---|---|
| `pedidos_operaciones`, `tiempos_estados`, `devoluciones` | `PedidoID` 100001–100045 → **Fase 4** (45 pedidos); 990001–990030 → heredado de Fase 3, **excluido** de los KPIs principales |
| `incidencias` | `PedidoID` cuando existe; las 2 recepciones CD sin línea → por `FechaHoraDeteccion ≥ 2026-10-01` (resultado: 11 Fase 4 / 1 heredada) |
| `movimientos` | Triple clasificación: **Fase 4 (86) / heredado (8) / Global sin pedido (22)** — cada KPI indica cuál usa |
| `stock_historico` | **Completo** (5.040 filas): su serie depende de `FechaID`, no de `PedidoID` |

---

## 3. Tabla de KPIs

| KPI | Definición | Fórmula | Unidad | Fuente | Alcance | Nivel de desglose | Interpretación | Limitaciones |
|---|---|---|---|---|---|---|---|---|
| 1. Pedidos gestionados | Nº de pedidos con actividad operativa: base y denominador de los KPIs de pedidos | `COUNT(DISTINCT PedidoID)` sobre `Alcance = "Fase 4"` | pedidos (acompaña: líneas y unidades) | `pedidos_operaciones.csv` | Fase 4 | mes, canal, tienda, categoría, campaña | Magnitud de la operación analizada | Los 6 pedidos heredados quedan fuera; el pedido no tiene estado propio (`EstadoActual` es de línea) |
| 2. % de cancelación | Proporción de líneas que terminan en estado `Cancelado` | `líneas EstadoActual = "Cancelado" / líneas gestionadas × 100` | % | `pedidos_operaciones.csv` | Fase 4 | tienda, canal, categoría, mes, campaña; variantes por pedido | Cuánto de lo procesado termina cancelado | Grano línea (el estado no existe a nivel pedido); muestra pequeña: 1 línea ≈ 1,9 pp |
| 3. % de cancelación por incidencia | Peso de las cancelaciones cuyo motivo declarado es una incidencia de picking | `canceladas MotivoCancelacion = "incidencia_picking" / canceladas × 100` | % | `pedidos_operaciones.csv` | Fase 4 | tienda, mes, campaña | Composición de motivos sobre las cancelaciones (voluntaria 6 · incidencia 3 · vencimiento 2) | Solo 11 cancelaciones: 1 línea ≈ 9,1 pp; es el motivo declarado (RN-029), no causa raíz verificada |
| 4. Distribución por canal | Reparto de líneas entre recojo y despacho | `líneas por canal / líneas × 100` | % | `pedidos_operaciones.csv` | Fase 4 | mes, tienda, estado | Mezcla operativa del canal (recojo domina) | Medido sobre líneas; en los datos ningún pedido mezcla ambos canales |
| 5. Incidencias por 100 líneas | Densidad de incidencias normalizada al volumen procesado | `incidencias Fase 4 / líneas Fase 4 × 100` | incidencias por 100 líneas | `incidencias.csv` + `pedidos_operaciones.csv` | Fase 4 | tienda, tipo, mes, campaña | Permite comparar cortes de distinto volumen | n = 11; las 2 recepciones CD sin tienda entran por fecha de detección |
| 6. % de incidencias no resueltas | Proporción de incidencias que no cerraron como `resuelta` | `incidencias EstadoResolucion ≠ "resuelta" / incidencias × 100` | % | `incidencias.csv` | Fase 4 | tipo, tienda, campaña | Estado de cierre al corte (`no_resuelta` 3, `en_atencion` 2, `escalada` 1) | Agrupa 3 estados distintos; es un snapshot, sin fecha de corte configurable |
| 7. Incidencias por tipo/motivo | Composición de incidencias por tipo | `COUNT(TipoIncidencia) / incidencias × 100` | % (y conteo) | `incidencias.csv` | Fase 4 | tipo × estado, tienda, mes | Ranking de tipos: `no_encontrado` 4 (36,4 %), `cantidad_insuficiente` 3 (27,3 %), `dañado` 2, `recepcion_incompleta` 2 | `TipoIncidencia` y `NombreMotivo` coinciden 1:1 → una sola dimensión, no dos evidencias; n = 11 |
| 8. Stock disponible al cierre | Unidades disponibles (sistema − reservado) en el último `FechaID` | `SUM(StockDisponible) WHERE FechaID = MAX(FechaID)` | unidades | `stock_historico.csv` | **Completo** | fecha, tienda, SKU | Nivel de inventario disponible para venta al cierre (2026-03-31) | Solo stock sistema (sin stock físico); corte único del escenario |
| 9. SKUs/tiendas con stock = 0 | Combos SKU×tienda sin unidades disponibles en el cierre | `COUNT(StockDisponible = 0) / COUNT(combos) × 100` | combos y % | `stock_historico.csv` | **Completo** | tienda, SKU | Cobertura de inventario al cierre (44/56 = 78,6 %) | Stock 0 ≠ quiebre: 41 combos nunca se abastecieron y 3 agotaron; no hay demanda insatisfecha medible |
| 10. Movimientos de inventario | Volumen y sentido de los movimientos de stock | `COUNT(*)` por alcance/tipo; `SUM(Cantidad)` por tipo (signo almacenado) | movimientos y unidades | `movimientos.csv` | **Los tres** (Fase 4 / heredado / Global) | alcance, tipo, origen, fecha, tienda | Actividad de inventario y su efecto neto (ledger reconstruye 47/2/45 = cierre) | 22 movimientos sin `PedidoID` → nunca se desglosan por pedido; los INGRESO/AJUSTE caen todos en Global |
| 11. Tasa de devolución | Líneas devueltas sobre líneas entregadas | `devoluciones / líneas EstadoActual = "Completado" × 100` | % | `devoluciones.csv` + `pedidos_operaciones.csv` | Fase 4 | categoría, tienda, motivo, mes | Frecuencia de devoluciones sobre pedidos entregados | n = 6; alternativas: 9 u./31 = 29,0 % y 6/45 = 13,3 % (la elección del denominador es explícita en el notebook) |

---

## 4. Fórmulas con valores de referencia (Fase 4)

Valores calculados por `02_kpis.ipynb` — el notebook se detiene si alguno no cuadra (sección 9).

| # | KPI | Fórmula con valores | Resultado |
|---|---|---|---|
| 1 | Pedidos gestionados | `COUNT(DISTINCT PedidoID)` = 45 (52 líneas, 87 unidades) | **45 pedidos** |
| 2 | % de cancelación | `11 / 52 × 100` | **21,2 %** (pedido: ≥1 cancelación 11/45 = 24,4 %; 100 % cancelado 8/45 = 17,8 %) |
| 3 | % cancelación por incidencia | `3 / 11 × 100` | **27,3 %** (sobre gestionadas: 3/52 = 5,8 %) |
| 4 | Distribución por canal | `31/52 × 100` y `21/52 × 100` | **recojo 59,6 % · despacho 40,4 %** (pedidos: 27/18 → 60,0 % / 40,0 %) |
| 5 | Incidencias por 100 líneas | `11 / 52 × 100` | **21,2** |
| 6 | % incidencias no resueltas | `6 / 11 × 100` | **54,5 %** |
| 7 | Incidencias por tipo | `4/11`, `3/11`, `2/11`, `2/11` × 100 | **36,4 % · 27,3 % · 18,2 % · 18,2 %** |
| 8 | Stock disponible al cierre | `47 − 2` en `FechaID = 20260331` | **45 u.** (sistema 47, reservado 2) |
| 9 | SKUs/tiendas con stock = 0 | `44 / 56 × 100` | **78,6 %** (Jockey 7/14 · Trujillo 11/14 · Arequipa 12/14 · Web 14/14) |
| 10 | Movimientos de inventario | `COUNT(*)` = 116 | **86 Fase 4 · 8 heredado · 22 Global** (RESERVA 48 · DESCUENTO 36 · INGRESO 13 · LIBERACIÓN 10 · AJUSTE 9) |
| 11 | Tasa de devolución | `6 / 31 × 100` | **19,4 %** |

---

## 5. Desgloses implementados en el notebook

- **Por fecha (mes):** líneas, canceladas, % cancelación, incidencias, devoluciones
  (ene 14,3 % · feb 23,1 % · mar 24,0 % de cancelación sobre líneas).
- **Por tienda:** estados y % de cancelación (Jockey 31,2 % · Trujillo 25,0 % · Arequipa 18,8 %;
  las 8 líneas Rechazado no tienen tienda).
- **Por canal:** estados y % de cancelación (despacho 23,8 % · recojo 19,4 %).
- **Por categoría:** estados y % de cancelación (Ropa 25,9 % · Calzado 22,2 % · Accesorios 14,3 % ·
  Perfumería 11,1 %) y devoluciones (Ropa 4 de 6).
- **Por campaña:** sección 6.

Ningún desglose introduce un KPI nuevo: es el mismo numerador/denominador desagregado.

---

## 6. Campaña vs. no campaña (solo diferencia descriptiva)

Fechas de campaña en los datos: **2026-03-15 a 2026-03-21** (`Cyber Origen`, 7 días).
Cancelaciones e incidencias se cortan por `EsCampania` (línea) y `FechaID` (incidencias/movimientos).

| Métrica | Campaña | No campaña | Diferencia |
|---|---|---|---|
| Pedidos (Fase 4) | 9 | 36 | — |
| Líneas | 11 | 41 | — |
| Líneas canceladas | 5 | 6 | — |
| % cancelación (líneas) | 45,5 % | 14,6 % | +30,9 pp |
| Incidencias | 3 | 8 | — |
| Incidencias por 100 líneas | 27,3 | 19,5 | +7,8 |
| Incidencias no resueltas | 0 | 6 | — |
| Movimientos de inventario | 24 | 92 | — |

**No se afirma causalidad.** La campaña cae dentro de marzo, que ya concentra el mayor volumen
(25 de 52 líneas): la diferencia es un corte descriptivo, no un efecto aislado y medible
(n = 11 líneas en campaña).

---

## 7. SLA — no definido

**El proyecto no contiene una meta SLA formal, por lo que no se calcula ningún "cumplimiento SLA".**

- `docs/01_procesos_y_reglas.md` §10 lista el parámetro *"SLA objetivo (por etapa del pedido)"*
  entre los parámetros **sin valor concreto** (RN-030: ningún plazo va hardcodeado; el documento
  dice que sus valores "se definen en Fase 4", pero nunca se definieron).
- `sql/06_views/` lo declara en sus 6 vistas: *"no implementan SLA, ni niveles, ni ventanas, ni
  criticidad; solo miden duraciones"*.
- En consecuencia, la pregunta de `docs/00` §7 *"¿Qué proporción de pedidos incumple el SLA, y en
  qué etapa se genera el retraso?"* **no es contestable todavía**; queda pendiente de que se
  defina la meta (decisión de negocio, no del análisis).

Lo que sí se conserva para análisis posterior (sin interpretar):

| Insumo conservado | Valor Fase 4 |
|---|---|
| Episodios de `vw_TiemposEstados` | 288 (236 con duración medida, 52 abiertos) |
| Duración > 0 min | 6 episodios |
| Mediana de duración | 0 min (operaciones ejecutadas en ráfaga) |
| Máximo | 5.004 min (≈ 3,5 días) en `Disponible para recojo` e `Incidencia de picking` |

---

## 8. Limitaciones

1. **No hay precios ni montos** → ningún KPI financiero (ventas, GMV, margen).
2. **No existe stock físico por tienda** → no se mide brecha sistema vs. físico.
3. **No existe meta SLA formal** → no hay cumplimiento SLA (sección 7).
4. **Dataset pequeño:** 45 pedidos, 52 líneas, 11 incidencias, 6 devoluciones, 90 días;
   las tasas son frágiles (1 línea mueve ≈ 1,9 pp la cancelación).
5. **`stock_historico` no está vinculado a pedidos** → sus KPIs usan alcance completo y no se
   desglosan por canal/campaña.
6. **Los movimientos globales no tienen `PedidoID`** (22 de 116) → se analizan por
   tipo/origen/fecha, nunca por pedido.
7. **El estado es atributo de línea** → la cancelación principal es de líneas; las variantes por
   pedido (24,4 % / 17,8 %) se muestran aparte.
8. **`TipoIncidencia` y `NombreMotivo` coinciden 1:1** en este dataset → una sola dimensión.
9. **Dos relojes temporales** (fecha de negocio 2026-01-01…03-31 vs. ejecución real
   2026-09-29…10-05) → toda serie usa `FechaID`.
10. **No se crea `data/processed/`** (ver sección 1).

---

## 9. Validaciones del notebook

`02_kpis.ipynb` verifica antes de calcular nada y **se detiene con `AssertionError`** si algo
no cuadra (nada se oculta ni se "ajusta"):

| # | Verificación | Resultado |
|---|---|---|
| 1 | 45 pedidos Fase 4 | OK |
| 2 | 52 líneas Fase 4 | OK |
| 3 | 11 incidencias Fase 4 | OK |
| 4 | 6 devoluciones | OK |
| 5 | 0 celdas de stock negativas | OK |
| 6 | 116 movimientos en el ledger | OK |
| 7 | 47 StockSistema al cierre | OK |
| 8 | 45 StockDisponible al cierre | OK |
| 9 | Estados F4 = 31/11/8/2/0 | OK |
| 10 | Ledger reconstruye StockSistema (47) | OK |
| 11 | Ledger reconstruye StockReservado (2) | OK |

**Validaciones: 11/11 OK** (última ejecución: 24 celdas, 0 errores, CSV intactos por sha256).

---

## 10. Relación con las preguntas de negocio (`docs/00` §7)

| Pregunta | Estado con estos KPIs |
|---|---|
| Tasa de cancelación por tienda/categoría/periodo | **Contestada** — KPI 2 + desgloses |
| % de cancelaciones por stock no encontrado vs. otros motivos | **Contestada** — KPI 3 (motivos) + KPI 7 (tipos de incidencia) |
| ¿Las campañas incrementan incidencias y cancelación? | **Contestada descriptivamente** — sección 6 (sin causalidad) |
| Tasa de devolución por categoría/tienda/periodo | **Contestada** — KPI 11 + desgloses |
| ¿Qué tiendas/categorías entran con stock crítico en campaña? | **Parcial** — KPI 9 (stock 0 al cierre); el cruce con historial de incidencias queda para hallazgos |
| ¿Qué proporción de pedidos incumple el SLA? | **No contestable** — sin meta SLA (sección 7) |
| Stock sistema vs. físico | **No contestable** — no hay stock físico (limitación 2) |
| Pricing/promos cargados antes de campaña | **No contestable** — no hay datos de pricing |
| Tiempo promedio de picking | **Insumo conservado** — duraciones por estado (sección 7), sin meta que comparar |
| Área responsable y acción esperada por incidencia | **Fuera de este paso** — corresponde a la matriz de resolución (fase de hallazgos) |
