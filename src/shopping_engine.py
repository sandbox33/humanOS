"""
HumanOS — Motor de compras.

PURO: no importa `database` ni `flet`.

Tres fuentes para la lista, en orden de prioridad:

  1. AGOTADO      — lo que se acabó o está por acabarse, y sueles comprar
  2. FALTANTE     — lo que necesitas para cerrar la brecha de proteína/kcal
  3. SUGERENCIA   — buena relación nutriente/precio que aún no compras

El "sueles comprar" no lo declaras: sale del historial de Compra. Un
alimento comprado 5 veces en 3 meses es habitual; uno comprado una vez, no.
"""

import datetime as dt
from dataclasses import dataclass, field

PRIORIDAD_AGOTADO = 1
PRIORIDAD_FALTANTE = 2
PRIORIDAD_SUGERENCIA = 3

# Días de consumo por debajo de los cuales algo cuenta como "por acabarse".
DIAS_RESERVA = 3

# Compras mínimas en la ventana para considerar un alimento "habitual".
MIN_COMPRAS_HABITUAL = 2


# ---------------------------------------------------------------------------
# DTOs
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class ItemCompra:
    """Alimento con lo necesario para decidir si entra en la lista."""
    nombre: str
    categoria: str
    unidad_compra: str
    kcal_100g: float
    proteina_100g: float
    gramos_disponibles: float = 0.0
    precio_por_100g: float = None     # del historial; None = desconocido
    compras_en_ventana: int = 0
    ultima_compra: dt.date = None
    gramos_por_unidad: float = None

    @property
    def es_habitual(self) -> bool:
        return self.compras_en_ventana >= MIN_COMPRAS_HABITUAL

    @property
    def costo_por_10g_proteina(self):
        """Métrica de eficiencia: cuánto cuesta la proteína, no el alimento."""
        if self.precio_por_100g is None or self.proteina_100g <= 0:
            return None
        return round(self.precio_por_100g / self.proteina_100g * 10, 4)

    @property
    def costo_paquete(self):
        """Lo que pagas de una sola vez — no lo mismo que el costo unitario."""
        if self.precio_por_100g is None or not self.gramos_por_unidad:
            return None
        return round(self.precio_por_100g * self.gramos_por_unidad / 100, 2)

    def resumen_precio(self) -> str:
        """
        Contexto completo, para que el ranking no engañe. Algo puede salir
        baratísimo por gramo de proteína y aun así ser mala compra: si el
        paquete mínimo es de 5 kg y no tienes dónde guardarlo, el precio
        unitario no sirve de nada.
        """
        if self.precio_por_100g is None:
            return "sin precio registrado"
        partes = [f"{self.precio_por_100g:.2f}/100 g"]
        if self.costo_por_10g_proteina is not None:
            partes.append(f"{self.costo_por_10g_proteina:.2f} por 10 g proteína")
        if self.costo_paquete is not None:
            partes.append(f"paquete ~{self.costo_paquete:.2f} "
                          f"({self.gramos_por_unidad:.0f} g)")
        return " · ".join(partes)


@dataclass
class LineaLista:
    nombre: str
    categoria: str
    prioridad: int
    motivo: str
    gramos_sugeridos: float = None
    unidad: str = "g"
    precio_estimado: float = None

    @property
    def cantidad_texto(self) -> str:
        if self.gramos_sugeridos is None:
            return ""
        if self.unidad in ("unidad", "lata", "paquete"):
            return f"{self.gramos_sugeridos:.0f} g"
        if self.gramos_sugeridos >= 1000:
            return f"{self.gramos_sugeridos/1000:.1f} kg"
        return f"{self.gramos_sugeridos:.0f} g"


@dataclass
class ListaCompras:
    lineas: list = field(default_factory=list)
    total_estimado: float = None
    nota: str = ""

    def por_categoria(self) -> dict:
        """Agrupado para recorrer la tienda por secciones, no saltando."""
        grupos = {}
        for l in self.lineas:
            grupos.setdefault(l.categoria, []).append(l)
        for lineas in grupos.values():
            lineas.sort(key=lambda l: l.prioridad)
        return grupos


# ---------------------------------------------------------------------------
# Historial → hábitos de compra
# ---------------------------------------------------------------------------

def resumen_compras(compras: list, dias: int = 90) -> dict:
    """
    compras: lista de dicts {'nombre', 'fecha', 'gramos', 'precio'}
    Devuelve {nombre: {'veces', 'gramos_promedio', 'precio_por_100g', 'ultima'}}
    """
    corte = dt.date.today() - dt.timedelta(days=dias)
    agrupado = {}

    for c in compras:
        if c["fecha"] < corte:
            continue
        d = agrupado.setdefault(c["nombre"], {
            "veces": 0, "gramos_total": 0.0,
            "precios": [], "ultima": None,
        })
        d["veces"] += 1
        d["gramos_total"] += c.get("gramos", 0) or 0
        if c.get("precio") is not None and c.get("gramos"):
            d["precios"].append(c["precio"] / c["gramos"] * 100)
        if d["ultima"] is None or c["fecha"] > d["ultima"]:
            d["ultima"] = c["fecha"]

    salida = {}
    for nombre, d in agrupado.items():
        precios = d["precios"]
        salida[nombre] = {
            "veces": d["veces"],
            "gramos_promedio": round(d["gramos_total"] / d["veces"], 1) if d["veces"] else 0,
            "precio_por_100g": round(sum(precios) / len(precios), 4) if precios else None,
            "ultima": d["ultima"],
        }
    return salida


