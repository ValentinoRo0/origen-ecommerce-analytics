# ORIGEN — Procesos y Reglas de Negocio
## Fase 1 ✅ Completa

---

## 1. Propósito del documento

Este documento define los procesos operativos y las reglas de negocio que gobiernan el funcionamiento del canal e-commerce de Origen.

Su objetivo es establecer cómo se comporta el negocio **antes** de traducir estos procesos a un modelo de datos, reglas SQL, procesos ETL o análisis. Este documento no contiene estructuras de tablas, código SQL ni implementaciones técnicas — esas decisiones se desarrollan en `02_modelo_de_datos.md` en adelante.

---

## 2. Principios generales del negocio

### 2.1. Inicio del ciclo del pedido

El ciclo de vida analizado por Origen comienza cuando **el pago del cliente ha sido confirmado**. No se modelan las etapas previas de carrito, checkout abandonado o conversión digital — eso pertenece a analítica de marketing/conversión, fuera del alcance del proyecto.

### 2.2. Diferencia entre rechazo y cancelación tardía

Origen distingue dos situaciones relacionadas con la disponibilidad de stock, porque mezclarlas diluiría la señal del problema central:

**Rechazo inmediato** — el sistema detecta falta de stock al momento de intentar la reserva. El pedido no ingresa al flujo operativo principal; se registra como demanda insatisfecha. Es el sistema funcionando *correctamente*, no una incidencia operativa.

**Cancelación tardía (operativa)** — el sistema aceptó el pedido creyendo que había stock, pero durante el picking se descubre que no lo hay. **Esta es la manifestación directa del problema central del proyecto.**

### 2.3. Motivos de cancelación (ampliado)

Con la incorporación de la cancelación voluntaria (sección 3.4), el estado `Cancelado` puede originarse por tres vías distintas, que deben quedar diferenciadas mediante un campo `motivo_cancelacion` — de lo contrario, se mezclarían en el análisis y se diluiría la señal del problema operativo:

| Motivo | Origen | ¿Es el problema central del proyecto? |
|---|---|---|
| `incidencia_picking` | Operativo — stock no encontrado o insuficiente | **Sí** |
| `voluntaria` | El cliente solicita cancelar antes del despacho | No — es comportamiento normal del cliente |
| `vencimiento` | El cliente no recogió el pedido dentro del plazo | Parcialmente — puede relacionarse con mala comunicación (problema 2) |

Cualquier KPI de "tasa de cancelación" que construyamos en Fase 6 debe poder filtrarse por este campo, o el número mezclará causas de negocio muy distintas.

---

## 3. Ciclo de vida del pedido

### 3.1. Flujo general

```
Pago confirmado
    ↓
Reserva de stock (intento)
    ↙                    ↘
Stock insuficiente     Stock reservado con éxito
    ↓                        ↓
Rechazado              Pedido creado ────────┐
(fuera del flujo)           ↓                │
                       Asignado a picking     │  Cancelación voluntaria
                             ↓                │  disponible en cualquiera
                       Picking en proceso     │  de estos 4 estados
                        ↙            ↘        │  (ver sección 3.4)
              Producto encontrado   Producto NO encontrado
                    ↓                 o cantidad insuficiente
               Empaquetado ──────────┘             ↓
                    ↓                       Incidencia de picking
          ¿Recojo o despacho?                 ↙            ↘
              ↙        ↘                 Resuelto        No resuelto
        Despacho    Disponible          (retoma el          ↓
             ↓      para recojo          flujo)         Cancelado
        En tránsito       ↓                             (motivo:
             ↓        ¿Cliente recoge                 incidencia_picking)
        Entregado      a tiempo?
             ↓          ↙    ↘
        Completado    Sí     No, vence
                       ↓        ↓
                 Recojo por  Vencido
                  cliente       ↓
                       ↓    Cancelado
                 Completado (motivo: vencimiento)
                       ↓
              (post-completado, opcional)
                  Devolución
```

**Nota sobre la cancelación voluntaria**: a partir de "Despacho" o "Disponible para recojo", el pedido ya no admite cancelación voluntaria (ver regla RN-009). Por eso esas dos ramas no tienen flecha de salida hacia cancelación voluntaria en el diagrama.

