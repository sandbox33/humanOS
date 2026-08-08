"""
HumanOS — Motor nutricional.

Todo el cálculo vive aquí. Sin dependencias de UI ni de base de datos:
recibe valores, devuelve valores. Eso lo hace testeable y reutilizable.
"""

import datetime as dt
from dataclasses import dataclass, field
from typing import Iterable

import config


# ---------------------------------------------------------------------------
# Gasto energético
# ---------------------------------------------------------------------------

def bmr_mifflin(peso_kg: float, estatura_cm: float, edad: int,
                sexo: str = "m") -> float:
    """
    Tasa metabólica basal — ecuación de Mifflin-St Jeor.
    Es la que menor error promedio tiene frente a calorimetría indirecta
    en población no obesa.
    """
    base = 10 * peso_kg + 6.25 * estatura_cm - 5 * edad
    return base + 5 if sexo == "m" else base - 161


def tdee(peso_kg: float, estatura_cm: float, edad: int,
         nivel_actividad: str = config.DEFAULT_ACTIVIDAD,
         sexo: str = "m") -> float:
    """Gasto energético total diario (mantenimiento)."""
    factor = config.FACTOR_ACTIVIDAD.get(
        nivel_actividad, config.FACTOR_ACTIVIDAD[config.DEFAULT_ACTIVIDAD]
    )
    return bmr_mifflin(peso_kg, estatura_cm, edad, sexo) * factor


@dataclass
class ObjetivoDiario:
    mantenimiento_kcal: float
    objetivo_kcal: float
    superavit_kcal: float
    proteina_g: float
    proteina_min_por_comida_g: float

    def __str__(self) -> str:
        return (f"{self.objetivo_kcal:.0f} kcal "
                f"({self.superavit_kcal:+.0f} sobre mantenimiento) · "
                f"{self.proteina_g:.0f} g proteína")


def objetivo_diario(peso_kg: float, estatura_cm: float, edad: int,
                    nivel_actividad: str = config.DEFAULT_ACTIVIDAD,
                    superavit_pct: float = config.SUPERAVIT_PCT,
                    proteina_g_por_kg: float = config.PROTEINA_G_POR_KG,
                    sexo: str = "m") -> ObjetivoDiario:
    """
    Objetivo calórico y proteico del día.

    Superávit: +10-20%. Por encima de eso la ganancia extra es
    mayoritariamente grasa, no músculo.
    """
    mantenimiento = tdee(peso_kg, estatura_cm, edad, nivel_actividad, sexo)
    superavit = mantenimiento * superavit_pct
    return ObjetivoDiario(
        mantenimiento_kcal=mantenimiento,
        objetivo_kcal=mantenimiento + superavit,
        superavit_kcal=superavit,
        proteina_g=peso_kg * proteina_g_por_kg,
        proteina_min_por_comida_g=peso_kg * config.PROTEINA_MIN_POR_COMIDA_G_KG,
    )


# ---------------------------------------------------------------------------
# Reparto por comida
# ---------------------------------------------------------------------------

@dataclass
class MetaComida:
    orden: int
    nombre: str
    hora_str: str
    kcal: float
    proteina_g: float


def repartir(objetivo: ObjetivoDiario, comidas: Iterable) -> list:
    """
    Reparte el objetivo diario entre las comidas según su peso calórico.

    La proteína NO se reparte por peso calórico: se distribuye lo más pareja
    posible, porque la síntesis proteica responde a la dosis por toma, no al
    total diario acumulado. Cada comida recibe al menos el piso de ~0.4 g/kg
    cuando el total lo permite.
    """
    comidas = list(comidas)
    if not comidas:
        return []

    total_peso = sum(c.peso_calorico for c in comidas) or 1.0
    n = len(comidas)

    prot_pareja = objetivo.proteina_g / n
    prot_por_comida = max(prot_pareja, objetivo.proteina_min_por_comida_g)
    # Si el piso empuja el total por encima del objetivo, se vuelve a lo parejo.
    if prot_por_comida * n > objetivo.proteina_g * 1.15:
        prot_por_comida = prot_pareja

    metas = []
    for c in comidas:
        metas.append(MetaComida(
            orden=c.orden,
            nombre=c.nombre,
            hora_str=f"{c.hora:02d}:{c.minuto:02d}",
            kcal=objetivo.objetivo_kcal * (c.peso_calorico / total_peso),
            proteina_g=prot_por_comida,
        ))
    return metas


# ---------------------------------------------------------------------------
# Porciones concretas
# ---------------------------------------------------------------------------

def macros_de(alimento: str, gramos: float) -> dict:
    """kcal y proteína de N gramos de un alimento de la tabla base."""
    datos = config.ALIMENTOS.get(alimento)
    if not datos:
        return {"kcal": 0.0, "proteina_g": 0.0}
    f = gramos / 100.0
    return {"kcal": datos["kcal"] * f, "proteina_g": datos["prot"] * f}


def macros_de_plato(items: dict) -> dict:
    """items = {'arroz_cocido': 200, 'huevo': 120} -> totales."""
    kcal = prot = 0.0
    for alimento, gramos in items.items():
        m = macros_de(alimento, gramos)
        kcal += m["kcal"]
        prot += m["proteina_g"]
    return {"kcal": kcal, "proteina_g": prot}


