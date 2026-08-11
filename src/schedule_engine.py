"""
HumanOS — Motor de horario y seguridad alimentaria.

PURO: no importa `database` ni `flet`.

Dos problemas que resuelve:

1. HORARIO VARIABLE. Tu entrada cambia día a día (7:00-7:30) y la salida
   también (17:00-18:00). Un horario de comidas fijo en config.py queda
   corrido apenas entras media hora más tarde. Aquí las horas de comida
   se derivan de la jornada real de ESE día.

2. SIN NEVERA. Bacillus cereus forma esporas que sobreviven la cocción y
   germinan a temperatura ambiente. La toxina emética que producen es
   termoestable: recalentar no la destruye. Por eso el reloj corre desde
   que se cocinó, no desde el último recalentado.
"""

import datetime as dt
from dataclasses import dataclass

import config


# ---------------------------------------------------------------------------
# Seguridad alimentaria sin refrigeración
# ---------------------------------------------------------------------------

# La guía estándar es 2 h a temperatura ambiente; 4 h es el máximo absoluto
# y solo en clima templado. En clima cálido el margen se acorta, no se
# alarga. Por eso son dos umbrales y no un corte único a las 4 h.
HORAS_AVISO = 2.0
HORAS_LIMITE = 4.0

NIVEL_OK = "ok"
NIVEL_AVISO = "aviso"
NIVEL_LIMITE = "limite"


@dataclass
class EstadoCoccion:
    nombre: str
    horas: float
    nivel: str
    mensaje: str

    @property
    def horas_restantes(self) -> float:
        return max(0.0, HORAS_LIMITE - self.horas)


def evaluar_coccion(nombre: str, cocinado_en: dt.datetime,
                    ahora: dt.datetime = None) -> EstadoCoccion:
    ahora = ahora or dt.datetime.now()
    horas = (ahora - cocinado_en).total_seconds() / 3600

    if horas >= HORAS_LIMITE:
        nivel = NIVEL_LIMITE
        mensaje = (f"{nombre}: {horas:.1f} h fuera de refrigeración. "
                   f"Pasó el margen seguro — recalentar no elimina la toxina.")
    elif horas >= HORAS_AVISO:
        nivel = NIVEL_AVISO
        restante = HORAS_LIMITE - horas
        mensaje = (f"{nombre}: {horas:.1f} h cocinado. "
                   f"Cómelo dentro de {restante:.1f} h.")
    else:
        nivel = NIVEL_OK
        mensaje = f"{nombre}: {horas:.1f} h — dentro del margen seguro."

    return EstadoCoccion(nombre=nombre, horas=round(horas, 2),
                         nivel=nivel, mensaje=mensaje)


def revisar_cocciones(items: list, ahora: dt.datetime = None) -> list:
    """items: lista de (nombre, cocinado_en). Devuelve lo más urgente primero."""
    estados = [evaluar_coccion(n, c, ahora) for n, c in items]
    orden = {NIVEL_LIMITE: 0, NIVEL_AVISO: 1, NIVEL_OK: 2}
    return sorted(estados, key=lambda e: (orden[e.nivel], -e.horas))


def hora_limite_consumo(cocinado_en: dt.datetime) -> dt.datetime:
    return cocinado_en + dt.timedelta(hours=HORAS_LIMITE)


# ---------------------------------------------------------------------------
# Horario de comidas derivado de la jornada real
# ---------------------------------------------------------------------------

# Tu receso de almuerzo: 1 hora total, 5 min caminando de ida y 5 de vuelta.
MINUTOS_CAMINATA_IDA = 5
MINUTOS_CAMINATA_VUELTA = 5
MINUTOS_RECESO = 60


@dataclass
class BloqueAlmuerzo:
    inicio_receso: dt.time
    llegada_casa: dt.time
    fin_receso: dt.time
    minutos_para_cocinar_y_comer: int

    def __str__(self):
        return (f"{self.inicio_receso.strftime('%H:%M')} sales · "
                f"{self.llegada_casa.strftime('%H:%M')} llegas · "
                f"{self.minutos_para_cocinar_y_comer} min para cocinar y comer")


def bloque_almuerzo(hora_inicio_receso: dt.time,
                    minutos_receso: int = MINUTOS_RECESO) -> BloqueAlmuerzo:
    """
    El tiempo útil no es la hora del receso: hay que descontar la caminata
    de ida y la de vuelta. De 60 min quedan ~50 reales para cocinar y comer.
    """
    hoy = dt.date.today()
    inicio = dt.datetime.combine(hoy, hora_inicio_receso)
    llegada = inicio + dt.timedelta(minutes=MINUTOS_CAMINATA_IDA)
    fin = inicio + dt.timedelta(minutes=minutos_receso)
    utiles = minutos_receso - MINUTOS_CAMINATA_IDA - MINUTOS_CAMINATA_VUELTA

    return BloqueAlmuerzo(
        inicio_receso=inicio.time(),
        llegada_casa=llegada.time(),
        fin_receso=fin.time(),
        minutos_para_cocinar_y_comer=utiles,
    )


@dataclass
class HorarioDia:
    comidas: list        # [(orden, nombre, dt.time)]
    almuerzo: BloqueAlmuerzo = None
    dia_libre: bool = False
    nota: str = ""


