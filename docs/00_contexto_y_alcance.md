# ORIGEN — Contexto y Alcance
## Fase 0

---

## 1. Contexto de la empresa

Origen es un retailer ficticio de **moda y lifestyle** (ropa, calzado, accesorios, perfumería), más cercano en posicionamiento a **Zara / The Box** que a un marketplace departamental como Falabella o Ripley. Opera bajo un modelo **omnicanal**: venta online, despacho a domicilio y recojo en tienda (Click & Collect), con preparación de pedidos desde tiendas o almacenes y abastecimiento desde un Centro de Distribución (CD).

El tamaño de Origen es deliberadamente mediano: suficiente para generar problemas operativos reales, pero acotado para que el proyecto siga siendo defendible por una sola persona en una entrevista.

---

## 2. Problema rector

> **¿Cómo puede Origen usar sus datos operativos para vender mejor, cumplir la promesa hecha al cliente y reducir las incidencias que afectan la experiencia de compra?**

"Vender mejor" se interpreta como **evitar perder ventas por problemas operativos y cumplir correctamente la promesa al cliente** — no como desarrollar estrategias de marketing, pricing o publicidad.

Tres áreas conectadas, con jerarquía explícita:

| Área | Rol |
|---|---|
| **E-commerce** (demanda, campañas, pedidos, promesa al cliente) | **Núcleo** |
| **Operaciones** (stock, reserva, picking, SLA) | **Motor** |
| **Logística / SCM** (abastecimiento, recepción CD) | **Soporte / causa**, no protagonista |

---

## 2.1. Alineación con perfil profesional objetivo

El proyecto está diseñado pensando en roles de **Asistente / Analista Jr. de Operaciones E-commerce** en el mercado peruano: perfiles que combinan seguimiento operativo (pedidos, inventario, SLA, incidencias), coordinación entre áreas (Logística, Comercial, CX) y reportería en Excel/Power BI.

Por eso el núcleo incorpora tres piezas ancladas en funciones reales de ese tipo de rol, sin abrir un dominio comercial/marketing nuevo:

| Incorporación | Qué agrega |
|---|---|
| **Matriz de resolución de incidencias** | Incidencia → KPI afectado → área responsable → acción esperada → prioridad |
| **Campaign Readiness** | Checklist previo a campaña: stock, SKUs críticos, pricing cargado (check binario), capacidad de picking, categorías de riesgo |
| **Tasa de devoluciones** | KPI adicional segmentable por categoría/tienda/periodo, sin modelar el proceso completo de devolución |

**Explícitamente fuera de alcance, incluso como "dimensión secundaria":** margen, costo, pricing como dataset propio, ROAS/inversión publicitaria, multi-marketplace, CRM, email marketing.

---

## 3. Problemas empresariales a analizar

| # | Problema | Rol |
|---|---|---|
| 1 | Stock mostrado vs. stock real | **Núcleo** — problema central |
| 2 | Cumplimiento de la promesa al cliente (retrasos) | **Núcleo** |
| 3 | Recepciones incompletas desde el CD | **Causa relacionada**, no proceso central |
| 4 | Preparación de pedidos / picking | **Núcleo** — conecta stock con cancelación |
| 5 | Campañas y demanda | **Núcleo, con alcance limitado**: descriptivo, sin forecasting/ML |

---

## 4. Causas y consecuencias

```
Diferencia entre stock sistema y stock físico
        ↓
Pedido aceptado como "disponible"
        ↓
Picking → producto no encontrado / cantidad insuficiente
        ↓
Incidencia registrada
        ↓
        ├── Cancelación del pedido
        └── Retraso → incumplimiento de SLA → cliente afectado
```

**Causas hipotéticas** (a simular con datos realistas en Fase 4): recepciones incompletas del CD, errores de conteo, mercadería mal ubicada, concurrencia en el descuento de stock, presión adicional durante campañas.

**Consecuencias:** tasa de cancelación elevada, baja productividad de picking, incumplimiento de SLA visible al cliente, falta de visibilidad para priorizar.

---

## 5. Objetivo general

> Diseñar y construir una solución analítica para Origen que permita monitorear la operación e-commerce, detectar incidencias, identificar sus principales causas y evaluar su impacto sobre el cumplimiento de la promesa al cliente, integrando información de pedidos, inventario, picking y abastecimiento.

---

## 6. Objetivos específicos

1. Diseñar un modelo de datos que represente los procesos clave de la operación e-commerce de Origen.
2. Implementar reglas de negocio e integridad en SQL Server.
3. Analizar el comportamiento de pedidos, inventario, picking y SLA.
4. Construir KPIs de e-commerce y operaciones.
5. Identificar causas principales de cancelaciones e incidencias.
6. Construir un dashboard interactivo en Power BI (Control Tower).
7. Formular recomendaciones accionables respaldadas por los datos del propio proyecto.
8. Incorporar matriz de resolución de incidencias, Campaign Readiness y tasa de devoluciones, sin ampliar el proyecto a un dominio comercial/marketing.

---

## 7. Preguntas de negocio

**Demanda y campañas**
- ¿Qué categorías/productos concentran mayor demanda, y cómo cambia durante campañas?
- ¿Las campañas incrementan la tasa de incidencias y cancelación?

**Pedidos y promesa al cliente**
- ¿Cuál es la tasa de cancelación por tienda/categoría/periodo?
- ¿Qué proporción de pedidos incumple el SLA, y en qué etapa se genera el retraso?
- ¿Qué porcentaje de cancelaciones se debe a stock no encontrado vs. otros motivos?

**Inventario y picking**
- ¿Qué tiendas/categorías concentran mayor diferencia entre stock sistema y físico?
- ¿Cuál es el tiempo promedio de picking, y qué proporción de líneas tiene incidencia de "no encontrado"?

