# Prueba de concurrencia — picking

## 1. Objetivo

Verificar que las transiciones de picking se ejecutan de forma correcta bajo concurrencia: que dos sesiones que intentan avanzar la misma línea no producen estados inconsistentes, que cada transición queda registrada en el historial y que la reserva de stock permanece íntegra durante la prueba y tras la limpieza.

## 2. Escenario de prueba

Script: `sql/07_tests/test_concurrencia_stock.sql`

Pedido de prueba:

| Campo | Valor |
|---|---|
| PedidoID | 991001 |
| LineaID | 2054 |
| ClienteID | 4 |
| SKUID | 4 |
| TiendaID | 6 |
| FechaID | 20260102 |
| Canal | recojo |
| Cantidad | 1 |

Stock de SKUID 4 / TiendaID 6 antes de la prueba: `StockSistema = 8`, `StockReservado = 0`, `StockDisponible = 8`.

La prueba se ejecutó con dos sesiones independientes sobre OrigenDB: una sesión 1 que realiza la transacción y mantiene el bloqueo, y una sesión 2 que intenta realizar la misma transición sobre la misma línea.

## 3. Pruebas realizadas

### 3.1 sp_AsignarPicking

- La sesión 1 ejecutó `sp_AsignarPicking` sobre la línea 2054 (`Pedido creado → Asignado a picking`) y funcionó correctamente.
- Mientras la sesión 1 mantenía el bloqueo, la sesión 2 quedó esperando.
- Después del COMMIT de la sesión 1, la sesión 2 fue rechazada porque el estado de origen ya había cambiado.

### 3.2 sp_IniciarPicking

- La sesión 1 ejecutó `sp_IniciarPicking` sobre la línea 2054 (`Asignado a picking → Picking en proceso`) y funcionó correctamente.
- Mientras la sesión 1 mantenía el bloqueo, la sesión 2 quedó esperando.
- Después del COMMIT de la sesión 1, la sesión 2 fue rechazada porque el estado de origen ya había cambiado.

## 4. Concurrencia y bloqueo

- En ambas pruebas la segunda sesión quedó esperando mientras la primera mantenía el bloqueo.
- Después del COMMIT, la segunda ejecución fue rechazada porque el estado de origen ya había cambiado: la transición no se aplicó dos veces.
- El `wait_type` del bloqueo no fue capturado directamente, por lo que no se afirma que se haya observado específicamente `LCK_M_U`.

## 5. Transiciones verificadas

Se verificó en `FactHistorialEstadoLinea` la secuencia completa de la línea de prueba:

`Pedido creado (1) → Asignado a picking (9) → Picking en proceso (10)`

## 6. Integridad del stock

| Momento | StockSistema | StockReservado | StockDisponible |
|---|---|---|---|
| Inicial | 8 | 0 | 8 |
| Después de crear el pedido | 8 | 1 | 7 |
| Después de la limpieza | 8 | 0 | 8 |

- La creación del pedido reservó exactamente la cantidad de la línea (1).
- La limpieza eliminó los registros de prueba y el stock volvió exactamente a su estado inicial.

## 7. Resultado

- `sp_AsignarPicking`: funcionó correctamente.
- `sp_IniciarPicking`: funcionó correctamente.
- En ambas pruebas la segunda sesión esperó el bloqueo y, tras el COMMIT, fue rechazada porque el estado de origen ya había cambiado.
- Historial `1 → 9 → 10` verificado.
- Registros de prueba eliminados; stock restaurado a `8 / 0 / 8`.

**Prueba aprobada: la Fase 3 de OrigenDB queda validada.**
