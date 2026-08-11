"""
HumanOS — Motor de hábitos.

PURO: no importa `database` ni `flet`. Recibe DTOs planos y devuelve
resultados. Se prueba sin base de datos ni interfaz.

DISEÑO — tres rachas separadas, no una sola:

  racha_individual  — por hábito, contra su propio criterio
  racha_global      — día completo, suma ponderada, umbral 70%
  racha_minima      — solo las 2-3 acciones esenciales

La razón de separarlas: una sola racha todo-o-nada convierte "fallé en
leer" en "el día fue un fracaso", y eso produce el ciclo
fallo → vergüenza → abandono. Con tres niveles, fallar un hábito
secundario no borra el hecho de que cumpliste lo esencial.

Además: un día sin registro NO cuenta como fallo. Se trata como
desconocido y detiene el conteo, sin asumir lo peor. Inventar fracaso a
partir de silencio sería peor que no medir.
"""

import datetime as dt
from dataclasses import dataclass

# Umbral del puntaje global para que el día cuente. 0.70 viene de la
# literatura de intervenciones digitales de cambio conductual: exigir
# 100% hace la racha frágil y contraproducente.
UMBRAL_GLOBAL = 0.70

# Acciones esenciales que hay que cumplir para el "día mínimo". Si tienes
# 3 esenciales, cumplir 2 basta — la racha mínima existe justo para los
# días malos, y exigir las 3 la volvería tan frágil como la global.
MINIMO_ESENCIALES = 2


# ---------------------------------------------------------------------------
# DTOs — puente con la base de datos
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class DefHabito:
    """Definición de un hábito. main.py lo construye desde el modelo Habito."""
    nombre: str
    tipo_objetivo: str        # 'binario' | 'aumentar' | 'reducir'
    valor_objetivo: float = 1.0
    umbral: float = 1.0       # fracción de valor_objetivo que cuenta como cumplido
    peso: float = 1.0
    esencial: bool = False
    tolerancia: float = None  # solo 'reducir': margen antes de caer a 0


@dataclass(frozen=True)
class RegistroHabito:
    """Un día de un hábito. valor=None significa 'no registrado'."""
    fecha: dt.date
    valor: float = None


@dataclass
class ResultadoHabito:
    cumplimiento: float   # 0.0 - 1.0
    completado: bool
    sin_dato: bool = False


# ---------------------------------------------------------------------------
# Evaluación de un hábito en un día
# ---------------------------------------------------------------------------

def evaluar(habito: DefHabito, valor: float) -> ResultadoHabito:
    """
    'aumentar'  — más es mejor, capado a 1.0. Hacer 45 min de una meta de
                  30 da 1.0, no 1.5: pasarse en un hábito no compensa
                  haber fallado en otro.
    'reducir'   — menos es mejor. Con tolerancia, la caída es gradual en
                  vez de binaria (60 min límite + 30 tolerancia: 75 min
                  da 0.5, no 0).
    'binario'   — se hizo o no se hizo.
    """
    if valor is None:
        return ResultadoHabito(cumplimiento=0.0, completado=False, sin_dato=True)

    objetivo = habito.valor_objetivo or 1.0

    if habito.tipo_objetivo == "aumentar":
        cumplimiento = min(valor / objetivo, 1.0) if objetivo else 0.0
        completado = cumplimiento >= habito.umbral

    elif habito.tipo_objetivo == "reducir":
        if valor <= objetivo:
            cumplimiento = 1.0
        elif habito.tolerancia:
            exceso = valor - objetivo
            cumplimiento = max(0.0, 1.0 - exceso / habito.tolerancia)
        else:
            cumplimiento = 0.0
        completado = valor <= objetivo

    else:  # binario
        cumplimiento = 1.0 if valor else 0.0
        completado = bool(valor)

    return ResultadoHabito(cumplimiento=cumplimiento, completado=completado)


# ---------------------------------------------------------------------------
# Nivel 1 — racha individual
# ---------------------------------------------------------------------------

def racha_individual(habito: DefHabito, registros: list) -> int:
    """
    Días consecutivos con el hábito completado, desde el más reciente
    hacia atrás. Un día sin registro detiene el conteo (no lo cuenta
    como fallo ni como éxito).
    """
    por_fecha = {r.fecha: r.valor for r in registros}
    racha = 0
    dia = dt.date.today()

    while True:
        if dia not in por_fecha:
            break
        resultado = evaluar(habito, por_fecha[dia])
        if resultado.sin_dato or not resultado.completado:
            break
        racha += 1
        dia -= dt.timedelta(days=1)

    return racha


# ---------------------------------------------------------------------------
# Nivel 2 — puntaje y racha global
# ---------------------------------------------------------------------------

@dataclass
class PuntajeDia:
    fecha: dt.date
    puntos_obtenidos: float
    puntos_posibles: float
    sin_registros: bool = False

    @property
    def fraccion(self) -> float:
        if not self.puntos_posibles:
            return 0.0
        return self.puntos_obtenidos / self.puntos_posibles

    @property
    def pct(self) -> float:
        return round(self.fraccion * 100, 1)

    @property
    def dia_completado(self) -> bool:
        return (not self.sin_registros) and self.fraccion >= UMBRAL_GLOBAL