### 3.2. Estados del pedido

| Estado | Descripción | Estado final |
|---|---|---|
| Rechazado | No existe stock suficiente al momento de la reserva | Sí |
| Pedido creado | Pago confirmado y stock reservado con éxito | No |
| Asignado a picking | Pedido asignado a tienda/almacén para preparación | No |
| Picking en proceso | Preparación física en curso | No |
| Incidencia de picking | Producto no encontrado o cantidad insuficiente | No |
| Empaquetado | Pedido físicamente listo | No |
| En tránsito | Despachado a domicilio, en camino | No |
| Entregado | Recibido por el cliente (despacho) | No |
| Disponible para recojo | Esperando que el cliente llegue a tienda | No |
| Vencido | Cliente no recogió dentro del plazo definido | No (transiciona a Cancelado) |
| Recojo por cliente | Cliente recogió en tienda | No |
| Completado | Ciclo cerrado exitosamente | **Sí** |
| Cancelado | Pedido no pudo completarse (ver motivos, sección 2.3) | **Sí** |
| Devolución | Cliente devuelve un pedido ya completado | Sí (evento aparte, solo KPI) |

### 3.3. Reglas de negocio — flujo principal

**RN-001 — Reserva de stock**
La reserva de stock debe realizarse inmediatamente después de la confirmación del pago. Si no existe stock suficiente, el pedido no debe ingresar al flujo operativo principal (pasa a Rechazado).

**RN-002 — Reserva atómica**
La verificación y reserva de stock deben ejecutarse como una operación atómica, para evitar que dos pedidos reserven simultáneamente la misma unidad disponible. *(Implementación prevista en Fase 3: transacción + TRY/CATCH.)*

**RN-003 — Incidencia de picking**
Si durante el picking el producto no puede ser encontrado o la cantidad disponible es inferior a la reservada, debe registrarse una incidencia con su motivo (`no_encontrado`, `cantidad_insuficiente`, `dañado`, u otro).

**RN-004 — Resolución de incidencia**
Toda incidencia debe quedar asociada a un área responsable y una acción esperada, según la matriz de resolución de incidencias (pendiente de definir).

**RN-005 — Cancelación operativa**
Una cancelación por incidencia de picking debe registrar el momento en que se produce (`fecha_cancelacion`) y generar un evento de notificación al cliente con su propio timestamp (`fecha_notificacion`). Esto permite medir la brecha entre cancelación y notificación — clave para el problema de clientes que llegan a recoger un pedido ya cancelado.

**RN-006 — Vencimiento de recojo**
Un pedido disponible para recojo se considera vencido cuando supera el plazo definido para que el cliente lo retire. Este plazo es un **parámetro de negocio configurable**, no un valor fijo, para poder simular distintos escenarios en Power BI.

**RN-007 — Devolución**
Una devolución solo puede registrarse sobre un pedido que haya alcanzado previamente el estado Completado.

**RN-008 — Registro de eventos por transición**
Cada transición de estado debe registrar un timestamp propio, no solo el estado actual del pedido. Esto es indispensable para calcular tiempos de picking, cumplimiento de SLA, y la brecha cancelación–notificación. Implica modelar un **historial de estados**, no solo el estado vigente (a resolver formalmente en Fase 2).

### 3.4. Cancelación voluntaria del cliente

**RN-009 — Cancelación voluntaria**
El cliente puede solicitar la cancelación de su pedido mientras este se encuentre en cualquiera de los estados: `Pedido creado`, `Asignado a picking`, `Picking en proceso` o `Empaquetado`. Una vez que el pedido pasa a `En tránsito` o `Disponible para recojo`, ya no se admite cancelación voluntaria — a partir de ahí, si el pedido llega a completarse, cualquier rechazo del producto por parte del cliente se trata como **devolución**, no como cancelación.

Cuando ocurre una cancelación voluntaria:
- Se registra con `motivo_cancelacion = voluntaria`.
- Si el pedido ya tenía stock reservado o descontado, ese stock debe liberarse/reingresar (ver RN-012 en el ciclo de stock).
- **No** dispara la matriz de resolución de incidencias — no es una falla operativa, no requiere que un área "actúe" para corregir algo.

