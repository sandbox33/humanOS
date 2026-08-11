"""
HumanOS — Motor de sueño.

PURO, igual que nutrition_engine.py: no importa `database` ni `flet`.
Recibe una lista de RegistroNoche (que main.py saca de SueñoLog) y
devuelve ventana recomendada, deuda acumulada y racha. Se puede probar
sin base de datos.
"""

import datetime as dt
from dataclasses import dataclass

import config


@dataclass(frozen=True)
class RegistroNoche:
    fecha: dt.date
    horas_dormidas: float = None   # None = noche sin registro completo


# ---------------------------------------------------------------------------
# Ventana de acostarse — proyección a partir de la hora de despertar
# ---------------------------------------------------------------------------

def ventanas_sueño(hora_despertar: dt.time,
                   duracion_objetivo_h: float = config.SUEÑO_OBJETIVO_H) -> dict:
    """
    Rango recomendado para acostarse — no una hora exacta.

    Los ciclos de sueño varían entre ~70 y 120 min y cambian a lo largo de
    la noche; calcular al minuto sobre un ciclo fijo de 90 min da precisión
    falsa. Lo que domina es la duración total (7-9 h) y la regularidad del
    despertar, no la alineación con un ciclo — por eso esto es un rango.
    """
    hoy = dt.date.today()
    despertar = dt.datetime.combine(hoy, hora_despertar)
    latencia = dt.timedelta(minutes=20)   # tiempo típico en conciliar el sueño

    ideal = despertar - dt.timedelta(hours=duracion_objetivo_h) - latencia
    temprano = despertar - dt.timedelta(hours=9.0) - latencia
    tarde = despertar - dt.timedelta(hours=7.0) - latencia

    return {
        "ideal": ideal.time(),
        "rango_inicio": temprano.time(),
        "rango_fin": tarde.time(),
        "nota": "Rango para 7-9 h. La regularidad importa más que el minuto exacto.",
    }


# ---------------------------------------------------------------------------
# Deuda de sueño — sobre datos reales, no proyectados
# ---------------------------------------------------------------------------

@dataclass
class ResultadoDeuda:
    noches_con_dato: int
    noches_sin_dato: int
    horas_objetivo_total: float
    horas_reales_total: float
    deuda_h: float   # positivo = debes horas de sueño; negativo = vas adelantado

    @property
    def promedio_real_h(self):
        if not self.noches_con_dato:
            return None
        return round(self.horas_reales_total / self.noches_con_dato, 2)


def deuda_de_sueño(noches: list, dias: int = 7,
                   objetivo_h: float = config.SUEÑO_OBJETIVO_H) -> ResultadoDeuda:
    """
    noches: lista de RegistroNoche, cualquier orden — esta función filtra
    a los últimos `dias` días ella misma.

    Solo cuenta noches con dato real. Si faltan registros, no asume que
    esas noches fueron malas: las reporta como "sin dato", no como deuda.
    Inventar deuda a partir de silencio sería peor que no calcularla.
    """
    corte = dt.date.today() - dt.timedelta(days=dias)
    recientes = [n for n in noches if n.fecha >= corte]

    con_dato = [n for n in recientes if n.horas_dormidas is not None]
    sin_dato = len(recientes) - len(con_dato)

    horas_reales = sum(n.horas_dormidas for n in con_dato)
    horas_objetivo = objetivo_h * len(con_dato)

    return ResultadoDeuda(
        noches_con_dato=len(con_dato),
        noches_sin_dato=sin_dato,
        horas_objetivo_total=horas_objetivo,
        horas_reales_total=horas_reales,
        deuda_h=round(horas_objetivo - horas_reales, 2),
    )


# ---------------------------------------------------------------------------
# Racha de noches buenas — lo que pediste: "acumular días de sueño bueno"
# ---------------------------------------------------------------------------

# 7-9 h es la banda con respaldo real para adultos. No depende de tu
# objetivo personal ajustable — ese mueve la meta de deuda, esto mide
# contra el rango saludable en sí.
RANGO_BUENO_H = (7.0, 9.5)


def racha_actual(noches: list, rango: tuple = RANGO_BUENO_H) -> int:
    """
    Noches consecutivas (desde la más reciente hacia atrás) dentro del
    rango saludable. Se corta en la primera noche sin dato o fuera de rango
    — una noche sin registrar simplemente detiene el conteo ahí, no cuenta
    como buena ni se le asume nada peor.
    """
    ordenadas = sorted(noches, key=lambda n: n.fecha, reverse=True)
    racha = 0
    for n in ordenadas:
        if n.horas_dormidas is None:
            break
        if rango[0] <= n.horas_dormidas <= rango[1]:
            racha += 1
        else:
            break
    return racha
