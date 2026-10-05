"""
ORIGEN — Conexión a SQL Server para los extractores (solo lectura).

La conexión se configúa mediante variables de entorno. No hay credenciales
ni en este archivo ni en ningún otro archivo del repositorio.

Variables de entorno (todas opcionales si se usan los valores por defecto):

    ORIGEN_SERVER    Servidor o instancia        (defecto: localhost)
    ORIGEN_DATABASE  Base de datos               (defecto: OrigenDB)
    ORIGEN_AUTH      'windows' | 'sql'           (defecto: windows)
    ORIGEN_UID       Usuario                     (solo si ORIGEN_AUTH=sql)
    ORIGEN_PWD       Contraseña                  (solo si ORIGEN_AUTH=sql;
                                                  NUNCA se escribe en el código
                                                  ni se sube a git)
    ORIGEN_DRIVER    Driver ODBC concreto        (defecto: autodetección)

Procedencia de los valores por defecto (no son inventados): el repositorio
documenta la conexión como `sqlcmd -S localhost -E -d OrigenDB`
(ver cabecera de sql/06_seed_data/03_seed_bloque4.sql): servidor local,
autenticación de Windows y base OrigenDB.
"""

from __future__ import annotations

import os

import pyodbc

# Orden de preferencia para la autodetección del driver ODBC.
_DRIVERS_PREFERIDOS = (
    "ODBC Driver 18 for SQL Server",
    "ODBC Driver 17 for SQL Server",
    "ODBC Driver 13 for SQL Server",
    "SQL Server",
)


def _driver_odbc() -> str:
    """Driver ODBC a usar: variable de entorno o autodetección."""
    driver = os.environ.get("ORIGEN_DRIVER")
    if driver:
        return driver

    disponibles = set(pyodbc.drivers())
    for candidato in _DRIVERS_PREFERIDOS:
        if candidato in disponibles:
            return candidato

    raise RuntimeError(
        "No se encontró ningún driver ODBC para SQL Server. "
        "Instala 'ODBC Driver 17/18 for SQL Server' o define ORIGEN_DRIVER. "
        f"Drivers disponibles: {sorted(disponibles)}"
    )


def cadena_conexion() -> str:
    """Construye la cadena de conexión ODBC a partir de las variables de entorno."""
    servidor = os.environ.get("ORIGEN_SERVER", "localhost")
    base_datos = os.environ.get("ORIGEN_DATABASE", "OrigenDB")
    autenticacion = os.environ.get("ORIGEN_AUTH", "windows").strip().lower()

    partes = [
        f"DRIVER={{{_driver_odbc()}}}",
        f"SERVER={servidor}",
        f"DATABASE={base_datos}",
        # Válido para SQL Server local/desarrollo: no afecta a credenciales,
        # solo evita rechazar el certificado autofirmado del servidor local.
        "TrustServerCertificate=yes",
    ]

    if autenticacion == "windows":
        partes.append("Trusted_Connection=yes")
    elif autenticacion == "sql":
        usuario = os.environ.get("ORIGEN_UID")
        clave = os.environ.get("ORIGEN_PWD")
        if not usuario or not clave:
            raise RuntimeError(
                "ORIGEN_AUTH=sql requiere ORIGEN_UID y ORIGEN_PWD "
                "(defínelos como variables de entorno; no los escribas en el código)."
            )
        partes += [f"UID={usuario}", f"PWD={clave}"]
    else:
        raise RuntimeError(
            f"ORIGEN_AUTH inválido: {autenticacion!r}. Usa 'windows' o 'sql'."
        )

    return ";".join(partes)


def get_connection() -> pyodbc.Connection:
    """Abre y devuelve una conexión pyodbc. El llamado es responsable de cerrarla.

    autocommit=True: la extracción es de solo lectura y no debe mantener
    transacciones abiertas en el servidor.
    """
    return pyodbc.connect(cadena_conexion(), autocommit=True)