Esta distinción es la razón por la que se separó `motivo_cancelacion` como campo obligatorio desde el diseño (sección 2.3): sin ella, la tasa de cancelación total mezclaría decisiones del cliente con fallas propias de Origen, y el análisis de causas (pregunta de negocio central del proyecto) perdería precisión.

---

## 4. Ciclo de vida del stock

### 4.1. Conceptos base

Origen distingue tres magnitudes de stock por producto/variante y tienda, que no deben confundirse:

| Magnitud | Definición |
|---|---|
| **Stock sistema** | Lo que el sistema registra como existente, tras aplicar todos los movimientos conocidos |
| **Stock reservado** | Unidades comprometidas por pedidos aún no descontados definitivamente (en curso, no canceladas) |
| **Stock disponible** | `Stock sistema − Stock reservado`. Es lo que se le muestra al cliente en la web |
| **Stock físico** | Lo que realmente existe en el punto de almacenamiento, verificado por conteo |

La diferencia entre **stock sistema** y **stock físico** es, por definición del problema central del proyecto (sección 2, `00_contexto_y_alcance.md`), la causa raíz que se quiere analizar.

### 4.2. Flujo general de movimientos de stock

```
                    Stock sistema (por producto/variante y tienda)
                              ↑↓
        ┌──────────┬──────────┼──────────┬──────────┐
        ↓          ↓          ↓          ↓          ↓
   Recepción   Reserva    Liberación  Descuento   Ajuste
    desde CD  (pedido      de reserva  definitivo  (conteo
   (ingreso)   creado)    (cancelación (picking     físico o
                           o incidencia  exitoso)    corrección)
                          no resuelta)
```

Cada movimiento queda registrado individualmente (no se sobreescribe simplemente un número de "stock actual"), porque sin ese historial no es posible auditar después dónde y cuándo se originó una diferencia — que es exactamente lo que las preguntas de negocio de la sección 7 (`00_contexto_y_alcance.md`) requieren poder responder.

### 4.3. Tipos de movimiento

| Tipo de movimiento | Efecto sobre stock sistema | Efecto sobre stock reservado | Dispara cuándo |
|---|---|---|---|
| Ingreso (recepción CD) | + | — | Llega mercadería desde el CD (detalle en fase posterior) |
| Reserva | — (no descuenta sistema, ver nota) | + | Pedido pasa a "Pedido creado" |
| Liberación de reserva | — | − | Cancelación (cualquier motivo) o incidencia no resuelta |
| Descuento definitivo | − | − | Picking exitoso — convierte la reserva en salida real |
| Ajuste por conteo | + o − | — | Conteo físico periódico detecta diferencia |

**Nota importante**: la reserva **no** descuenta el stock sistema inmediatamente — solo incrementa el stock reservado. El descuento real ocurre recién cuando el picking confirma que el producto físicamente existe y se entrega (RN-011). Esto es deliberado: si se descontara al reservar, un pedido cancelado tendría que "devolver" stock de forma más compleja, y sobre todo, confundiría stock realmente vendido con stock simplemente comprometido.

### 4.4. Reglas de negocio — stock

**RN-010 — Cálculo de disponibilidad**
El stock disponible mostrado al cliente se calcula como `stock sistema − stock reservado`, nunca como el stock sistema solo. Esta es la magnitud que interviene en la decisión de aceptar o rechazar un pedido (RN-001).

**RN-011 — Momento del descuento definitivo**
El descuento definitivo de stock ocurre cuando el picking confirma la disponibilidad física del producto, no en el momento de crear el pedido. Hasta ese momento, la unidad está "reservada", no "vendida".

**RN-012 — Liberación de reserva**
Toda cancelación (por cualquier motivo: incidencia no resuelta, voluntaria o vencimiento) y toda incidencia de picking no resuelta deben liberar la reserva correspondiente, para que la unidad vuelva a estar disponible para otros pedidos.

**RN-013 — Trazabilidad de movimientos**
Todo movimiento de stock debe registrarse como un evento individual con tipo, cantidad, fecha y origen — no como una simple actualización del campo de stock actual. Sin esto no es posible reconstruir después el origen de una diferencia.

