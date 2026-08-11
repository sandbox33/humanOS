"""
HumanOS — Pantalla de hábitos.

RESPONSABILIDAD: ordenar y mostrar. Las tres rachas (individual, global,
mínima) ya vienen calculadas por habits_engine.py vía
presentador.datos_habitos() — esta vista no evalúa cumplimiento ni
rachas, solo las pinta, igual criterio que views/hoy.py.

'Marcar el día con valor real': el campo de valor es libre (no solo un
check) porque un hábito de 30 min de correr se registra con 35 min
reales, no con un booleano. Para hábitos binarios (metrica='check') el
valor es 1.0/0.0 y se pinta como estado, no como número.
"""

import datetime as dt
from dataclasses import dataclass, field

import flet as ft

import theme as t


# ---------------------------------------------------------------------------
# Lo que la vista necesita
# ---------------------------------------------------------------------------

@dataclass
class FilaHistorial:
    fecha: dt.date
    valor: float = None          # None = sin registro ese día
    completado: bool = False


@dataclass
class FilaHabitoDetalle:
    nombre: str
    tipo: str = "mantener"        # 'mantener' | 'moderar' — etiqueta semántica, no de cálculo
    metrica: str = "check"        # 'check' | 'contador' | 'duracion_min'
    tipo_objetivo: str = "binario"
    valor_objetivo: float = 1.0
    esencial: bool = False
    icono: str = None

    valor_hoy: float = None       # None = sin registrar
    completado_hoy: bool = False
    racha: int = 0
    historial_7d: list = field(default_factory=list)   # FilaHistorial × 7, más antiguo primero


@dataclass
class DatosHabitos:
    fecha: dt.date
    habitos: list = field(default_factory=list)          # FilaHabitoDetalle
    racha_global: int = 0
    racha_minima: int = 0
    puntaje_pct: float = 0.0
    sugerir_mision_minima: bool = False


CLAVES_ICONO = ("vicios", "masturbacion", "comida", "entrenamiento",
                "correr", "progreso", "concentracion", "trabajo", "fumar")


# ---------------------------------------------------------------------------
# Cabecera y resumen del día
# ---------------------------------------------------------------------------

