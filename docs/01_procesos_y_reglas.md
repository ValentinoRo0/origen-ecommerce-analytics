# ORIGEN — Procesos y Reglas de Negocio
## Fase 1 (en construcción)

---

## 1. Propósito del documento

Este documento define los procesos operativos y las reglas de negocio que gobiernan el funcionamiento del canal e-commerce de Origen.

Su objetivo es establecer cómo se comporta el negocio **antes** de traducir estos procesos a un modelo de datos, reglas SQL, procesos ETL o análisis. Este documento no contiene estructuras de tablas, código SQL ni implementaciones técnicas — esas decisiones se desarrollan en `02_modelo_de_datos.md` en adelante.

---

## 2. Principios generales del negocio

### 2.1. Inicio del ciclo del pedido

El ciclo de vida analizado por Origen comienza cuando **el pago del cliente ha sido confirmado**. No se modelan las etapas previas de carrito, checkout abandonado o conversión digital — eso pertenece a analítica de marketing/conversión, fuera del alcance del proyecto (ver `00_contexto_y_alcance.md`, sección 8.2).

### 2.2. Diferencia entre rechazo y cancelación tardía

Origen distingue dos situaciones relacionadas con la disponibilidad de stock, porque mezclarlas diluiría la señal del problema central:

**Rechazo inmediato** — el sistema detecta falta de stock al momento de intentar la reserva. El pedido no ingresa al flujo operativo principal; se registra como demanda insatisfecha. Es el sistema funcionando *correctamente*, no una incidencia operativa.

**Cancelación tardía** — el sistema aceptó el pedido creyendo que había stock, pero durante el picking se descubre que no lo hay. **Esta es la manifestación directa del problema central del proyecto.**

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
Rechazado              Pedido creado
(fuera del flujo)           ↓
                       Asignado a picking
                             ↓
                       Picking en proceso
                        ↙            ↘
              Producto encontrado   Producto NO encontrado
                    ↓                 o cantidad insuficiente
               Empaquetado                  ↓
                    ↓                Incidencia de picking
          ¿Recojo o despacho?          ↙            ↘
              ↙        ↘          Resuelto        No resuelto
        Despacho    Disponible    (retoma el          ↓
             ↓      para recojo    flujo)         Cancelado
        En tránsito       ↓                     (+ notificación
             ↓        ¿Cliente recoge              al cliente)
        Entregado      a tiempo?
             ↓          ↙    ↘
        Completado    Sí     No, vence
                       ↓        ↓
                 Recojo por  Vencido
                  cliente       ↓
                       ↓    Cancelado
                 Completado (+ notificación,
                              posible reingreso
                              a stock)
                       ↓
              (post-completado, opcional)
                  Devolución
```

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
| Cancelado | Pedido no pudo completarse | **Sí** |
| Devolución | Cliente devuelve un pedido ya completado | Sí (evento aparte, solo KPI) |

---

## 4. Reglas de negocio — ciclo del pedido

**RN-001 — Reserva de stock**
La reserva de stock debe realizarse inmediatamente después de la confirmación del pago. Si no existe stock suficiente, el pedido no debe ingresar al flujo operativo principal (pasa a Rechazado).

**RN-002 — Reserva atómica**
La verificación y reserva de stock deben ejecutarse como una operación atómica, para evitar que dos pedidos reserven simultáneamente la misma unidad disponible. *(Implementación prevista en Fase 3: transacción + TRY/CATCH.)*

**RN-003 — Incidencia de picking**
Si durante el picking el producto no puede ser encontrado o la cantidad disponible es inferior a la reservada, debe registrarse una incidencia con su motivo (`no_encontrado`, `cantidad_insuficiente`, `dañado`, u otro).

**RN-004 — Resolución de incidencia**
Toda incidencia debe quedar asociada a un área responsable y una acción esperada, según la matriz de resolución de incidencias (pendiente de definir en la sección 6 de este documento).

**RN-005 — Cancelación**
Una cancelación debe registrar el momento en que se produce (`fecha_cancelacion`) y generar un evento de notificación al cliente con su propio timestamp (`fecha_notificacion`). Esto permite medir la brecha entre cancelación y notificación — clave para el problema de clientes que llegan a recoger un pedido ya cancelado.

**RN-006 — Vencimiento de recojo**
Un pedido disponible para recojo se considera vencido cuando supera el plazo definido para que el cliente lo retire. Este plazo es un **parámetro de negocio configurable**, no un valor fijo en el código, para poder simular distintos escenarios en Power BI.

**RN-007 — Devolución**
Una devolución solo puede registrarse sobre un pedido que haya alcanzado previamente el estado Completado.

**RN-008 — Registro de eventos por transición**
Cada transición de estado debe registrar un timestamp propio, no solo el estado actual del pedido. Esto es indispensable para calcular tiempos de picking, cumplimiento de SLA, y la brecha cancelación–notificación en fases posteriores. Implica modelar un **historial de estados**, no solo el estado vigente (a resolver formalmente en Fase 2).

---

## 5. Decisiones de diseño registradas

| Decisión | Resolución | Motivo |
|---|---|---|
| ¿Se modela el funnel previo a la compra (carrito, checkout)? | No | Pertenece a analítica de conversión/marketing, fuera de alcance |
| ¿Se separan rechazo inmediato y cancelación tardía? | Sí, como estados distintos | Evita diluir la señal del problema central en el análisis |
| ¿Se modela la cancelación voluntaria del cliente (arrepentimiento)? | **Pendiente de confirmación** | No estaba en el alcance original; no responde ninguna pregunta de negocio actual — se agrega solo si el usuario lo solicita explícitamente |

---

## 6. Pendiente en este documento

Las siguientes secciones se desarrollan en las próximas sesiones de la Fase 1, siguiendo el mismo nivel de detalle que el ciclo del pedido:

- [ ] Ciclo de vida del stock (movimientos, reserva, descuento, ajuste)
- [ ] Recepción desde Centro de Distribución
- [ ] Gestión de incidencias — tipos, matriz de resolución completa, estados de resolución
- [ ] Campaign Readiness — criterios y checklist
- [ ] Devoluciones — regla de registro y motivos
- [ ] Reglas de negocio transversales (aplican a más de un proceso)
- [ ] Parámetros de negocio (lista consolidada: plazo de vencimiento, SLA objetivo, etc.)