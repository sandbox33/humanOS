"""
HumanOS — Motor nutricional.

PURO: no importa `database` ni `flet`. Recibe listas de ItemInventario
(un DTO plano) y devuelve resultados. Quien conecta esto con la base de
datos real es main.py — así el motor se puede probar sin base de datos
ni interfaz, y no se acopla a cómo Peewee modela las tablas.

CAMBIO CLAVE vs v1: ya no hay `sugerir_porciones()` con una fuente
proteica fija por número de comida. Ahora `armar_combinacion()` recibe
el inventario real disponible y arma la combinación con eso — si no
tienes pollo, no te va a sugerir pollo.
"""

import datetime as dt
from dataclasses import dataclass, field
from typing import Iterable

import config


# ---------------------------------------------------------------------------
# DTO puente con la base de datos
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class ItemInventario:
    """
    Todo lo que el motor necesita saber de un alimento disponible.
    main.py construye esto desde Alimento + InventarioItem.
    """
    nombre: str
    kcal_100g: float
    proteina_100g: float
    etiquetas: frozenset
    gramos_disponibles: float
    categoria: str = "otro"   # verdura|fruta|grano|proteina|lacteo|grasa|bebida


# ---------------------------------------------------------------------------
# Gasto energético (sin cambios vs v1 — no depende de inventario)
# ---------------------------------------------------------------------------

def bmr_mifflin(peso_kg: float, estatura_cm: float, edad: int,
                sexo: str = "m") -> float:
    """Mifflin-St Jeor — menor error promedio frente a calorimetría indirecta."""
    base = 10 * peso_kg + 6.25 * estatura_cm - 5 * edad
    return base + 5 if sexo == "m" else base - 161


def tdee(peso_kg: float, estatura_cm: float, edad: int,
         nivel_actividad: str = config.DEFAULT_ACTIVIDAD,
         sexo: str = "m") -> float:
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
    # Desglose del plan de proteína. Existe porque el mínimo por toma puede
    # empujar el plan por encima del objetivo diario, y esa diferencia debe
    # verse explicada en pantalla, no aparecer como una cifra rara.
    proteina_plan_g: float = None
    proteina_por_comida_g: float = None

    @property
    def exceso_proteina_g(self) -> float:
        if self.proteina_plan_g is None:
            return 0.0
        return round(self.proteina_plan_g - self.proteina_g, 1)

    @property
    def exceso_proteina_pct(self) -> float:
        if not self.proteina_g or self.proteina_plan_g is None:
            return 0.0
        return round((self.proteina_plan_g / self.proteina_g - 1) * 100, 1)

    def explicacion_proteina(self, peso_kg: float = None) -> str:
        if self.exceso_proteina_g <= 0.5:
            return ""
        # Nota de redacción: 0.4 g/kg por toma es un objetivo práctico de
        # reparto, no un umbral que "enciende" la síntesis proteica — la
        # respuesta es graduada, no binaria.
        base = (f"El plan aporta {self.proteina_plan_g:.0f} g frente a un "
                f"objetivo de {self.proteina_g:.0f} g "
                f"({self.exceso_proteina_pct:+.0f}%). El exceso viene del "
                f"mínimo configurado de {self.proteina_min_por_comida_g:.0f} g "
                f"por comida para repartir la proteína del día.")
        if peso_kg:
            base += f" Total: {self.proteina_plan_g/peso_kg:.1f} g/kg."
        return base

    def __str__(self) -> str:
        return (f"{self.objetivo_kcal:.0f} kcal "
                f"({self.superavit_kcal:+.0f} sobre mantenimiento) · "
                f"{self.proteina_g:.0f} g proteína")