**RN-014 — Origen de la diferencia sistema vs. físico**
La diferencia entre stock sistema y stock físico se detecta mediante conteos periódicos, que generan un movimiento de tipo "ajuste" con motivo `conteo_fisico`. Origen no asume que el stock físico se conoce en tiempo real — se conoce solo en el momento del conteo, lo cual es realista y es, en sí mismo, parte del problema que el proyecto investiga.

**RN-015 — No negatividad**
El stock sistema no puede quedar en un valor negativo tras ningún movimiento. *(Implementación prevista en Fase 3: constraint CHECK o validación dentro de la transacción de descuento.)*

### 4.5. Nota sobre granularidad (referencia cruzada)

Todas las reglas anteriores aplican sobre la unidad de granularidad que se determine formalmente en Fase 2 (Producto vs. Variante/SKU — ver `00_contexto_y_alcance.md`, sección 14). Este documento no asume una respuesta todavía; las reglas son válidas en cualquiera de los dos escenarios.

---

## 5. Recepción desde el Centro de Distribución

### 5.1. Alcance de este proceso

Tal como se definió en `00_contexto_y_alcance.md` (sección 3), la recepción desde el CD **no se modela como proceso logístico completo**. Se modela únicamente como un evento que puede originar una diferencia de stock — que es lo único relevante para el problema central de Origen.

No se modelan: transporte, tracking del envío, gestión de proveedores del CD, ni el proceso interno de picking dentro del propio CD.

### 5.2. Flujo simplificado

```
CD despacha una remesa hacia una tienda
    ↓
Tienda registra la recepción
    ↓
¿Cantidad recibida = cantidad esperada?
    ↙                              ↘
   Sí                              No
    ↓                               ↓
Ingreso de stock              Ingreso de stock
(cantidad completa)           (cantidad parcial)
    ↓                               ↓
                          Se registra discrepancia
                          (motivo: recepción_incompleta)
                                    ↓
                          Queda disponible como posible
                          causa en el análisis de incidencias
                          posteriores en esa tienda/categoría
```

### 5.3. Reglas de negocio — recepción

**RN-016 — Registro de cantidad esperada vs. recibida**
Toda recepción debe registrar tanto la cantidad esperada (según lo que el CD reporta haber despachado) como la cantidad efectivamente recibida por la tienda. La diferencia entre ambas, si existe, se registra como discrepancia — no se descarta ni se corrige silenciosamente.

**RN-017 — La recepción es un tipo de movimiento de ingreso**
Una recepción exitosa (o parcialmente exitosa) genera un movimiento de stock de tipo "ingreso" (ver sección 4.3), por la cantidad efectivamente recibida — nunca por la cantidad esperada.

**RN-018 — No se infiere causa automáticamente**
Una recepción incompleta no debe marcarse automáticamente como "causa" de una cancelación futura. Es un dato disponible para el análisis de causas (Fase 6), pero la relación se establece mediante análisis de los datos, no se asume por diseño. *(Esto es intencional: si asumiéramos la relación de antemano, el "hallazgo" en Fase 6 no sería un hallazgo real — sería una conclusión que ya decidimos de entrada.)*

---

## 6. Gestión de incidencias y matriz de resolución

### 6.1. Principio de primer nivel de atención

Confirmado por el usuario en base a su experiencia observando la operación: **el primer responsable ante cualquier incidencia detectada durante el picking es el propio equipo de tienda/picking**, no un área central. Un área central de Operaciones E-commerce interviene únicamente cuando la incidencia no se resuelve dentro de una ventana de tiempo definida (RN-019), o cuando la incidencia no es puntual sino un patrón detectado por monitoreo de KPIs (sección 6.4).

Esto es importante para el diseño: la matriz de resolución no es un mapa fijo de "incidencia → área", sino un mapa de **escalamiento** — quién atiende primero, y a quién se escala si no se resuelve a tiempo.

### 6.2. Tipos de incidencia

**Incidencias puntuales** (asociadas a un pedido/línea específica):

| Tipo | Origen | Motivo registrado |
|---|---|---|
| Producto no encontrado | Picking | `no_encontrado` |
| Cantidad insuficiente | Picking | `cantidad_insuficiente` |
| Producto dañado | Picking | `dañado` |
| Recepción incompleta | Recepción CD | `recepcion_incompleta` (ver sección 5) |