def puntaje_dia(habitos: list, valores: dict, fecha: dt.date = None) -> PuntajeDia:
    """
    habitos: lista de DefHabito activos.
    valores: {nombre_habito: valor_del_dia}. Ausente = no registrado.

    Un hábito creado después de esta fecha no debe aparecer en `habitos`
    — main.py filtra por fecha de creación. De lo contrario, agregar un
    hábito nuevo bajaría retroactivamente el puntaje de días pasados.
    """
    fecha = fecha or dt.date.today()
    obtenidos = 0.0
    posibles = 0.0
    hubo_registro = False

    for h in habitos:
        posibles += h.peso
        valor = valores.get(h.nombre)
        if valor is not None:
            hubo_registro = True
        resultado = evaluar(h, valor)
        obtenidos += h.peso * resultado.cumplimiento

    return PuntajeDia(fecha=fecha, puntos_obtenidos=obtenidos,
                      puntos_posibles=posibles,
                      sin_registros=not hubo_registro)


def racha_global(habitos: list, valores_por_dia: dict) -> int:
    """
    valores_por_dia: {fecha: {nombre_habito: valor}}

    Días consecutivos con puntaje >= 70%, desde hoy hacia atrás. Un día
    sin ningún registro detiene el conteo sin contarlo como fallo.
    """
    racha = 0
    dia = dt.date.today()

    while True:
        if dia not in valores_por_dia:
            break
        p = puntaje_dia(habitos, valores_por_dia[dia], fecha=dia)
        if not p.dia_completado:
            break
        racha += 1
        dia -= dt.timedelta(days=1)

    return racha


# ---------------------------------------------------------------------------
# Nivel 3 — racha mínima (la que sobrevive los días malos)
# ---------------------------------------------------------------------------

@dataclass
class ResultadoMinimo:
    esenciales_totales: int
    esenciales_cumplidos: int
    cumplido: bool
    sin_registros: bool = False


def dia_minimo(habitos: list, valores: dict) -> ResultadoMinimo:
    """Cumple el mínimo si al menos MINIMO_ESENCIALES esenciales están hechos."""
    esenciales = [h for h in habitos if h.esencial]
    if not esenciales:
        return ResultadoMinimo(0, 0, False, sin_registros=True)

    cumplidos = 0
    hubo_registro = False
    for h in esenciales:
        valor = valores.get(h.nombre)
        if valor is not None:
            hubo_registro = True
        if evaluar(h, valor).completado:
            cumplidos += 1

    requeridos = min(MINIMO_ESENCIALES, len(esenciales))
    return ResultadoMinimo(
        esenciales_totales=len(esenciales),
        esenciales_cumplidos=cumplidos,
        cumplido=cumplidos >= requeridos,
        sin_registros=not hubo_registro,
    )


def racha_minima(habitos: list, valores_por_dia: dict) -> int:
    """Días consecutivos cumpliendo el mínimo. Esta es la que aguanta rachas malas."""
    racha = 0
    dia = dt.date.today()

    while True:
        if dia not in valores_por_dia:
            break
        r = dia_minimo(habitos, valores_por_dia[dia])
        if r.sin_registros or not r.cumplido:
            break
        racha += 1
        dia -= dt.timedelta(days=1)

    return racha


# ---------------------------------------------------------------------------
# Resumen — lo que main.py va a pintar
# ---------------------------------------------------------------------------

@dataclass
class ResumenHabitos:
    puntaje_hoy: PuntajeDia
    minimo_hoy: ResultadoMinimo
    racha_global_dias: int
    racha_minima_dias: int
    rachas_individuales: dict   # {nombre: días}
    sugerir_mision_minima: bool


def resumen(habitos: list, valores_por_dia: dict) -> ResumenHabitos:
    """
    sugerir_mision_minima: dos días seguidos sin cumplir el mínimo. En vez
    de marcar el fallo, la interfaz propone una acción corta (5-10 min).
    Es una rampa de reentrada, no un castigo — por eso no se muestra en
    rojo ni acompañado de un contador de fallos.
    """
    hoy = dt.date.today()
    ayer = hoy - dt.timedelta(days=1)

    valores_hoy = valores_por_dia.get(hoy, {})
    p_hoy = puntaje_dia(habitos, valores_hoy, fecha=hoy)
    m_hoy = dia_minimo(habitos, valores_hoy)

    m_ayer = dia_minimo(habitos, valores_por_dia.get(ayer, {}))
    fallo_hoy = (not m_hoy.cumplido) and not m_hoy.sin_registros
    fallo_ayer = (not m_ayer.cumplido) and not m_ayer.sin_registros

    individuales = {}
    for h in habitos:
        registros = [RegistroHabito(fecha=f, valor=v.get(h.nombre))
                     for f, v in valores_por_dia.items()]
        individuales[h.nombre] = racha_individual(h, registros)

    return ResumenHabitos(
        puntaje_hoy=p_hoy,
        minimo_hoy=m_hoy,
        racha_global_dias=racha_global(habitos, valores_por_dia),
        racha_minima_dias=racha_minima(habitos, valores_por_dia),
        rachas_individuales=individuales,
        sugerir_mision_minima=fallo_hoy and fallo_ayer,
    )