def horario_del_dia(comidas_base: list,
                    hora_entrada: dt.time = None,
                    hora_salida: dt.time = None,
                    hora_almuerzo: dt.time = None,
                    dia_libre: bool = False) -> HorarioDia:
    """
    comidas_base: lista de objetos con .orden, .nombre, .hora, .minuto
                  (las plantillas de config, pensadas para entrada 7:00).

    Desplaza las comidas según la entrada real. Si entras 7:30 en vez de
    7:00, todo se corre 30 min — salvo el almuerzo, que va anclado al
    receso real, no al desplazamiento.

    En día libre no hay desplazamiento: se usan las horas base.
    """
    hoy = dt.date.today()
    ENTRADA_REFERENCIA = dt.time(7, 0)

    if dia_libre or hora_entrada is None:
        desfase = dt.timedelta(0)
        nota = "Día libre — horario base." if dia_libre else \
               "Sin hora de entrada registrada — usando horario base."
    else:
        ref = dt.datetime.combine(hoy, ENTRADA_REFERENCIA)
        real = dt.datetime.combine(hoy, hora_entrada)
        desfase = real - ref
        minutos = int(desfase.total_seconds() / 60)
        nota = ("Horario base." if minutos == 0
                else f"Corrido {minutos:+d} min por tu hora de entrada.")

    salida = []
    for c in comidas_base:
        base = dt.datetime.combine(hoy, dt.time(c.hora, c.minuto))
        salida.append((c.orden, c.nombre, (base + desfase).time()))

    bloque = bloque_almuerzo(hora_almuerzo) if hora_almuerzo else None

    # El almuerzo se ancla al receso real, no al desfase de entrada.
    if bloque:
        salida = [
            (o, n, bloque.llegada_casa if o == 3 else t)
            for o, n, t in salida
        ]

    return HorarioDia(comidas=salida, almuerzo=bloque,
                      dia_libre=dia_libre, nota=nota)


def objetivo_proporcional(objetivo_kcal_completo: float,
                          hora_entrada: dt.time = None,
                          hora_salida: dt.time = None,
                          horas_referencia: float = 10.0,
                          dia_libre: bool = False) -> dict:
    """
    Ajusta el objetivo calórico según las horas realmente trabajadas.

    El gasto no es idéntico un día de 10 h y uno de 6 h. Pero el ajuste es
    parcial (no proporcional puro): el metabolismo basal es la mayor parte
    del gasto y no cambia con las horas trabajadas. Solo se escala la
    porción de actividad — alrededor de un 25% del total en trabajo físico.

    Tres situaciones distintas, que antes se confundían:
      - jornada registrada  → escala por horas reales
      - día libre declarado → se sabe que no hubo trabajo; escala a 0 horas
        laborales, pero conserva un piso porque un día libre no es reposo
        absoluto (caminar, entrenar, tareas de casa)
      - sin datos           → no se sabe nada; objetivo completo, sin
        inventar un recorte
    """
    FRACCION_ACTIVIDAD = config.supuesto("fraccion_actividad", 0.25)
    base = objetivo_kcal_completo * (1 - FRACCION_ACTIVIDAD)
    actividad = objetivo_kcal_completo * FRACCION_ACTIVIDAD

    if dia_libre:
        # Un día libre no es cama todo el día: se conserva ~40% de la
        # porción de actividad por movimiento cotidiano y entrenamiento.
        PISO_DIA_LIBRE = config.supuesto("actividad_dia_libre", 0.40)
        ajustado = base + actividad * PISO_DIA_LIBRE
        return {
            "objetivo_kcal": round(ajustado),
            "horas": 0.0,
            "ajuste_kcal": round(ajustado - objetivo_kcal_completo),
            "estado": "dia_libre",
            "confianza": "media",
            "supuesto": "actividad_dia_libre",
            "nota": (f"Día libre: sin jornada laboral, pero se mantiene "
                     f"~{PISO_DIA_LIBRE:.0%} del gasto por actividad "
                     f"cotidiana. Si entrenas fuerte, come más que esto."),
        }

    if hora_entrada is None or hora_salida is None:
        return {"objetivo_kcal": objetivo_kcal_completo, "horas": None,
                "ajuste_kcal": 0,
                "estado": "sin_datos",
                "confianza": "baja",
                "supuesto": None,
                "nota": ("Sin jornada registrada — objetivo provisional. "
                         "Registra tu entrada y salida para ajustarlo.")}

    hoy = dt.date.today()
    entrada = dt.datetime.combine(hoy, hora_entrada)
    salida = dt.datetime.combine(hoy, hora_salida)
    if salida <= entrada:
        salida += dt.timedelta(days=1)
    horas = (salida - entrada).total_seconds() / 3600

    escalada = actividad * (horas / horas_referencia)
    ajustado = base + escalada

    return {
        "objetivo_kcal": round(ajustado),
        "horas": round(horas, 1),
        "ajuste_kcal": round(ajustado - objetivo_kcal_completo),
        "estado": "jornada",
        "confianza": "alta",
        "supuesto": "fraccion_actividad",
        "nota": (f"{horas:.1f} h trabajadas vs {horas_referencia:.0f} h de "
                 f"referencia. Solo se ajusta la parte de actividad; el gasto "
                 f"basal no cambia."),
    }