**Incidencias de monitoreo** (no asociadas a un pedido individual, sino detectadas por umbral sobre un KPI — tienda, categoría o periodo):

| Tipo | Se detecta por |
|---|---|
| Pedido próximo a incumplir SLA | % de tiempo de SLA consumido supera un umbral |
| Stock crítico | Stock disponible cae bajo un umbral de cobertura |
| Tasa de incidencias anómala en tienda | Tasa de incidencias de una tienda supera significativamente el promedio |

Las incidencias de monitoreo dependen de KPIs que se calculan formalmente en Fase 6 — aquí solo se deja establecido que también pasan por esta misma lógica de matriz y escalamiento.

### 6.3. Matriz de resolución

| Incidencia | Primer respondedor | KPI afectado | Escala a (si no se resuelve en la ventana) | Acción esperada | Prioridad |
|---|---|---|---|---|---|
| Producto no encontrado | Tienda / Picking | Tasa de cancelación | Operaciones E-commerce | Buscar ubicación alterna dentro de tienda; si no aparece, liberar reserva | Alta |
| Cantidad insuficiente | Tienda / Picking | Tasa de cancelación, disponibilidad | Operaciones E-commerce | Confirmar cantidad real, liberar la diferencia no disponible | Alta |
| Producto dañado | Tienda / Picking | Calidad de picking | Operaciones E-commerce → Abastecimiento | Retirar unidad del stock, generar ajuste, liberar reserva | Media |
| Recepción incompleta (CD) | Tienda (registra) | Cobertura de stock | Abastecimiento / CD | Validar con CD, gestionar reposición | Media |
| Pedido próximo a incumplir SLA | Operaciones E-commerce (monitoreo) | Cumplimiento de SLA | Logística / Tienda | Priorizar preparación o despacho de ese pedido | Alta |
| Stock crítico | Operaciones E-commerce (monitoreo) | Cobertura, riesgo de quiebre | Abastecimiento / Comercial | Evaluar reposición o exclusión de campaña (ver Campaign Readiness) | Media |
| Tasa de incidencias anómala en tienda | Operaciones E-commerce (monitoreo) | Tasa de incidencias, cancelación | Encargado de tienda | Investigar causa raíz (conteo, capacitación, ubicación) | Alta |

### 6.4. Estados de resolución

```
Incidencia detectada
        ↓
En atención (tienda/picking)
    ↙            ↘
Resuelta      No resuelta dentro
(retoma el     de la ventana definida
 flujo)              ↓
              Escalada a Operaciones E-commerce
                    ↙            ↘
               Resuelta      No resuelta
                                  ↓
                          Pedido cancelado
                       (motivo: incidencia_picking)
```

### 6.5. Reglas de negocio — incidencias

**RN-019 — Ventana de escalamiento**
Toda incidencia puntual no resuelta por el primer respondedor dentro de una ventana de tiempo definida (parámetro de negocio configurable) se escala automáticamente al área correspondiente según la matriz de resolución.

**RN-020 — Registro completo de la incidencia**
Toda incidencia debe registrar: tipo, fecha de detección, área en atención, estado actual, y — si corresponde — fecha y motivo de resolución o de escalamiento. Este registro es la base de datos que permite construir el análisis de causas en Fase 6.

**RN-021 — Incidencia no resuelta implica cancelación**
Una incidencia puntual que no se resuelve ni siquiera tras el escalamiento deriva en cancelación del pedido (motivo `incidencia_picking`) y libera la reserva de stock asociada (RN-012).

**RN-022 — Las incidencias de monitoreo no bloquean pedidos individuales**
Las incidencias de tipo monitoreo (SLA en riesgo, stock crítico, tasa anómala) generan una alerta operativa, pero no cancelan pedidos por sí solas — impulsan una acción preventiva o de revisión, no una resolución transaccional inmediata.

---

## 7. Campaign Readiness

### 7.1. Qué es y qué no es

Campaign Readiness es un **checklist de preparación operativa** que se evalúa antes del inicio de una campaña de alta demanda (ej. Cyber, temporada). No es un módulo de planificación de marketing ni gestiona presupuesto o creatividades — solo responde una pregunta: **¿está Origen operativamente lista para el volumen que se aproxima?**

