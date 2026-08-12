# ORIGEN — E-commerce Operations & Supply Chain Analytics

Proyecto de analítica de operaciones e-commerce orientado al monitoreo de pedidos, inventario, picking y cumplimiento de la promesa al cliente.

## 📌 Descripción

Origen es un proyecto de analítica de datos basado en un retailer ficticio de moda y lifestyle con operación omnicanal (venta online, despacho a domicilio y Click & Collect).

El proyecto busca representar y analizar problemas reales de una operación e-commerce, especialmente aquellos relacionados con la disponibilidad de inventario, la preparación de pedidos, las incidencias operativas y el cumplimiento de los tiempos prometidos al cliente.

El objetivo no es construir un ERP ni replicar todo el ecosistema de e-commerce, sino desarrollar una solución analítica enfocada en **operaciones e-commerce**, utilizando datos simulados con patrones realistas de negocio.

## 🎯 Problema de negocio

Origen enfrenta situaciones en las que el stock mostrado por el sistema no coincide con la disponibilidad física real. Esto puede provocar que un pedido sea aceptado correctamente por el sistema, pero posteriormente falle durante el picking porque el producto no puede ser encontrado o no existe la cantidad necesaria.

```
Diferencia entre stock sistema y stock físico
                    ↓
              Pedido aceptado
                    ↓
              Reserva de stock
                    ↓
                  Picking
                    ↓
          Producto no encontrado
                    ↓
                Incidencia
                 ↙       ↘
            Resuelto     No resuelto
                             ↓
                        Cancelación
                             ↓
                    Cliente afectado
```

Pregunta central del proyecto:

> ¿Cómo puede Origen utilizar sus datos operativos para vender mejor, cumplir la promesa hecha al cliente y reducir las incidencias que afectan la experiencia de compra?

En este proyecto, "vender mejor" se entiende como **evitar pérdidas de ventas por fallas operativas**, no como desarrollar una estrategia de marketing o pricing.

## 🎯 Objetivo

Diseñar y construir una solución analítica que permita:

- Monitorear la operación e-commerce.
- Analizar pedidos e inventario.
- Medir el cumplimiento de SLA.
- Detectar incidencias durante el picking.
- Identificar causas de cancelaciones.
- Analizar diferencias entre stock del sistema y stock físico.
- Evaluar el impacto de las incidencias sobre la experiencia del cliente.
- Preparar la operación para periodos de alta demanda y campañas.
- Generar recomendaciones accionables a partir de los datos.

## 🔎 Principales preguntas de negocio

**Pedidos y cliente**
- ¿Cuál es la tasa de cancelación por tienda, categoría y periodo?
- ¿Qué proporción de pedidos incumple el SLA, y en qué etapa se genera el retraso?
- ¿Qué porcentaje de cancelaciones se debe a problemas de stock?

**Inventario y picking**
- ¿Qué tiendas presentan mayores diferencias entre stock sistema y stock físico?
- ¿Cuál es el tiempo promedio de picking y qué proporción de líneas tiene incidencia?

**Causas**
- ¿Qué combinación de tienda, categoría y periodo concentra más incidencias?
- ¿Existe relación entre recepciones incompletas del CD y problemas posteriores de disponibilidad?

**Campañas**
- ¿Las campañas incrementan las incidencias y cancelaciones?
- ¿El stock y la capacidad operativa están preparados antes de una campaña?

**Devoluciones**
- ¿Cuál es la tasa de devolución por categoría, tienda y periodo?

## 🏗️ Alcance

**Dentro del alcance:** pedidos, inventario, stock sistema vs. físico, picking e incidencias, ciclo de vida del pedido, recepción simplificada desde CD, SLA, cancelaciones, tasa de devoluciones, matriz de resolución de incidencias, Campaign Readiness, KPIs, Control Tower en Power BI.

**Fuera del alcance:** CRM, email marketing, ROAS/inversión publicitaria, análisis de márgenes, pricing como dominio propio, multi-marketplace, forecasting avanzado, Machine Learning, automatización de comunicación al cliente, gestión completa de devoluciones/proveedores/transporte.

Estas funcionalidades podrían desarrollarse como proyectos o extensiones independientes.

## 🏢 Modelo de negocio