def ranking_proteina_barata(items: list, top: int = 5) -> list:
    """Ordena por costo real de la proteína. Sin precio no entra al ranking."""
    con_precio = [it for it in items if it.costo_por_10g_proteina is not None]
    return sorted(con_precio, key=lambda it: it.costo_por_10g_proteina)[:top]


# ---------------------------------------------------------------------------
# Construcción de la lista
# ---------------------------------------------------------------------------

def _dias_de_reserva(item: ItemCompra, consumo_diario_g: dict) -> float:
    consumo = consumo_diario_g.get(item.nombre, 0)
    if consumo <= 0:
        return float("inf")
    return item.gramos_disponibles / consumo


def construir_lista(items: list,
                    consumo_diario_g: dict = None,
                    brecha_proteina_g: float = 0.0,
                    brecha_kcal: float = 0.0,
                    incluir_sugerencias: bool = True) -> ListaCompras:
    """
    items: todos los alimentos del catálogo, con inventario e historial.
    consumo_diario_g: {nombre: gramos/día} estimado del consumo real.
    brecha_proteina_g / brecha_kcal: lo que falta cubrir en un día típico.
    """
    consumo_diario_g = consumo_diario_g or {}
    lineas = []
    ya_incluido = set()

    # --- 1. Agotado o por acabarse, entre lo que sueles comprar ---
    for it in items:
        if not it.es_habitual:
            continue
        dias = _dias_de_reserva(it, consumo_diario_g)
        if it.gramos_disponibles <= 0:
            motivo = "Se acabó"
        elif dias <= DIAS_RESERVA:
            motivo = f"Quedan ~{dias:.0f} día(s)"
        else:
            continue

        historico = consumo_diario_g.get(it.nombre, 0) * 7
        sugerido = max(historico, it.gramos_por_unidad or 0) or None
        lineas.append(LineaLista(
            nombre=it.nombre, categoria=it.categoria,
            prioridad=PRIORIDAD_AGOTADO, motivo=motivo,
            gramos_sugeridos=sugerido, unidad=it.unidad_compra,
            precio_estimado=(round(it.precio_por_100g * sugerido / 100, 2)
                             if it.precio_por_100g and sugerido else None),
        ))
        ya_incluido.add(it.nombre)

    # --- 2. Lo que falta para cerrar la brecha de metas ---
    if brecha_proteina_g > 0:
        candidatos = [it for it in items
                      if it.nombre not in ya_incluido and it.proteina_100g >= 10]
        # Con precio conocido, el más eficiente primero; sin precio, el más denso.
        candidatos.sort(key=lambda it: (it.costo_por_10g_proteina
                                        if it.costo_por_10g_proteina is not None
                                        else 9e9,
                                        -it.proteina_100g))
        for it in candidatos[:2]:
            gramos = round(brecha_proteina_g / it.proteina_100g * 100)
            lineas.append(LineaLista(
                nombre=it.nombre, categoria=it.categoria,
                prioridad=PRIORIDAD_FALTANTE,
                motivo=f"Cubre {brecha_proteina_g:.0f} g de proteína que faltan",
                gramos_sugeridos=gramos, unidad=it.unidad_compra,
                precio_estimado=(round(it.precio_por_100g * gramos / 100, 2)
                                 if it.precio_por_100g else None),
            ))
            ya_incluido.add(it.nombre)

    if brecha_kcal > 300:
        candidatos = [it for it in items
                      if it.nombre not in ya_incluido
                      and 80 <= it.kcal_100g < 600]
        candidatos.sort(key=lambda it: (it.precio_por_100g
                                        if it.precio_por_100g is not None else 9e9,
                                        -it.kcal_100g))
        for it in candidatos[:1]:
            gramos = round(brecha_kcal / it.kcal_100g * 100)
            lineas.append(LineaLista(
                nombre=it.nombre, categoria=it.categoria,
                prioridad=PRIORIDAD_FALTANTE,
                motivo=f"Cubre {brecha_kcal:.0f} kcal que faltan",
                gramos_sugeridos=gramos, unidad=it.unidad_compra,
                precio_estimado=(round(it.precio_por_100g * gramos / 100, 2)
                                 if it.precio_por_100g else None),
            ))
            ya_incluido.add(it.nombre)

    # --- 3. Sugerencias: barato y nutritivo, que aún no compras ---
    if incluir_sugerencias:
        nuevos = [it for it in items
                  if it.nombre not in ya_incluido
                  and not it.es_habitual
                  and it.proteina_100g >= 8]
        for it in ranking_proteina_barata(nuevos, top=2):
            lineas.append(LineaLista(
                nombre=it.nombre, categoria=it.categoria,
                prioridad=PRIORIDAD_SUGERENCIA,
                motivo=(f"No lo compras seguido — {it.resumen_precio()}"),
                gramos_sugeridos=it.gramos_por_unidad, unidad=it.unidad_compra,
            ))

    lineas.sort(key=lambda l: (l.prioridad, l.categoria, l.nombre))

    precios = [l.precio_estimado for l in lineas if l.precio_estimado is not None]
    total = round(sum(precios), 2) if precios else None
    sin_precio = len(lineas) - len(precios)
    nota = ("" if not sin_precio
            else f"Total parcial: {sin_precio} artículo(s) sin precio conocido.")

    return ListaCompras(lineas=lineas, total_estimado=total, nota=nota)
