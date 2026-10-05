#!/usr/bin/env python3
"""
ORIGEN — Paso 1: extracción de las 6 vistas analíticas → data/raw/*.csv.

Solo lectura: cada vista se lee con `SELECT * FROM <vista>`. No se modifica
SQL Server, no se filtran registros, no se agregan ni se calculan KPIs: las
columnas y filas se conservan tal cual (la separación entre datos heredados
y escenario Fase 4 se decide en el EDA, no en la extracción).

Uso:
    python etl/extract/01_extract_views.py

Salida: un CSV por vista en data/raw/ (UTF-8, sin índice), con registro de
vista consultada, filas, columnas y archivo generado.
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path

import pandas as pd

# La raíz del repo permite importar python/utils/conexion.py sin instalar nada.
RAIZ = Path(__file__).resolve().parents[2]
if str(RAIZ) not in sys.path:
    sys.path.insert(0, str(RAIZ))

from python.utils.conexion import get_connection  # noqa: E402

# (vista analítica, nombre exacto del CSV de salida)
VISTAS = (
    ("dbo.vw_PedidosOperaciones", "pedidos_operaciones.csv"),
    ("dbo.vw_TiemposEstados", "tiempos_estados.csv"),
    ("dbo.vw_IncidenciasPicking", "incidencias.csv"),
    ("dbo.vw_MovimientosInventario", "movimientos.csv"),
    ("dbo.vw_StockHistorico", "stock_historico.csv"),
    ("dbo.vw_Devoluciones", "devoluciones.csv"),
)

DESTINO = RAIZ / "data" / "raw"

logging.basicConfig(
    level=logging.INFO,
    format="%(levelname)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("extract")


def extraer_vista(conexion: pyodbc.Connection, vista: str) -> pd.DataFrame:
    """SELECT * FROM <vista> — sin filtros, sin agregaciones, sin transformaciones.

    Se lee con un cursor de pyodbc (y no con pd.read_sql_query) para evitar el
    aviso de pandas sobre conexiones DBAPI2 "no probadas": mismas columnas y
    mismos tipos, sin necesidad de librerías adicionales.
    """
    with conexion.cursor() as cursor:
        cursor.execute(f"SELECT * FROM {vista}")
        columnas = [columna[0] for columna in cursor.description]
        filas = [tuple(fila) for fila in cursor.fetchall()]
    return pd.DataFrame(filas, columns=columnas)


def main() -> int:
    # Crea data/raw/ si no existe (idempotente).
    DESTINO.mkdir(parents=True, exist_ok=True)
    log.info("Destino: %s", DESTINO.relative_to(RAIZ))

    try:
        conexion = get_connection()
    except Exception as exc:  # sin conexión no hay nada que extraer
        log.error("No se pudo conectar a SQL Server: %s", exc)
        return 1

    errores = 0
    with conexion:
        for numero, (vista, archivo) in enumerate(VISTAS, start=1):
            destino = DESTINO / archivo
            try:
                df = extraer_vista(conexion, vista)
                df.to_csv(destino, index=False, encoding="utf-8")
                log.info(
                    "[%d/%d] vista=%s filas=%d columnas=%d archivo=%s",
                    numero,
                    len(VISTAS),
                    vista,
                    len(df),
                    len(df.columns),
                    destino.relative_to(RAIZ),
                )
            except Exception as exc:
                errores += 1
                log.error("[%d/%d] vista=%s FALLÓ: %s", numero, len(VISTAS), vista, exc)

    log.info(
        "Extracción finalizada: %d/%d vistas OK, errores=%d",
        len(VISTAS) - errores,
        len(VISTAS),
        errores,
    )
    return 0 if errores == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