### 7.2. Criterios evaluados

Cada criterio se evalúa por tienda y/o categoría, y produce un semáforo (🟢/🟡/🔴):

| Criterio | Qué mide | Fuente de datos |
|---|---|---|
| Stock suficiente | SKUs con cobertura por debajo del umbral crítico (mismo umbral que la incidencia de monitoreo "stock crítico", sección 6.3) | Stock disponible actual |
| Historial de incidencias | Tiendas/categorías con tasa de incidencias superior al promedio en el periodo previo | Registro de incidencias (sección 6) |
| Capacidad de picking | Tiendas con tiempos de picking ya cercanos al límite de SLA antes de que empiece la campaña | Historial de tiempos de picking |
| Pricing cargado | Check binario: ¿el precio promocional está correctamente configurado para los SKUs en campaña? | Validación puntual, no dataset de precios (ver `00_contexto_y_alcance.md`, alcance) |

### 7.3. Resultado esperado

El resultado es un **score agregado por tienda/categoría** (ej. 3 de 4 criterios en verde) y un listado de qué elementos están en riesgo — no una nota única sin desglose, porque lo accionable es saber *qué* corregir, no solo que "algo" está mal.

### 7.4. Reglas de negocio — Campaign Readiness

**RN-023 — Ejecución previa a campaña**
El checklist de Campaign Readiness debe evaluarse en una fecha de corte definida antes del inicio de la campaña (parámetro de negocio), no el mismo día que esta comienza.

**RN-024 — Reutilización de umbrales existentes**
Los criterios de stock crítico e historial de incidencias reutilizan los mismos umbrales definidos para las incidencias de monitoreo (sección 6.3) — no se definen umbrales distintos para el mismo concepto en dos lugares del proyecto.

**RN-025 — No bloquea automáticamente**
Un resultado en rojo no cancela ni bloquea la campaña automáticamente; es información para que el área responsable decida (ej. excluir un SKU crítico de la promoción). Origen no automatiza esa decisión — está fuera de alcance (ver Power Automate en `00_contexto_y_alcance.md`).

---

## 8. Devoluciones

### 8.1. Alcance

Tal como se definió desde la Fase 0, no se modela el proceso completo de devolución (solicitud → aprobación → recojo → inspección → reembolso). Se modela únicamente el **evento de devolución** como dato suficiente para calcular la tasa de devolución.

### 8.2. Regla de registro

**RN-026 — Condición para registrar una devolución**
Una devolución solo puede registrarse sobre un pedido en estado `Completado` (ya establecido en RN-007). Se registra con: fecha de devolución, motivo (categoría general, ej. `talla_incorrecta`, `no_cumple_expectativa`, `producto_dañado`), y la línea de pedido afectada (para poder segmentar por producto/categoría).

**RN-027 — Ventana de devolución**
Una devolución solo es válida dentro de un plazo definido desde la fecha de completado del pedido (parámetro de negocio). Fuera de ese plazo, no se registra como devolución dentro del alcance del proyecto.

---

## 9. Reglas de negocio transversales

Reglas que no pertenecen a un solo proceso, sino que gobiernan el diseño general de Origen:

**RN-028 — Todo evento requiere timestamp propio**
Generalización de RN-008: cualquier evento relevante del negocio (cambio de estado de pedido, movimiento de stock, incidencia, recepción, devolución) se registra con su propio timestamp — nunca se sobreescribe un campo sin dejar rastro de cuándo cambió.

**RN-029 — Todo motivo es un campo explícito, nunca se infiere**
Cancelación, incidencia, ajuste de stock y devolución siempre registran su motivo como un valor explícito capturado en el momento del evento. Ningún motivo se infiere después a partir de otros datos — evita construir análisis de causas sobre supuestos no verificados (mismo principio que RN-018).

**RN-030 — Ningún umbral o plazo va hardcodeado**
Todo valor que representa una política de negocio (plazos, umbrales, ventanas de tiempo) es un parámetro configurable, consolidado en la sección 10, no un valor fijo disperso en la lógica.

---

## 10. Parámetros de negocio consolidados