def objetivo_diario(peso_kg: float, estatura_cm: float, edad: int,
                    nivel_actividad: str = config.DEFAULT_ACTIVIDAD,
                    superavit_pct: float = config.SUPERAVIT_PCT,
                    proteina_g_por_kg: float = config.PROTEINA_G_POR_KG,
                    sexo: str = "m") -> ObjetivoDiario:
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
# Reparto por comida (sin cambios vs v1)
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
    La proteína se reparte lo más pareja posible (no por peso calórico):
    la síntesis proteica responde a la dosis por toma (~0.4 g/kg), no al
    total diario acumulado.
    """
    comidas = list(comidas)
    if not comidas:
        return []

    total_peso = sum(c.peso_calorico for c in comidas) or 1.0
    n = len(comidas)

    prot_pareja = objetivo.proteina_g / n
    prot_por_comida = max(prot_pareja, objetivo.proteina_min_por_comida_g)

    # El mínimo por toma no puede inflar el plan en silencio: si excede la
    # tolerancia, se cae al reparto parejo.
    tolerancia = config.supuesto("tolerancia_proteina", 0.15)
    if prot_por_comida * n > objetivo.proteina_g * (1 + tolerancia):
        prot_por_comida = prot_pareja

    objetivo.proteina_por_comida_g = round(prot_por_comida, 1)
    objetivo.proteina_plan_g = round(prot_por_comida * n, 1)

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
# Clasificación de alimentos por macros — no por etiqueta manual
# ---------------------------------------------------------------------------
# Se clasifica por densidad de macros, no por una categoría que alguien
# tuvo que asignar a mano. Así funciona igual con alimentos que agregues
# tú al catálogo después, sin tocar código.

def es_proteico(item: ItemInventario) -> bool:
    """
    >=6 g de proteína por 100g Y >=5 g de proteína por cada 100 kcal.
    La segunda condición existe para que verduras de pocas calorías
    (espinaca, brócoli) no se cuelen como "fuente proteica" solo porque
    su ratio se dispara al tener kcal casi nulas.
    """
    if item.proteina_100g < 6.0:
        return False
    densidad = item.proteina_100g / max(item.kcal_100g, 1) * 100
    return densidad >= 5.0


def es_base_energetica(item: ItemInventario) -> bool:
    """
    Comida real para llenar calorías (arroz, papa, pan, avena, plátano...).
    No proteico, y por debajo del umbral de "grasa concentrada" — evita que
    el aceite compita de igual a igual con el arroz por densidad calórica.
    """
    if item.categoria in CATEGORIAS_NO_COMIDA:
        return False
    return not es_proteico(item) and 80.0 <= item.kcal_100g < 600.0


def es_grasa_concentrada(item: ItemInventario) -> bool:
    """
    Aceites, mantecas: muchas kcal en poco volumen. Se usan AL FINAL y en
    poca cantidad — nadie come 100g de aceite puro como base de un plato.
    """
    return not es_proteico(item) and item.kcal_100g >= 600.0


# Las bebidas no son comida aunque tengan pocas calorías. Sin esta
# exclusión el motor metía 370 g de infusión de jamaica en un plato como
# si fuera verdura: cumple "pocas kcal y sin proteína", pero no aporta
# nada de lo que se busca en esa fase.
CATEGORIAS_NO_COMIDA = {"bebida"}


def es_verdura(item: ItemInventario) -> bool:
    """
    Verdura o fruta: pocas calorías, sin proteína relevante, y comida de
    verdad — no una bebida.

    Estas quedaban fuera del armado porque no sirven para llenar kcal ni
    proteína, que era exactamente el error: su aporte es de
    micronutrientes. El brócoli no entra al plato por sus 34 kcal, entra
    por sus 89 mg de vitamina C, que mejoran bastante la absorción del
    hierro vegetal del resto de la comida.
    """
    if item.categoria in CATEGORIAS_NO_COMIDA:
        return False
    if "infusion" in item.etiquetas:
        return False
    return not es_proteico(item) and item.kcal_100g < 80.0


# Porción fija de verdura por comida. No se calcula desde la meta calórica
# porque su razón de estar no es calórica.
GRAMOS_VERDURA_POR_COMIDA = 120.0


# ---------------------------------------------------------------------------
# Motor de combinaciones — el reemplazo real de sugerir_porciones()
# ---------------------------------------------------------------------------

MAX_PORCION_G = 400.0        # tope duro por alimento — evita "800 g de arroz"
MAX_KCAL_BASE_ITEM = 500.0   # tope de kcal que aporta UN alimento base
MAX_KCAL_GRASA_ITEM = 150.0  # tope de kcal desde grasa concentrada — es aderezo, no plato


@dataclass
class Advertencia:
    regla_id: str
    mensaje: str
    severidad: str


@dataclass
class ResultadoCombinacion:
    porciones: dict                    # {nombre: gramos}
    kcal: float
    proteina_g: float
    meta_kcal: float
    meta_proteina_g: float
    advertencias_interaccion: list = field(default_factory=list)
    faltantes: list = field(default_factory=list)   # escasez de inventario, en texto

    @property
    def precision_kcal_pct(self) -> float:
        return round(100 * self.kcal / self.meta_kcal, 1) if self.meta_kcal else 0.0

    @property
    def precision_proteina_pct(self) -> float:
        return round(100 * self.proteina_g / self.meta_proteina_g, 1) if self.meta_proteina_g else 0.0

    @property
    def viable(self) -> bool:
        """Llega a al menos ~85% de ambas metas con lo que hay disponible."""
        return self.precision_kcal_pct >= 85 and self.precision_proteina_pct >= 85


def _llenar(porciones, stock, kcal_acum, prot_acum, kcal_objetivo_restante,
           candidatos, tope_kcal_item):
    """Reparte kcal_objetivo_restante entre candidatos, más denso primero,
    respetando stock y un tope de kcal por alimento individual."""
    for it in candidatos:
        if kcal_objetivo_restante <= 1:
            break
        tope_stock = stock.get(it.nombre, 0)
        tope_kcal = (tope_kcal_item / it.kcal_100g) * 100 if it.kcal_100g else 0
        tope = min(tope_stock, tope_kcal, MAX_PORCION_G)
        if tope < 1:
            continue
        gramos_necesarios = (kcal_objetivo_restante / it.kcal_100g) * 100
        gramos = round(min(gramos_necesarios, tope))
        if gramos < 1:
            continue
        porciones[it.nombre] = porciones.get(it.nombre, 0) + gramos
        aportado_kcal = it.kcal_100g * gramos / 100
        kcal_acum += aportado_kcal
        prot_acum += it.proteina_100g * gramos / 100
        kcal_objetivo_restante -= aportado_kcal
        stock[it.nombre] -= gramos
    return kcal_acum, prot_acum, kcal_objetivo_restante


def armar_combinacion(meta: MetaComida, disponibles: list,
                      extras: dict = None) -> ResultadoCombinacion:
    """
    disponibles: lista de ItemInventario con gramos_disponibles > 0.
    extras: {nombre: gramos} — cosas que vas a tomar igual (café, té) aunque
    no aporten a la meta de macros. No participan del llenado automático,
    pero sí se suman al total y entran en la revisión de interacciones —
    sin esto, un café que no aporta kcal nunca sería "elegido" por el
    algoritmo y su interacción con hierro pasaría desapercibida.

    Prioriza precisión (tu elección explícita sobre costo/variedad):
    1) proteína, con lo más denso en proteína que tengas
    2) kcal restantes, con comida real (arroz, papa, pan...)
    3) si aún falta, grasa concentrada (aceite) en poca cantidad — aderezo,
       no plato principal

    Si el inventario no alcanza, `faltantes` lo dice — no rellena con algo
    que no tienes.
    """
    stock = {it.nombre: it.gramos_disponibles for it in disponibles}
    por_nombre = {it.nombre: it for it in disponibles}
    porciones: dict = {}
    kcal_acum = 0.0
    prot_acum = 0.0
    faltantes = []

    # --- Fase 0: verdura disponible, por micronutrientes ---
    # Va primero a propósito: si entrara al final, el llenado calórico ya
    # habría cerrado la meta y la verdura nunca aparecería. Sus kcal son
    # pocas y se descuentan de lo que queda por llenar.
    verduras = sorted((it for it in disponibles if es_verdura(it)),
                      key=lambda it: it.gramos_disponibles, reverse=True)
    for it in verduras[:2]:   # máximo dos verduras por comida
        tope = min(stock.get(it.nombre, 0), GRAMOS_VERDURA_POR_COMIDA)
        gramos = round(tope)
        if gramos < 20:
            continue
        porciones[it.nombre] = porciones.get(it.nombre, 0) + gramos
        kcal_acum += it.kcal_100g * gramos / 100
        prot_acum += it.proteina_100g * gramos / 100
        stock[it.nombre] -= gramos

    # --- Fase 1: proteína, mayor densidad proteica primero ---
    proteicos = sorted(
        (it for it in disponibles if es_proteico(it)),
        key=lambda it: it.proteina_100g / max(it.kcal_100g, 1),
        reverse=True,
    )
    prot_restante = meta.proteina_g - prot_acum
    for it in proteicos:
        if prot_restante <= 0.5:
            break
        tope = min(stock.get(it.nombre, 0), MAX_PORCION_G)
        if tope < 1 or it.proteina_100g <= 0:
            continue
        gramos_necesarios = (prot_restante / it.proteina_100g) * 100
        gramos = round(min(gramos_necesarios, tope))
        if gramos < 1:
            continue
        porciones[it.nombre] = porciones.get(it.nombre, 0) + gramos
        kcal_acum += it.kcal_100g * gramos / 100
        aportado = it.proteina_100g * gramos / 100
        prot_acum += aportado
        prot_restante -= aportado
        stock[it.nombre] -= gramos

    if prot_restante > 0.5:
        faltantes.append(
            f"Faltan ~{prot_restante:.0f} g de proteína para la meta de esta "
            f"comida — no hay suficiente fuente proteica en tu inventario."
        )

    # --- Fase 2: kcal restantes, comida real primero ---
    kcal_restante = meta.kcal - kcal_acum
    bases = sorted((it for it in disponibles if es_base_energetica(it)),
                   key=lambda it: it.kcal_100g, reverse=True)
    kcal_acum, prot_acum, kcal_restante = _llenar(
        porciones, stock, kcal_acum, prot_acum, kcal_restante,
        bases, MAX_KCAL_BASE_ITEM)

    # --- Fase 3: si aún falta, grasa concentrada, en poca cantidad ---
    if kcal_restante > 1:
        grasas = sorted((it for it in disponibles if es_grasa_concentrada(it)),
                        key=lambda it: it.kcal_100g, reverse=True)
        kcal_acum, prot_acum, kcal_restante = _llenar(
            porciones, stock, kcal_acum, prot_acum, kcal_restante,
            grasas, MAX_KCAL_GRASA_ITEM)

    if kcal_restante > 50:
        faltantes.append(
            f"Faltan ~{kcal_restante:.0f} kcal para la meta — no hay "
            f"suficiente comida base (arroz, papa, pan...) disponible."
        )

    # --- Extras manuales (café, té...) — no llenan macros, sí cuentan ---
    for nombre, gramos in (extras or {}).items():
        it = por_nombre.get(nombre)
        if not it or gramos <= 0:
            continue
        porciones[nombre] = porciones.get(nombre, 0) + gramos
        m = macros_de(it, gramos)
        kcal_acum += m["kcal"]
        prot_acum += m["proteina_g"]

    usados = [por_nombre[n] for n in porciones if n in por_nombre]
    advertencias = revisar_interacciones(usados, orden_comida=meta.orden)

    return ResultadoCombinacion(
        porciones=porciones,
        kcal=kcal_acum,
        proteina_g=prot_acum,
        meta_kcal=meta.kcal,
        meta_proteina_g=meta.proteina_g,
        advertencias_interaccion=advertencias,
        faltantes=faltantes,
    )


def macros_de(item: ItemInventario, gramos: float) -> dict:
    f = gramos / 100.0
    return {"kcal": item.kcal_100g * f, "proteina_g": item.proteina_100g * f}


# ---------------------------------------------------------------------------
# Advertencias de interacción — ahora leen etiquetas de ItemInventario,
# no de un diccionario global. Sigue siendo ADVERTENCIA, nunca bloqueo.
# ---------------------------------------------------------------------------

def _tags(items: Iterable[ItemInventario]) -> set:
    tags = set()
    for it in items:
        tags |= set(it.etiquetas)
        tags.add(it.nombre)
    return tags


def revisar_interacciones(items_comida: Iterable[ItemInventario],
                          orden_comida: int = None,
                          items_recientes: Iterable[ItemInventario] = (),
                          minutos_desde_reciente: int = 999) -> list:
    advertencias = []
    tags_ahora = _tags(items_comida)
    tags_antes = _tags(items_recientes)

    for regla in config.REGLAS_INTERACCION:
        solo = regla.get("solo_comidas")
        if solo and orden_comida not in solo:
            continue

        grupo_a = regla["grupo_a"]
        grupo_b = regla["grupo_b"]

        if not grupo_b:
            if tags_ahora & grupo_a:
                advertencias.append(Advertencia(
                    regla_id=regla["id"], mensaje=regla["mensaje"],
                    severidad=regla["severidad"],
                ))
            continue

        choque_mismo = bool(tags_ahora & grupo_a) and bool(tags_ahora & grupo_b)
        dentro_ventana = minutos_desde_reciente <= regla["ventana_min"]
        choque_previo = dentro_ventana and (
            (bool(tags_ahora & grupo_a) and bool(tags_antes & grupo_b)) or
            (bool(tags_ahora & grupo_b) and bool(tags_antes & grupo_a))
        )

        if choque_mismo or choque_previo:
            advertencias.append(Advertencia(
                regla_id=regla["id"], mensaje=regla["mensaje"],
                severidad=regla["severidad"],
            ))

    return advertencias


# ---------------------------------------------------------------------------
# Interacciones calculadas con nutrientes reales
# ---------------------------------------------------------------------------
# Las reglas de config.REGLAS_INTERACCION funcionan por etiqueta: disparan
# si aparece "legumbres" junto a "cafe". Eso no distingue 20 g de lenteja
# de 300 g, ni sabe que el brócoli al lado cambia el resultado.
#
# Con nutrientes numéricos las mismas interacciones se calculan por
# cantidad, y aparece algo que las etiquetas no podían ver: las
# combinaciones que MEJORAN la absorción, no solo las que la estorban.

@dataclass(frozen=True)
class ItemNutrido:
    """Alimento con perfil nutricional completo. main.py lo arma desde Alimento."""
    nombre: str
    gramos: float
    nutrientes: dict          # {'hierro_mg': 3.3, 'vitc_mg': 89, ...} por los gramos dados
    hierro_es_hemo: bool = False
    inhibe_hierro_no_hemo: bool = False   # campo propio, no inferido de etiquetas
    etiquetas: frozenset = frozenset()


@dataclass
class Sinergia:
    """Una interacción positiva — algo que esta combinación hace BIEN."""
    id: str
    mensaje: str
    magnitud: str    # 'alta' | 'media'


# Umbrales. Son puntos de corte prácticos para decidir si vale la pena
# mencionar algo, no valores clínicos: por debajo de esto el efecto existe
# pero es demasiado pequeño para que cambie una decisión.
MIN_HIERRO_RELEVANTE_MG = 1.5
MIN_VITC_SINERGIA_MG = 25.0
MIN_CALCIO_INHIBIDOR_MG = 250.0
MIN_ZINC_RELEVANTE_MG = 2.0


def _suma(items, clave: str) -> float:
    return sum(it.nutrientes.get(clave, 0.0) for it in items)


def perfil_nutricional(items: list) -> dict:
    """Suma de todos los nutrientes de una comida."""
    total = {}
    for it in items:
        for k, v in it.nutrientes.items():
            total[k] = total.get(k, 0.0) + v
    return total


def hierro_no_hemo(items: list) -> float:
    return sum(it.nutrientes.get("hierro_mg", 0.0)
               for it in items if not it.hierro_es_hemo)


def analizar_sinergias(items: list) -> list:
    """
    Combinaciones que mejoran la absorción. Esto es lo que las etiquetas
    no podían detectar.

    La principal: vitamina C con hierro no-hemo. El ácido ascórbico reduce
    el hierro férrico a ferroso y forma un quelato soluble, lo que aumenta
    su absorción de forma sustancial — y además contrarresta parcialmente
    a los polifenoles. Solo aplica al hierro vegetal: el hemo (carne,
    pescado) ya se absorbe bien y apenas lo afectan estos factores.
    """
    sinergias = []
    fe_no_hemo = hierro_no_hemo(items)
    vitc = _suma(items, "vitc_mg")

    if fe_no_hemo >= MIN_HIERRO_RELEVANTE_MG and vitc >= MIN_VITC_SINERGIA_MG:
        fuentes_c = [it.nombre for it in items
                     if it.nutrientes.get("vitc_mg", 0) >= 10]
        magnitud = "alta" if vitc >= 50 else "media"
        sinergias.append(Sinergia(
            id="vitc_potencia_hierro",
            mensaje=(f"Buena combinación: {vitc:.0f} mg de vitamina C "
                     f"({', '.join(fuentes_c)}) con {fe_no_hemo:.1f} mg de "
                     f"hierro vegetal. La vitamina C aumenta bastante su "
                     f"absorción."),
            magnitud=magnitud,
        ))

    # Hemo + no-hemo juntos: la carne mejora la absorción del hierro vegetal.
    hay_hemo = any(it.hierro_es_hemo and it.nutrientes.get("hierro_mg", 0) > 0.5
                   for it in items)
    if hay_hemo and fe_no_hemo >= MIN_HIERRO_RELEVANTE_MG:
        sinergias.append(Sinergia(
            id="hemo_potencia_no_hemo",
            mensaje=("Tener carne o pescado en el mismo plato mejora la "
                     "absorción del hierro vegetal que lo acompaña."),
            magnitud="media",
        ))

    return sinergias


def analizar_inhibiciones(items: list) -> list:
    """
    Interferencias calculadas por cantidad, no por presencia de etiqueta.
    Devuelve objetos Advertencia, igual que revisar_interacciones(), para
    que la interfaz los trate igual.
    """
    avisos = []
    fe_no_hemo = hierro_no_hemo(items)
    calcio = _suma(items, "calcio_mg")
    zinc = _suma(items, "zinc_mg")
    vitc = _suma(items, "vitc_mg")

    # El campo explícito manda; la etiqueta queda solo como respaldo para
    # alimentos viejos creados antes de que existiera el campo.
    hay_polifenoles = any(
        it.inhibe_hierro_no_hemo or "polifenoles" in it.etiquetas
        for it in items
    )

    # Polifenoles (café, té, jamaica) + hierro vegetal, ponderado por si
    # hay vitamina C que compense.
    if hay_polifenoles and fe_no_hemo >= MIN_HIERRO_RELEVANTE_MG:
        if vitc >= MIN_VITC_SINERGIA_MG:
            avisos.append(Advertencia(
                regla_id="polifenoles_hierro_compensado",
                mensaje=(f"Los polifenoles reducen la absorción de los "
                         f"{fe_no_hemo:.1f} mg de hierro vegetal, pero los "
                         f"{vitc:.0f} mg de vitamina C lo compensan en parte."),
                severidad="baja",
            ))
        else:
            avisos.append(Advertencia(
                regla_id="polifenoles_hierro",
                mensaje=(f"Polifenoles junto a {fe_no_hemo:.1f} mg de hierro "
                         f"vegetal reducen su absorción. Separarlos ~1 h, o "
                         f"añadir algo con vitamina C."),
                severidad="media",
            ))

    # Calcio alto compite con hierro y zinc por los mismos transportadores.
    if calcio >= MIN_CALCIO_INHIBIDOR_MG and fe_no_hemo >= MIN_HIERRO_RELEVANTE_MG:
        avisos.append(Advertencia(
            regla_id="calcio_hierro",
            mensaje=(f"{calcio:.0f} mg de calcio en la misma comida que "
                     f"{fe_no_hemo:.1f} mg de hierro vegetal — compiten por "
                     f"absorberse. Es un efecto moderado, no un problema grave."),
            severidad="baja",
        ))

    if calcio >= MIN_CALCIO_INHIBIDOR_MG and zinc >= MIN_ZINC_RELEVANTE_MG:
        avisos.append(Advertencia(
            regla_id="calcio_zinc",
            mensaje=(f"Calcio alto ({calcio:.0f} mg) junto a {zinc:.1f} mg de "
                     f"zinc reduce algo su absorción."),
            severidad="baja",
        ))

    return avisos


@dataclass
class AnalisisComida:
    perfil: dict
    sinergias: list
    inhibiciones: list
    datos_incompletos: list   # nutrientes que faltaban en algún alimento

    @property
    def tiene_algo_que_decir(self) -> bool:
        return bool(self.sinergias or self.inhibiciones)


def analizar_comida(items: list) -> AnalisisComida:
    """
    Análisis completo: qué aporta, qué se potencia, qué se estorba.

    `datos_incompletos` existe para no mentir por omisión: si un alimento
    no tiene dato de hierro, el total de hierro es un piso, no la cifra
    real. Mejor decirlo que presentar una suma parcial como si fuera exacta.
    """
    perfil = perfil_nutricional(items)

    faltantes = []
    for clave in ("hierro_mg", "calcio_mg", "vitc_mg", "zinc_mg", "b12_mcg"):
        sin_dato = [it.nombre for it in items if clave not in it.nutrientes]
        if sin_dato:
            faltantes.append(f"{clave}: sin dato en {', '.join(sin_dato)}")

    return AnalisisComida(
        perfil=perfil,
        sinergias=analizar_sinergias(items),
        inhibiciones=analizar_inhibiciones(items),
        datos_incompletos=faltantes,
    )


# ---------------------------------------------------------------------------
# Biodisponibilidad del hierro — estimación con rango, no cifra exacta
# ---------------------------------------------------------------------------
# Sumar miligramos de hierro no dice cuánto absorbes: el hemo se absorbe
# varias veces mejor que el vegetal, y el vegetal cambia mucho según qué
# lo acompañe. Por eso "ingerido" y "absorbido" se reportan por separado.
#
# ADVERTENCIA DE PRECISIÓN: esto es una estimación gruesa. La absorción
# real depende de tus reservas de hierro (el cuerpo absorbe más cuando
# están bajas), fitatos, genética y más. Por eso devuelve un RANGO amplio
# y nunca un número único — un valor exacto aquí sería precisión falsa.

# Fracciones de absorción típicas, como rango (mínimo, máximo).
ABS_HEMO = (0.15, 0.35)
ABS_NO_HEMO_BASE = (0.05, 0.12)

# Multiplicadores. La vitamina C reduce el hierro férrico a ferroso y forma
# un quelato soluble; los polifenoles hacen lo contrario, complejan el
# hierro y lo vuelven no absorbible.
MULT_VITC_ALTA = 2.0     # >= 75 mg
MULT_VITC_MEDIA = 1.5    # >= 25 mg
MULT_POLIFENOLES = 0.5
MULT_CALCIO_ALTO = 0.8


@dataclass
class EstimacionHierro:
    ingerido_mg: float
    ingerido_hemo_mg: float
    ingerido_no_hemo_mg: float
    absorbido_min_mg: float
    absorbido_max_mg: float
    factores: list          # qué modificó la estimación, en texto

    @property
    def rango_texto(self) -> str:
        return f"{self.absorbido_min_mg:.1f}–{self.absorbido_max_mg:.1f} mg"

    @property
    def nota_incertidumbre(self) -> str:
        return ("Estimación dependiente de la comida; no equivale a una "
                "medición clínica. La absorción real también depende de tus "
                "reservas de hierro y de factores que la app no mide.")


def estimar_hierro_absorbido(items: list) -> EstimacionHierro:
    """
    Separa el hierro que comes del que probablemente absorbes.

    Ejemplo de por qué importa: 9 mg de hierro de lentejas con café
    absorbe menos que 3 mg de hierro de carne. El número grande no gana.
    """
    hemo = sum(it.nutrientes.get("hierro_mg", 0.0)
               for it in items if it.hierro_es_hemo)
    no_hemo = hierro_no_hemo(items)
    vitc = _suma(items, "vitc_mg")
    calcio = _suma(items, "calcio_mg")
    hay_inhibidor = any(it.inhibe_hierro_no_hemo or "polifenoles" in it.etiquetas
                        for it in items)

    factores = []
    mult_vitc = 1.0

    if vitc >= 75:
        mult_vitc = MULT_VITC_ALTA
    elif vitc >= MIN_VITC_SINERGIA_MG:
        mult_vitc = MULT_VITC_MEDIA

    hay_inhibidor_activo = hay_inhibidor

    # Cuando coexisten, la vitamina C mitiga la inhibición pero no la borra:
    # parte del hierro ya quedó complejado con los polifenoles antes de que
    # el ascorbato pueda actuar. Aplicar 2.0 × 0.5 = 1.0 daría a entender
    # que se cancelan exacto, y eso no está establecido — el neto queda por
    # debajo de una comida sin inhibidor.
    if hay_inhibidor_activo and mult_vitc > 1.0:
        EFICACIA_VITC_CON_INHIBIDOR = 0.6
        mult_vitc = 1.0 + (mult_vitc - 1.0) * EFICACIA_VITC_CON_INHIBIDOR
        factores.append(f"{vitc:.0f} mg de vitamina C compensan en parte la "
                        f"inhibición, aunque no del todo")
    elif mult_vitc >= MULT_VITC_ALTA:
        factores.append(f"{vitc:.0f} mg de vitamina C mejoran bastante la absorción")
    elif mult_vitc > 1.0:
        factores.append(f"{vitc:.0f} mg de vitamina C ayudan algo")

    mult = mult_vitc
    if hay_inhibidor_activo:
        mult *= MULT_POLIFENOLES
        factores.append("polifenoles (café, té o jamaica) reducen la absorción")

    if calcio >= MIN_CALCIO_INHIBIDOR_MG:
        mult *= MULT_CALCIO_ALTO
        factores.append(f"{calcio:.0f} mg de calcio compiten por absorberse")

    # Techo fisiológico: incluso en las mejores condiciones la absorción de
    # hierro no-hemo no supera ~25% en una comida.
    TECHO_NO_HEMO = 0.25
    abs_min = hemo * ABS_HEMO[0] + no_hemo * min(ABS_NO_HEMO_BASE[0] * mult, TECHO_NO_HEMO)
    abs_max = hemo * ABS_HEMO[1] + no_hemo * min(ABS_NO_HEMO_BASE[1] * mult, TECHO_NO_HEMO)

    return EstimacionHierro(
        ingerido_mg=round(hemo + no_hemo, 2),
        ingerido_hemo_mg=round(hemo, 2),
        ingerido_no_hemo_mg=round(no_hemo, 2),
        absorbido_min_mg=round(abs_min, 1),
        absorbido_max_mg=round(abs_max, 1),
        factores=factores,
    )
