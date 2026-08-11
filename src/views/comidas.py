"""
HumanOS — Pantalla de comidas.

RESPONSABILIDAD: ordenar y mostrar, igual que views/hoy.py. No calcula
combinaciones, macros ni interacciones — todo eso ya viene resuelto en
DatosComidas. Los gramos que el usuario ajusta con el stepper son un
valor que se PIDE mediante on_cambiar_gramos; quien decide cuánto
inventario hay disponible, recalcula kcal/proteína/advertencias y arma
el siguiente DatosComidas es presentador.py — no esta vista.

FORMA DE PANTALLA: las 5 comidas van apiladas. La comida identificada
por DatosComidas.orden se muestra expandida con su detalle completo
(ingredientes editables, extras, notas). Las otras 4 se muestran
colapsadas (DatosComidas.otras_comidas) como una fila compacta; tocarla
dispara on_expandir(orden) para que quien orquesta la pantalla (main.py)
pida un DatosComidas nuevo con esa otra comida como foco.

'EN VIVO': cada ajuste de gramos, cada extra agregado o quitado, dispara
su callback — se asume que quien llama a vista() va a pedir un
DatosComidas fresco y volver a renderizar. Esta vista nunca guarda su
propio estado de macros, solo refleja lo que le dan.

Si DatosComidas.ya_confirmada es True, no se muestran controles de
edición: se lista lo que de verdad se comió, en solo lectura — mismo
criterio que el 'detalle' de FilaComida en views/hoy.py.
"""

import datetime as dt
from dataclasses import dataclass, field

import flet as ft

import theme as t


# ---------------------------------------------------------------------------
# Lo que la vista necesita
# ---------------------------------------------------------------------------

@dataclass
class FilaIngrediente:
    nombre: str
    gramos: float
    kcal: float
    proteina_g: float
    gramos_disponibles: float = 0.0   # tope real del inventario para el stepper
    es_extra: bool = False            # True = agregado a mano, no vino de la sugerencia


@dataclass
class ExtraDisponible:
    """Algo que se puede agregar como extra. presentador.py ya excluye lo
    que está en ingredientes/extras — no hace falta filtrarlo aquí."""
    nombre: str
    categoria: str = "otro"
    gramos_sugeridos: float = 100.0


@dataclass
class ResumenComida:
    """Fila colapsada de una de las otras 4 comidas — liviana a propósito."""
    orden: int
    nombre: str
    hora: str
    estado: str = "pendiente"        # 'ok' | 'aviso' | 'limite' | 'pendiente'


@dataclass
class DatosComidas:
    fecha: dt.date
    orden: int                       # cuál de las 5 está expandida
    nombre: str = ""
    hora: str = ""
    estado: str = "pendiente"
    ya_confirmada: bool = False

    meta_kcal: float = 0.0
    meta_prot: float = 0.0
    kcal_total: float = 0.0
    prot_total: float = 0.0

    ingredientes: list = field(default_factory=list)     # FilaIngrediente
    extras: list = field(default_factory=list)            # FilaIngrediente, es_extra=True
    catalogo_extras: list = field(default_factory=list)    # ExtraDisponible
    faltantes: list = field(default_factory=list)          # str

    sinergias: list = field(default_factory=list)          # [(mensaje, magnitud)]
    advertencias: list = field(default_factory=list)       # [(mensaje, severidad)]
    notas_clinicas: list = field(default_factory=list)     # [str]

    otras_comidas: list = field(default_factory=list)      # ResumenComida × 4


MESES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]


def _fecha_corta(f: dt.date) -> str:
    return f"{f.day:02d} {MESES[f.month - 1]} {f.year}"


PASO_GRAMOS = 10.0

_BORDE_POR_ESTADO = {
    "ok": t.LINEA, "pendiente": t.LINEA,
    "aviso": t.AMBAR_TENUE, "limite": t.ALARMA_TENUE,
}

_AVISO_VENTANA = {
    "aviso": "Dentro de la ventana de gracia — confírmala pronto.",
    "limite": "Se pasó la ventana de gracia.",
}


# ---------------------------------------------------------------------------
# Cabecera de pantalla
# ---------------------------------------------------------------------------

def _cabecera(d: DatosComidas) -> ft.Container:
    return ft.Container(
        content=ft.Column([
            t.etiqueta("comidas", color=t.BASE, size=t.CAPTION),
            t.texto(_fecha_corta(d.fecha), color=t.TENUE, size=t.MICRO),
        ], spacing=2, tight=True),
        padding=ft.padding.only(left=t.ESPACIO, right=t.ESPACIO, top=t.ESPACIO, bottom=4),
    )


