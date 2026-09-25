/*
===============================================================================
ORIGEN — Creación de base de datos
Fase 3 — Implementación SQL Server
===============================================================================
Qué hace: crea la base de datos que va a alojar todo el modelo definido en
02_modelo_de_datos.md (8 dimensiones + 5 tablas de hechos).

Por qué un collation en español (Modern_Spanish_100_CI_AS):
- CI = Case Insensitive (no distingue mayúsculas/minúsculas al comparar)
- AS = Accent Sensitive (SÍ distingue tildes: "MAS" ≠ "MÁS")
- El sufijo _100_ indica la versión de reglas de ordenación introducida en
  SQL Server 2008, la recomendación vigente para bases nuevas frente a la
  versión heredada sin ese sufijo.
Esto importa porque vamos a tener texto en español (categorías, motivos,
nombres de producto) y queremos que ordene y compare correctamente, por
ejemplo que "Ñ" se ubique donde corresponde en el alfabeto español.
===============================================================================
*/

-- DB_ID() devuelve el ID de la base si existe, o NULL si no existe.
-- Es más idiomático en T-SQL que consultar sys.databases directamente,
-- y logra exactamente el mismo resultado: hace el script idempotente
-- (se puede volver a ejecutar sin que falle si la base ya existe).
IF DB_ID(N'OrigenDB') IS NULL
BEGIN
    CREATE DATABASE OrigenDB
    COLLATE Modern_Spanish_100_CI_AS;
END
GO

-- A partir de aquí, todo lo que ejecutemos debe apuntar a esta base de datos
USE OrigenDB;
GO

-- Verificación rápida: confirma nombre y collation aplicados
SELECT
    name AS NombreBaseDeDatos,
    collation_name AS Collation,
    create_date AS FechaCreacion
FROM sys.databases
WHERE name = N'OrigenDB';
GO