Origen es un retailer ficticio de moda y lifestyle (ropa, calzado, accesorios, perfumería), con operación omnicanal: venta online, despacho a domicilio, Click & Collect, preparación desde tiendas y abastecimiento desde un Centro de Distribución.

## 🛠️ Tecnologías

| Tecnología | Uso |
|---|---|
| SQL Server / T-SQL | Modelo de datos, integridad y lógica transaccional |
| Python / Pandas / NumPy | Generación de datos, EDA y análisis puntual |
| Power BI | Modelo semántico, KPIs y dashboard |
| Git / GitHub | Control de versiones y documentación |

Las herramientas adicionales se incorporarán únicamente cuando una necesidad concreta del proyecto las justifique.

## 🔄 Arquitectura prevista

```
Datos simulados → SQL Server → Views/consultas analíticas
     → Python/Pandas → Power BI → Control Tower
     → Hallazgos y recomendaciones
```

La arquitectura se irá refinando durante las siguientes fases.

## 📂 Estructura del proyecto

```
ORIGEN/
├── README.md
├── docs/
│   ├── 00_contexto_y_alcance.md
│   ├── 01_procesos_y_reglas.md
│   ├── 02_modelo_de_datos.md
│   ├── 03_implementacion_sql.md
│   ├── 04_etl.md
│   ├── 05_analisis_python.md
│   ├── 06_kpis.md
│   ├── 07_power_bi.md
│   ├── 08_hallazgos_y_recomendaciones.md
│   └── Glosario.md
├── data/
│   ├── raw/
│   └── processed/
├── sql/
│   ├── 01_database/
│   ├── 02_tables/
│   ├── 03_constraints/
│   ├── 04_stored_procedures/
│   ├── 05_views/
│   └── 06_seed_data/
├── etl/
│   ├── extract/
│   ├── transform/
│   └── load/
├── python/
│   ├── eda/
│   ├── analysis/
│   └── utils/
├── powerbi/
│   └── Origen.pbix
└── assets/
    ├── diagrams/
    └── screenshots/
```

No todos los directorios necesitan existir desde el inicio; se completan a medida que avanza cada fase.

## 📚 Documentación

| Documento | Contenido |
|---|---|
| Contexto y alcance | Problema, objetivos, preguntas de negocio y alcance |
| Procesos y reglas | Procesos operativos y reglas de negocio |
| Modelo de datos | Modelo conceptual, lógico y físico |
| Implementación SQL | Tablas, restricciones, procedimientos y vistas |
| ETL | Extracción, transformación y carga |
| Análisis Python | EDA y análisis exploratorio |
| KPIs | Definición y cálculo de indicadores |
| Power BI | Modelo semántico y dashboard |
| Hallazgos | Resultados y recomendaciones |

## 🚧 Estado del proyecto

**Fase actual:** Fase 2 — Modelo de datos

- [x] Definición del contexto empresarial
- [x] Definición del problema rector
- [x] Definición de objetivos y preguntas de negocio
- [x] Definición del alcance
- [x] Ciclo de vida del pedido
- [x] Ciclo de vida del stock
- [x] Recepción desde CD
- [x] Gestión de incidencias y matriz de resolución
- [x] Campaign Readiness
- [x] Devoluciones
- [x] Reglas de negocio consolidadas
- [ ] Modelo de datos
- [ ] Implementación SQL
- [ ] ETL
- [ ] Análisis Python
- [ ] KPIs
- [ ] Dashboard Power BI
- [ ] Hallazgos y recomendaciones

## 👤 Rol simulado

Durante el proyecto se simula el rol de **Analista de Operaciones E-commerce**: monitorear indicadores, detectar desviaciones operativas, analizar causas y proponer acciones de mejora en coordinación con las áreas involucradas.

## 📈 Resultado esperado

```
Datos operativos → Información → Indicadores → Diagnóstico → Acciones
```

Un Control Tower de Operaciones E-commerce acompañado de documentación técnica y de negocio que explique no solo qué muestran los datos, sino por qué se diseñó la solución de esa manera y qué decisiones puede apoyar.

## 📌 Nota

Origen es un proyecto ficticio desarrollado con fines educativos y de portafolio. Los datos utilizados son simulados y diseñados para representar escenarios plausibles de una operación e-commerce de retail.