def _cabecera(d: DatosHabitos) -> ft.Container:
    contenido = [
        t.etiqueta("hábitos", color=t.BASE, size=t.CAPTION),
        t.barra(min(d.racha_minima / 7, 1.0), segmentos=7, alto=6),
        ft.Row([
            t.texto(f"racha mínima {d.racha_minima} d", color=t.TENUE, size=t.MICRO),
            t.texto(f"{d.puntaje_pct:.0f}% hoy · racha {d.racha_global} d",
                    color=t.APAGADO, size=t.MICRO),
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
    ]
    if d.sugerir_mision_minima:
        contenido.append(t.aviso(
            "Dos días flojos. Una sola cosa corta hoy — 10 minutos cuentan "
            "para la racha mínima.", "baja"))
    return ft.Container(
        content=ft.Column(contenido, spacing=6, tight=True),
        padding=ft.padding.only(left=t.ESPACIO, right=t.ESPACIO, top=t.ESPACIO, bottom=4),
    )


# ---------------------------------------------------------------------------
# Historial de 7 días — barra de segmentos, igual firma visual que el resto
# ---------------------------------------------------------------------------

def _historial_barra(historial: list) -> ft.Row:
    celdas = []
    for f in historial:
        if f.valor is None:
            color = t.LINEA
        elif f.completado:
            color = t.VIVO
        else:
            color = t.AMBAR_TENUE
        celdas.append(ft.Container(height=10, bgcolor=color, expand=True, border_radius=0))
    return ft.Row(celdas, spacing=2, height=10)


# ---------------------------------------------------------------------------
# Marcar el día — valor real, no solo check
# ---------------------------------------------------------------------------

def _control_marcar(h: FilaHabitoDetalle, on_marcar=None) -> ft.Control:
    if h.metrica == "check":
        nivel = "ok" if h.completado_hoy else "pendiente"
        return ft.Container(
            content=t.estado(nivel),
            on_click=(lambda e: on_marcar(h.nombre, 0.0 if h.completado_hoy else 1.0))
            if on_marcar else None,
            ink=False, padding=4,
        )

    unidad = "min" if h.metrica == "duracion_min" else ""
    campo = ft.TextField(
        value=(f"{h.valor_hoy:g}" if h.valor_hoy is not None else ""),
        width=56, text_align=ft.TextAlign.RIGHT, hint_text="—",
        bgcolor=t.PANEL, color=t.BASE, border_color=t.LINEA,
        focused_border_color=t.VIVO, border_radius=t.RADIO, content_padding=8,
        text_size=t.CAPTION,
    )

    def _guardar(e):
        if not on_marcar:
            return
        try:
            valor = max(0.0, float(campo.value))
        except (TypeError, ValueError):
            return
        on_marcar(h.nombre, valor)

    campo.on_submit = _guardar
    campo.on_blur = _guardar

    return ft.Row([campo, t.texto(unidad, color=t.APAGADO, size=t.MICRO)],
                 spacing=4, tight=True, vertical_alignment=ft.CrossAxisAlignment.CENTER)


# ---------------------------------------------------------------------------
# Fila por hábito
# ---------------------------------------------------------------------------

def _fila_habito(h: FilaHabitoDetalle, on_marcar=None) -> ft.Container:
    encabezado = ft.Row([
        t.icono(h.icono, 22) if h.icono in CLAVES_ICONO else ft.Container(width=22),
        ft.Column([
            ft.Row([
                t.texto(h.nombre, color=t.BASE),
                t.texto("esencial", color=t.APAGADO, size=t.MICRO) if h.esencial else ft.Container(),
            ], spacing=8),
            t.texto(f"racha {h.racha} d" if h.racha else "sin racha",
                    color=t.VIVO if h.racha else t.APAGADO, size=t.MICRO),
        ], spacing=2, tight=True, expand=True),
        _control_marcar(h, on_marcar),
    ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER)

    return ft.Container(
        content=ft.Column([encabezado, _historial_barra(h.historial_7d)], spacing=8, tight=True),
        padding=ft.padding.symmetric(horizontal=t.ESPACIO, vertical=10),
        border=ft.border.all(t.BORDE, t.LINEA), border_radius=t.RADIO, bgcolor=t.PANEL,
    )


# ---------------------------------------------------------------------------
# Crear hábito — nombre libre, tipo, métrica, esencial
# ---------------------------------------------------------------------------

_OPCIONES_TIPO = [("mantener", "mantener"), ("moderar", "moderar")]
_OPCIONES_METRICA = [("check", "check"), ("contador", "contador"), ("duracion_min", "duración (min)")]
_OPCIONES_OBJETIVO = [("binario", "binario"), ("aumentar", "aumentar"), ("reducir", "reducir")]


def _bloque_crear_habito(on_crear_habito=None) -> ft.Container:
    campo_nombre = ft.TextField(label="nombre (alias discreto está bien)",
                                bgcolor=t.PANEL, color=t.BASE, border_color=t.LINEA,
                                focused_border_color=t.VIVO, border_radius=t.RADIO,
                                content_padding=10, text_size=t.BODY)
    dd_tipo = ft.Dropdown(label="tipo", value="mantener",
                          options=[ft.dropdown.Option(k, v) for k, v in _OPCIONES_TIPO],
                          bgcolor=t.PANEL, color=t.BASE, border_color=t.LINEA, text_size=t.BODY)
    dd_metrica = ft.Dropdown(label="métrica", value="check",
                             options=[ft.dropdown.Option(k, v) for k, v in _OPCIONES_METRICA],
                             bgcolor=t.PANEL, color=t.BASE, border_color=t.LINEA, text_size=t.BODY)
    dd_objetivo = ft.Dropdown(label="tipo de objetivo", value="binario",
                              options=[ft.dropdown.Option(k, v) for k, v in _OPCIONES_OBJETIVO],
                              bgcolor=t.PANEL, color=t.BASE, border_color=t.LINEA, text_size=t.BODY)
    campo_umbral = ft.TextField(label="valor objetivo (si no es binario)",
                                keyboard_type=ft.KeyboardType.NUMBER,
                                bgcolor=t.PANEL, color=t.BASE, border_color=t.LINEA,
                                focused_border_color=t.VIVO, border_radius=t.RADIO,
                                content_padding=10, text_size=t.BODY)
    chip_esencial = t.chip("esencial")
    estado_esencial = {"valor": False}

    def _toggle_esencial(e):
        estado_esencial["valor"] = not estado_esencial["valor"]
        nuevo = t.chip("esencial", activo=estado_esencial["valor"])
        chip_esencial.bgcolor = nuevo.bgcolor
        chip_esencial.border = nuevo.border
        chip_esencial.content = nuevo.content
        if chip_esencial.page:
            chip_esencial.update()

    chip_esencial.on_click = _toggle_esencial
    chip_esencial.ink = False

    def _enviar(e):
        if not on_crear_habito:
            return
        nombre = (campo_nombre.value or "").strip()
        if not nombre:
            return
        try:
            valor_objetivo = float(campo_umbral.value) if campo_umbral.value else 1.0
        except ValueError:
            valor_objetivo = 1.0
        on_crear_habito(nombre, dd_tipo.value, dd_metrica.value, dd_objetivo.value,
                        valor_objetivo, estado_esencial["valor"])

    return t.panel([
        campo_nombre, dd_tipo, dd_metrica, dd_objetivo, campo_umbral,
        chip_esencial,
        t.boton("crear hábito", on_click=_enviar, primario=True),
    ], titulo="crear hábito")


# ---------------------------------------------------------------------------
# Vista
# ---------------------------------------------------------------------------

def vista(d: DatosHabitos, on_marcar=None, on_crear_habito=None) -> ft.Control:
    """
    Callbacks, todos opcionales:
      on_marcar(nombre, valor)     — tocar el estado (check) o guardar el campo numérico
      on_crear_habito(nombre, tipo, metrica, tipo_objetivo, valor_objetivo, esencial)
    """
    filas = [_cabecera(d)]

    if not d.habitos:
        filas.append(t.panel([
            t.texto("Aún no has definido hábitos.", color=t.TENUE),
            t.texto("Créalos abajo, con el nombre que quieras.", color=t.APAGADO, size=t.CAPTION),
        ], titulo="hábitos"))
    else:
        for h in d.habitos:
            filas.append(_fila_habito(h, on_marcar))

    filas.append(_bloque_crear_habito(on_crear_habito))

    columna = ft.Column(controls=filas, spacing=t.ESPACIO, scroll=ft.ScrollMode.AUTO, expand=True)
    return ft.Container(content=columna, bgcolor=t.VOID, expand=True,
                        padding=ft.padding.only(left=t.ESPACIO, right=t.ESPACIO,
                                                bottom=t.ESPACIO * 2))