def sugerir_porciones(meta: MetaComida, fuente_proteica: str,
                      base_calorica: str, grasa: str = None) -> dict:
    """
    Calcula gramos concretos para alcanzar la meta de una comida.

    Estrategia: primero se cubre la proteína con la fuente proteica, luego se
    rellenan las calorías restantes con la base calórica, y la grasa se usa
    como ajuste fino si aún falta densidad.

    Devuelve {'porciones': {alimento: gramos}, 'kcal': x, 'proteina_g': y}
    """
    porciones = {}

    prot_datos = config.ALIMENTOS.get(fuente_proteica)
    if prot_datos and prot_datos["prot"] > 0:
        gramos_prot = (meta.proteina_g / prot_datos["prot"]) * 100.0
        porciones[fuente_proteica] = round(gramos_prot)

    actual = macros_de_plato(porciones)
    kcal_faltante = meta.kcal - actual["kcal"]

    base_datos = config.ALIMENTOS.get(base_calorica)
    if base_datos and base_datos["kcal"] > 0 and kcal_faltante > 0:
        # Si hay grasa disponible, se le reserva ~25% del hueco calórico.
        reserva = 0.25 if grasa else 0.0
        gramos_base = ((kcal_faltante * (1 - reserva)) / base_datos["kcal"]) * 100.0
        porciones[base_calorica] = round(gramos_base)

    if grasa:
        actual = macros_de_plato(porciones)
        kcal_faltante = meta.kcal - actual["kcal"]
        grasa_datos = config.ALIMENTOS.get(grasa)
        if grasa_datos and grasa_datos["kcal"] > 0 and kcal_faltante > 0:
            porciones[grasa] = round((kcal_faltante / grasa_datos["kcal"]) * 100.0)

    total = macros_de_plato(porciones)
    return {
        "porciones": porciones,
        "kcal": total["kcal"],
        "proteina_g": total["proteina_g"],
    }


# ---------------------------------------------------------------------------
# Advertencias de interacción
# ---------------------------------------------------------------------------

@dataclass
class Advertencia:
    regla_id: str
    mensaje: str
    severidad: str
    alimentos: tuple = field(default_factory=tuple)


def _etiquetas(alimentos: Iterable[str]) -> set:
    tags = set()
    for a in alimentos:
        datos = config.ALIMENTOS.get(a)
        if datos:
            tags |= datos["etiquetas"]
        tags.add(a)
    return tags


def revisar_interacciones(alimentos_comida: Iterable[str],
                          orden_comida: int = None,
                          alimentos_recientes: Iterable[str] = (),
                          minutos_desde_reciente: int = 999) -> list:
    """
    Devuelve ADVERTENCIAS, nunca bloqueos.

    La magnitud de estas interacciones es modesta. Bloquear una comida por
    ellas produce que el usuario desactive el sistema entero, que es un
    resultado mucho peor que absorber algo menos de hierro.
    """
    advertencias = []
    tags_ahora = _etiquetas(alimentos_comida)
    tags_antes = _etiquetas(alimentos_recientes)

    for regla in config.REGLAS_INTERACCION:
        solo = regla.get("solo_comidas")
        if solo and orden_comida not in solo:
            continue

        grupo_a = regla["grupo_a"]
        grupo_b = regla["grupo_b"]

        # Reglas de un solo grupo (contexto, no combinación)
        if not grupo_b:
            if tags_ahora & grupo_a:
                advertencias.append(Advertencia(
                    regla_id=regla["id"],
                    mensaje=regla["mensaje"],
                    severidad=regla["severidad"],
                    alimentos=tuple(tags_ahora & grupo_a),
                ))
            continue

        # Combinación dentro de la misma comida
        choque_mismo = bool(tags_ahora & grupo_a) and bool(tags_ahora & grupo_b)

        # Combinación con una comida reciente dentro de la ventana
        dentro_ventana = minutos_desde_reciente <= regla["ventana_min"]
        choque_previo = dentro_ventana and (
            (bool(tags_ahora & grupo_a) and bool(tags_antes & grupo_b)) or
            (bool(tags_ahora & grupo_b) and bool(tags_antes & grupo_a))
        )

        if choque_mismo or choque_previo:
            advertencias.append(Advertencia(
                regla_id=regla["id"],
                mensaje=regla["mensaje"],
                severidad=regla["severidad"],
                alimentos=tuple((tags_ahora | tags_antes) & (grupo_a | grupo_b)),
            ))

    return advertencias


# ---------------------------------------------------------------------------
# Ventanas de sueño
# ---------------------------------------------------------------------------

def ventanas_sueño(hora_despertar: dt.time,
                   duracion_objetivo_h: float = config.SUEÑO_OBJETIVO_H) -> dict:
    """
    Ventana recomendada para acostarse.

    Se devuelve un RANGO, no una hora exacta. Los ciclos de sueño varían
    entre ~70 y 120 minutos y cambian a lo largo de la noche; calcular la
    hora al minuto sobre un ciclo fijo de 90 min da precisión falsa.

    Lo que domina es la duración total (7-9 h) y la regularidad de la hora
    de despertar, no la alineación con un ciclo.
    """
    hoy = dt.date.today()
    despertar = dt.datetime.combine(hoy, hora_despertar)

    # ~20 min para conciliar el sueño
    latencia = dt.timedelta(minutes=20)

    ideal = despertar - dt.timedelta(hours=duracion_objetivo_h) - latencia
    temprano = despertar - dt.timedelta(hours=9.0) - latencia
    tarde = despertar - dt.timedelta(hours=7.0) - latencia

    return {
        "ideal": ideal.time(),
        "rango_inicio": temprano.time(),
        "rango_fin": tarde.time(),
        "nota": "Rango para 7-9 h. La regularidad importa más que el minuto exacto.",
    }