**Causas**
- ¿Qué combinación tienda + categoría + periodo concentra más incidencias?
- ¿Existe relación entre recepciones incompletas del CD y cancelaciones posteriores?

**Devoluciones**
- ¿Cuál es la tasa de devolución por categoría/tienda/periodo, y cómo se compara con el promedio?

**Preparación para campañas**
- Antes de una campaña, ¿qué tiendas/categorías/SKUs entran con stock crítico o historial elevado de incidencias?
- ¿El pricing y las promociones están correctamente cargados antes del inicio de la campaña?

**Resolución operativa**
- Ante una incidencia detectada, ¿qué área es responsable y qué acción se espera de ella?

---

## 8. Alcance

### 8.1. Dentro del alcance
- Pedidos, inventario, picking, ciclo de vida completo del pedido.
- Decisión explícita sobre granularidad de producto (ver sección 14).
- Integridad transaccional en SQL Server (constraints, transacciones, SP; triggers solo si se justifican).
- Datos simulados con patrones realistas de moda: temporadas, campañas, tallas/colores.
- KPIs y análisis de causas básico.
- Dashboard Power BI tipo Control Tower.
- Matriz de resolución de incidencias, Campaign Readiness (checklist), tasa de devolución.

### 8.2. Fuera del alcance
- Simulación completa de campaña Cyber antes/después (extensión opcional).
- Alertas con Power Automate y comunicación automatizada al cliente (extensión opcional).
- BigQuery/PySpark (extensión opcional, solo si el volumen lo justifica).
- Forecast, análisis causal multivariable avanzado, Machine Learning.
- CRM, email marketing, ROAS, márgenes, pricing como dataset propio, multi-marketplace real.
- Gestión completa de devoluciones, proveedores y transporte.

---

## 9. Actores involucrados

| Actor | Rol |
|---|---|
| Cliente | Genera el pedido, recoge o recibe el producto |
| Canal e-commerce | Muestra disponibilidad, captura el pedido |
| Encargado de picking (tienda) | Prepara el pedido físicamente |
| Encargado de tienda / recojo | Entrega el pedido |
| Centro de Distribución (CD) | Abastece a las tiendas |
| Analista de Operaciones E-commerce (rol simulado) | Monitorea KPIs, detecta causas, recomienda acciones |

---

## 10. Procesos que se van a modelar

1. Gestión de inventario: stock sistema, físico, movimientos, diferencias.
2. Ciclo de vida del pedido: creación → ... → completado/cancelado.
3. Recepción desde CD (simplificado).

No se modelan como proceso propio: devoluciones post-entrega complejas, gestión de proveedores, transporte entre almacenes.

---

## 11. Datos necesarios

Catálogo de productos/variantes, tiendas, clientes, pedidos y detalle, historial de estados del pedido, inventario (stock sistema vs. físico), eventos de picking, eventos de recepción CD, calendario con marcado de campañas.

---

## 12. Arquitectura preliminar

```
Datos simulados (CSV) → SQL Server (modelo + integridad transaccional)
     → Python/Pandas (EDA, cálculos puntuales)
     → Power BI (KPIs, causas, Control Tower)
```

BigQuery/PySpark y Power Automate quedan fuera hasta que una fase concreta demuestre que se necesitan.

---

## 13. Herramientas

| Herramienta | Uso | Justificación |
|---|---|---|
| SQL Server / T-SQL | Modelo, integridad, lógica transaccional | Corazón del proyecto |
| Constraints | Reglas simples e inquebrantables | Preferible a trigger cuando la regla es declarativa |
| Transacciones + TRY/CATCH | Reserva/descuento de stock | Evita estados inconsistentes |
| Stored Procedures | Operaciones de negocio multi-paso | Encapsula lógica reutilizable |
| Views | Consumo simplificado para Power BI/Python | Desacopla consumo de estructura |
| Triggers | Solo ante regla inquebrantable independiente del proceso escritor | Definido caso por caso en Fase 3 |
| Python (Pandas/NumPy) | EDA, cálculos puntuales, anomalías simples | Donde SQL no es la herramienta natural |
| Power BI | Modelo semántico + Control Tower | Herramienta principal a futuro |
| PySpark / BigQuery | Fuera del núcleo | Solo si el volumen lo justifica |
| Power Automate | Fuera del núcleo | Extensión opcional |
| Machine Learning | Fuera del proyecto | No forma parte del perfil a demostrar aquí |

---

## 14. Decisión pendiente: granularidad del producto

Antes de modelar dimensiones y hechos (Fase 2), se debe decidir si el inventario y el picking se manejan a nivel de **Producto** o de **Variante/SKU (Producto × Talla × Color)**. Afecta directamente el grano de `FactInventario`, `FactPicking` y `FactPedidoDetalle`.

Criterio de decisión: ¿esa granularidad es necesaria para responder alguna pregunta de negocio de la sección 7? En retail de moda, el stock y las incidencias suelen ocurrir a nivel de variante, así que es probable que el grano correcto sea SKU — pero se confirma formalmente en Fase 2.

---

## 15. Criterio para controlar el alcance

Toda nueva funcionalidad, tabla, herramienta o análisis debe evaluarse antes de incorporarse al proyecto. Debe cumplir al menos una de estas condiciones:

1. Responder directamente una pregunta de negocio definida en la sección 7.
2. Participar en una regla de negocio relevante.
3. Ser necesaria para calcular un KPI definido.
4. Permitir un análisis que aporte valor al problema central.
5. Resolver una necesidad que una herramienta anterior del proyecto no pueda cubrir adecuadamente.

Si no cumple ninguna condición, no se incorpora al núcleo del proyecto. Este criterio gobierna todas las fases siguientes.