Todos los parámetros configurables mencionados a lo largo de este documento, reunidos en un solo lugar para que en Fase 3/4 se implementen de forma centralizada (ej. una tabla de configuración), no repartidos por el código:

| Parámetro | Usado en | Referencia |
|---|---|---|
| Plazo de vencimiento de recojo | Determina cuándo un pedido "Disponible para recojo" pasa a "Vencido" | RN-006 |
| Ventana de escalamiento de incidencia | Tiempo máximo que tiene tienda/picking antes de escalar a Operaciones | RN-019 |
| Umbral de stock crítico (cobertura) | Dispara incidencia de monitoreo "stock crítico" y criterio de Campaign Readiness | RN-022, RN-024 |
| Umbral de tasa de incidencias anómala | Dispara incidencia de monitoreo "tasa anómala en tienda" | RN-022 |
| SLA objetivo (por etapa del pedido) | Define cuándo un pedido está "próximo a incumplir SLA" | RN-022 |
| Fecha de corte de Campaign Readiness | Cuándo se evalúa el checklist respecto al inicio de campaña | RN-023 |
| Ventana de devolución | Plazo máximo desde "Completado" para registrar una devolución válida | RN-027 |

Los valores concretos de estos parámetros (ej. "4 horas", "3 días") se definen en Fase 4, cuando se generen los datos simulados — este documento solo establece que deben existir como parámetros, no sus valores finales.

---

## 11. Decisiones de diseño registradas

| Decisión | Resolución | Motivo |
|---|---|---|
| ¿Se modela el funnel previo a la compra (carrito, checkout)? | No | Pertenece a analítica de conversión/marketing, fuera de alcance |
| ¿Se separan rechazo inmediato y cancelación tardía? | Sí, como estados distintos | Evita diluir la señal del problema central en el análisis |
| ¿Se modela la cancelación voluntaria del cliente? | **Sí**, con `motivo_cancelacion = voluntaria` (RN-009) | Confirmado por el usuario — se separa mediante campo de motivo para no contaminar el KPI de cancelación operativa |
| ¿La reserva descuenta el stock sistema inmediatamente? | No — solo incrementa stock reservado (RN-011) | Evita confundir stock comprometido con stock realmente vendido; simplifica la liberación ante cancelación |
| ¿Cómo se detecta la diferencia stock sistema vs. físico? | Mediante conteos periódicos, no en tiempo real (RN-014) | Refleja la realidad operativa; es parte del problema que el proyecto investiga, no un dato que se asume conocido |
| ¿Se infiere automáticamente que una recepción incompleta causó una incidencia posterior? | No — se deja como dato disponible, la relación se prueba en Fase 6 (RN-018) | Evita dar por sentado un hallazgo antes de analizarlo con datos reales |
| ¿Quién atiende primero una incidencia de picking? | El equipo de tienda/picking, no un área central | Confirmado por el usuario según su experiencia observando la operación real |
| ¿Cuándo interviene un área central de Operaciones? | Solo si la incidencia no se resuelve dentro de una ventana de tiempo definida, o si es una incidencia de monitoreo (patrón, no evento puntual) | Refleja escalamiento real, no un mapa fijo de responsables |
| ¿Campaign Readiness bloquea automáticamente una campaña? | No — solo informa, la decisión la toma el área responsable | Automatizar la decisión está fuera de alcance (Power Automate) |
| ¿Se modela el proceso completo de devolución? | No — solo el evento y su motivo, para calcular la tasa | Confirmado desde Fase 0; evita abrir un módulo de gestión completo |

---

## 12. Pendiente en este documento

- [x] Ciclo de vida del pedido
- [x] Ciclo de vida del stock
- [x] Recepción desde Centro de Distribución
- [x] Gestión de incidencias y matriz de resolución
- [x] Campaign Readiness
- [x] Devoluciones
- [x] Reglas de negocio transversales
- [x] Parámetros de negocio consolidados

**Fase 1: completa.** Siguiente paso: Fase 2 — Modelo de datos (`02_modelo_de_datos.md`), donde estos procesos y reglas se traducen a dimensiones, tablas de hechos y la decisión pendiente de granularidad (Producto vs. Variante/SKU).