# ---------------------------------------------------------------------------
# Filas colapsadas — las otras 4 comidas
# ---------------------------------------------------------------------------

def _fila_colapsada(r: ResumenComida, on_expandir=None) -> ft.Container:
    fila = ft.Row([
        t.estado(r.estado),
        ft.Row([
            t.texto(r.hora, color=t.TENUE, size=t.CAPTION),
            t.texto(r.nombre, color=t.BASE if r.estado != "pendiente" else t.TENUE),
        ], spacing=10),
        ft.Container(expand=True),
        t.texto("▸", color=t.APAGADO, size=t.CAPTION),
    ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER)

    return ft.Container(
        content=fila,
        padding=ft.padding.symmetric(horizontal=t.ESPACIO, vertical=10),
        border=ft.border.all(t.BORDE, _BORDE_POR_ESTADO.get(r.estado, t.LINEA)),
        border_radius=t.RADIO,
        bgcolor=t.PANEL,
        on_click=(lambda e: on_expandir(r.orden)) if on_expandir else None,
        ink=False,
    )


# ---------------------------------------------------------------------------
# Ingredientes y extras — filas editables con stepper
# ---------------------------------------------------------------------------

def _boton_gramos(simbolo: str, delta: float, item: FilaIngrediente, orden: int,
                  on_cambiar_gramos) -> ft.Container:
    if not on_cambiar_gramos:
        return t.boton(simbolo, ancho=34)
    nuevo = max(0.0, min(item.gramos_disponibles, item.gramos + delta))
    return t.boton(simbolo, on_click=lambda e: on_cambiar_gramos(orden, item.nombre, nuevo),
                   ancho=34)


def _fila_ingrediente(item: FilaIngrediente, orden: int,
                      on_cambiar_gramos=None, on_quitar=None) -> ft.Row:
    quitar = ft.Container(
        content=t.texto("✕", color=t.APAGADO, size=t.CAPTION),
        on_click=(lambda e: on_quitar(orden, item.nombre)) if on_quitar else None,
        padding=8, ink=False,
    )
    return ft.Row([
        ft.Row([
            _boton_gramos("−", -PASO_GRAMOS, item, orden, on_cambiar_gramos),
            t.texto(f"{item.gramos:.0f} g", color=t.BASE, size=t.CAPTION),
            _boton_gramos("+", PASO_GRAMOS, item, orden, on_cambiar_gramos),
        ], spacing=6, tight=True),
        ft.Column([
            t.texto(item.nombre.replace("_", " "), color=t.BASE),
            t.texto(f"{item.kcal:.0f} kcal · {item.proteina_g:.0f} g",
                    color=t.APAGADO, size=t.MICRO),
        ], spacing=1, tight=True, expand=True),
        quitar,
    ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER)


def _chip_extra(extra: ExtraDisponible, orden: int, on_agregar_extra=None) -> ft.Container:
    chip = t.chip(extra.nombre.replace("_", " "))
    if on_agregar_extra:
        chip.on_click = lambda e: on_agregar_extra(orden, extra.nombre, extra.gramos_sugeridos)
        chip.ink = False
    return chip


def _bloque_catalogo(catalogo: list, orden: int, on_agregar_extra=None) -> ft.Column:
    grupos = {}
    for e in catalogo:
        grupos.setdefault(e.categoria, []).append(e)

    columnas = []
    for categoria in sorted(grupos):
        chips = [_chip_extra(e, orden, on_agregar_extra) for e in grupos[categoria]]
        columnas.append(ft.Column([
            t.etiqueta(categoria, color=t.APAGADO, size=t.MICRO),
            ft.Row(chips, spacing=6, wrap=True),
        ], spacing=4, tight=True))
    return ft.Column(columnas, spacing=8, tight=True)


# ---------------------------------------------------------------------------
# Notas — mismo patrón que views/hoy.py
# ---------------------------------------------------------------------------

def _bloque_notas(d: DatosComidas):
    bloques = []
    for mensaje, _magnitud in d.sinergias:
        bloques.append(t.aviso(mensaje, "sinergia"))
    for mensaje, severidad in d.advertencias:
        bloques.append(t.aviso(mensaje, severidad))
    for mensaje in d.notas_clinicas:
        bloques.append(t.aviso_clinico(mensaje))
    if not bloques:
        return None
    return ft.Column(bloques, spacing=8, tight=True)


# ---------------------------------------------------------------------------
# Bloque expandido — la comida activa, completa
# ---------------------------------------------------------------------------

def _bloque_expandido(d: DatosComidas, on_cambiar_gramos=None, on_agregar_extra=None,
                      on_quitar=None, on_confirmar=None) -> ft.Container:
    contenido = [
        ft.Row([t.estado(d.estado), t.texto(d.hora, color=t.TENUE, size=t.CAPTION)],
              spacing=10),
    ]

    if d.estado in _AVISO_VENTANA and not d.ya_confirmada:
        color = t.AMBAR if d.estado == "aviso" else t.ALARMA
        contenido.append(t.texto(_AVISO_VENTANA[d.estado], color=color, size=t.MICRO))

    contenido.append(t.barra_etiquetada("kcal", round(d.kcal_total), d.meta_kcal, " kcal"))
    contenido.append(t.barra_etiquetada("proteína", round(d.prot_total), d.meta_prot, " g"))
    contenido.append(t.separador())

    if d.ya_confirmada:
        contenido.append(t.etiqueta("consumido", color=t.APAGADO))
        if not d.ingredientes:
            contenido.append(t.texto("Sin detalle registrado.", color=t.APAGADO, size=t.CAPTION))
        for it in d.ingredientes:
            contenido.append(ft.Row([
                t.texto(it.nombre.replace("_", " "), color=t.BASE, expand=True),
                t.texto(f"{it.gramos:.0f} g", color=t.TENUE, size=t.CAPTION),
            ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN))
    else:
        contenido.append(t.etiqueta("ingredientes", color=t.APAGADO))
        if not d.ingredientes:
            contenido.append(t.texto("Sin combinación sugerida — revisa el inventario.",
                                     color=t.APAGADO, size=t.CAPTION))
        for it in d.ingredientes:
            contenido.append(_fila_ingrediente(it, d.orden, on_cambiar_gramos, on_quitar))

        for msg in d.faltantes:
            contenido.append(t.aviso(msg, "media"))

        if d.extras:
            contenido.append(t.separador())
            contenido.append(t.etiqueta("extras", color=t.APAGADO))
            for it in d.extras:
                contenido.append(_fila_ingrediente(it, d.orden, on_cambiar_gramos, on_quitar))

        if d.catalogo_extras:
            contenido.append(t.separador())
            contenido.append(t.etiqueta("agregar", color=t.APAGADO))
            contenido.append(_bloque_catalogo(d.catalogo_extras, d.orden, on_agregar_extra))

    notas = _bloque_notas(d)
    if notas:
        contenido.append(t.separador())
        contenido.append(notas)

    if not d.ya_confirmada:
        contenido.append(ft.Container(
            content=t.boton("confirmar comida",
                            on_click=(lambda e: on_confirmar(d.orden)) if on_confirmar else None,
                            primario=True),
            padding=ft.padding.only(top=6),
        ))

    return t.panel(contenido, titulo=d.nombre or "comida",
                   color_borde=_BORDE_POR_ESTADO.get(d.estado, t.LINEA))


# ---------------------------------------------------------------------------
# Vista
# ---------------------------------------------------------------------------

def vista(d: DatosComidas, on_expandir=None, on_cambiar_gramos=None,
          on_agregar_extra=None, on_quitar=None, on_confirmar=None) -> ft.Control:
    """
    Callbacks, todos opcionales — sin ellos la vista se renderiza igual,
    útil para probarla aislada:
      on_expandir(orden)                          — tocar una fila colapsada
      on_cambiar_gramos(orden, nombre, gramos)     — stepper +/-
      on_agregar_extra(orden, nombre, gramos)      — tocar un chip de 'agregar'
      on_quitar(orden, nombre)                     — el '✕' de una fila
      on_confirmar(orden)                          — botón 'confirmar comida'
    """
    resumenes_por_orden = {r.orden: r for r in d.otras_comidas}
    ordenes = sorted(set(resumenes_por_orden) | {d.orden})

    filas = [_cabecera(d)]
    for orden in ordenes:
        if orden == d.orden:
            filas.append(_bloque_expandido(d, on_cambiar_gramos, on_agregar_extra,
                                           on_quitar, on_confirmar))
        else:
            filas.append(_fila_colapsada(resumenes_por_orden[orden], on_expandir))

    columna = ft.Column(controls=filas, spacing=t.ESPACIO, scroll=ft.ScrollMode.AUTO, expand=True)
    return ft.Container(content=columna, bgcolor=t.VOID, expand=True,
                        padding=ft.padding.only(left=t.ESPACIO, right=t.ESPACIO,
                                                bottom=t.ESPACIO * 2))
