"""
HumanOS — Pantalla de sueño.

RESPONSABILIDAD: ordenar y mostrar. deuda_de_sueño() y racha_actual()
(sleep_engine.py) ya resolvieron los números — esta vista solo pinta
DatosSueno, mismo criterio que el resto.

DOS BOTONES, NUNCA LOS DOS A LA VEZ: 'me voy a dormir' cuando no hay una
noche abierta, 'ya desperté' cuando sí la hay. Cuál mostrar lo decide
DatosSueno.durmiendo_ahora — presentador.py es quien sabe si existe un
SueñoLog con hora_dormir_real y sin hora_despertar_real; esta vista no
lo calcula, solo lee el booleano.
"""

import datetime as dt
from dataclasses import dataclass, field

import flet as ft

import theme as t


@dataclass
class FilaNoche:
    fecha: dt.date
    horas: float = None          # None = sin dato completo esa noche
    dentro_rango: bool = False    # 7.0-9.5 h


@dataclass
class DatosSueno:
    fecha: dt.date
    durmiendo_ahora: bool = False
    hora_dormir_registrada: str = ""      # "23:10", solo si durmiendo_ahora
    horas_ultima_noche: float = None       # última noche YA cerrada

    ventana_ideal: str = ""                # "22:40" o rango, ya formateado
    nota_ventana: str = ""

    deuda_h: float = 0.0
    noches_con_dato: int = 0
    noches_sin_dato: int = 0
    promedio_h: float = None
    racha: int = 0

    historial_7d: list = field(default_factory=list)   # FilaNoche × 7, viejo->nuevo


MESES = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]


def _fecha_corta(f: dt.date) -> str:
    return f"{f.day:02d} {MESES[f.month - 1]} {f.year}"


def _cabecera(d: DatosSueno) -> ft.Container:
    return ft.Container(
        content=ft.Column([
            t.etiqueta("sueño", color=t.BASE, size=t.CAPTION),
            t.texto(_fecha_corta(d.fecha), color=t.TENUE, size=t.MICRO),
        ], spacing=2, tight=True),
        padding=ft.padding.only(left=t.ESPACIO, right=t.ESPACIO, top=t.ESPACIO, bottom=4),
    )


def _bloque_boton(d: DatosSueno, on_dormir=None, on_despertar=None) -> ft.Container:
    if d.durmiendo_ahora:
        contenido = [
            t.etiqueta("durmiendo desde", color=t.TENUE),
            t.display(d.hora_dormir_registrada or "—"),
            t.boton("ya desperté", primario=True,
                   on_click=(lambda e: on_despertar()) if on_despertar else None),
        ]
    else:
        cifra = (f"{d.horas_ultima_noche:.1f} h anoche" if d.horas_ultima_noche is not None
                else "Sin registrar anoche")
        contenido = [
            t.texto(cifra, color=t.TENUE, size=t.CAPTION),
            t.boton("me voy a dormir", primario=True,
                   on_click=(lambda e: on_dormir()) if on_dormir else None),
        ]
    return t.panel(contenido, titulo="ahora")


def _bloque_ventana(d: DatosSueno):
    if not d.ventana_ideal:
        return None
    contenido = [t.texto(d.ventana_ideal, color=t.VIVO, size=t.VALOR)]
    if d.nota_ventana:
        contenido.append(t.texto(d.nota_ventana, color=t.APAGADO, size=t.MICRO, no_wrap=False))
    return t.panel(contenido, titulo="ventana para acostarte")


def _historial_barra(historial: list) -> ft.Row:
    celdas = []
    for f in historial:
        if f.horas is None:
            color = t.LINEA
        elif f.dentro_rango:
            color = t.VIVO
        else:
            color = t.AMBAR
        celdas.append(ft.Container(height=10, bgcolor=color, expand=True, border_radius=0))
    if not celdas:
        celdas = [ft.Container(height=10, bgcolor=t.LINEA, expand=True)]
    return ft.Row(celdas, spacing=2, height=10)


def _bloque_deuda(d: DatosSueno) -> ft.Container:
    color_deuda = t.ALARMA if d.deuda_h > 2 else (t.AMBAR if d.deuda_h > 0 else t.VIVO)
    detalle = f"{d.noches_con_dato} noche(s) con dato"
    if d.noches_sin_dato:
        detalle += f" · {d.noches_sin_dato} sin registrar"

    contenido = [
        ft.Row([
            t.etiqueta("deuda 7 días", color=t.TENUE),
            t.texto(f"{d.deuda_h:+.1f} h", color=color_deuda, size=t.VALOR,
                    weight=ft.FontWeight.W_600),
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
        ft.Row([
            t.texto(detalle, color=t.APAGADO, size=t.MICRO),
            t.texto(f"prom. {d.promedio_h:.1f} h" if d.promedio_h is not None else "",
                    color=t.APAGADO, size=t.MICRO),
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
        t.separador(),
        _historial_barra(d.historial_7d),
        ft.Row([
            t.etiqueta("racha 7–9.5 h", color=t.TENUE),
            t.valor(d.racha, "noches"),
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN, vertical_alignment=ft.CrossAxisAlignment.CENTER),
    ]
    return t.panel(contenido, titulo="esta semana")


def vista(d: DatosSueno, on_dormir=None, on_despertar=None) -> ft.Control:
    """
    on_dormir()      — botón 'me voy a dormir'
    on_despertar()   — botón 'ya desperté'
    """
    bloques = [_cabecera(d), _bloque_boton(d, on_dormir, on_despertar),
              _bloque_ventana(d), _bloque_deuda(d)]
    bloques = [b for b in bloques if b is not None]

    columna = ft.Column(controls=bloques, spacing=t.ESPACIO, scroll=ft.ScrollMode.AUTO, expand=True)
    return ft.Container(content=columna, bgcolor=t.VOID, expand=True,
                        padding=ft.padding.only(left=t.ESPACIO, right=t.ESPACIO,
                                                bottom=t.ESPACIO * 2))
