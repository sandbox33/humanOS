"""
HumanOS — Pantalla de perfil.

RESPONSABILIDAD: ordenar y mostrar. Esta vista no recalcula el objetivo
calórico al cambiar el peso — solo manda el nuevo peso vía
on_guardar_perfil() y confía en que quien la llama vuelve a pedir un
DatosPerfil fresco (con objetivo_kcal_actual/objetivo_prot_actual ya
recalculados por nutrition_engine) y renderiza de nuevo. Mismo patrón
'en vivo' que views/comidas.py.

SUPUESTOS EDITABLES: son los 5 de config.SUPUESTOS. Cada uno llega con
su título y explicación ya redactados — igual que se muestran en Hoy,
aquí además se pueden tocar.
"""

import datetime as dt
from dataclasses import dataclass, field

import flet as ft

import theme as t


@dataclass
class FilaSupuesto:
    clave: str
    titulo: str
    explica: str
    valor: float


@dataclass
class FilaSuplemento:
    nombre: str
    hora: str
    notas: str = ""


@dataclass
class DatosPerfil:
    peso_kg: float = 60.0
    estatura_cm: float = 172.0
    edad: int = 28
    nivel_actividad: str = "alto"
    superavit_pct: float = 0.15
    proteina_g_por_kg: float = 1.8

    objetivo_kcal_actual: int = 0
    objetivo_prot_actual: int = 0

    jornada_hoy_entrada: str = ""       # "07:00" o "" si no hay dato
    jornada_hoy_salida: str = ""
    jornada_hoy_almuerzo: str = ""
    jornada_hoy_dia_libre: bool = False

    supuestos: list = field(default_factory=list)              # FilaSupuesto
    suplementos_pendientes: list = field(default_factory=list)  # FilaSuplemento


NIVELES_ACTIVIDAD = ["sedentario", "ligero", "moderado", "alto", "muy_alto"]

_ESTILO_CAMPO = dict(
    bgcolor=t.PANEL, color=t.BASE, border_color=t.LINEA,
    focused_border_color=t.VIVO, border_radius=t.RADIO, content_padding=10,
    text_size=t.BODY,
)


def _cabecera() -> ft.Container:
    return ft.Container(
        content=t.etiqueta("perfil", color=t.BASE, size=t.CAPTION),
        padding=ft.padding.only(left=t.ESPACIO, right=t.ESPACIO, top=t.ESPACIO, bottom=4),
    )


# ---------------------------------------------------------------------------
# Perfil físico — peso, estatura, edad, actividad, superávit, proteína
# ---------------------------------------------------------------------------

def _bloque_perfil_fisico(d: DatosPerfil, on_guardar_perfil=None) -> ft.Container:
    campo_peso = ft.TextField(label="peso (kg)", value=f"{d.peso_kg:g}",
                              keyboard_type=ft.KeyboardType.NUMBER, **_ESTILO_CAMPO)
    campo_estatura = ft.TextField(label="estatura (cm)", value=f"{d.estatura_cm:g}",
                                  keyboard_type=ft.KeyboardType.NUMBER, **_ESTILO_CAMPO)
    campo_edad = ft.TextField(label="edad", value=f"{d.edad:d}",
                              keyboard_type=ft.KeyboardType.NUMBER, **_ESTILO_CAMPO)
    dd_actividad = ft.Dropdown(
        label="nivel de actividad", value=d.nivel_actividad,
        options=[ft.dropdown.Option(n, n) for n in NIVELES_ACTIVIDAD],
        bgcolor=t.PANEL, color=t.BASE, border_color=t.LINEA, text_size=t.BODY,
    )
    campo_superavit = ft.TextField(label="superávit (%)", value=f"{d.superavit_pct * 100:g}",
                                   keyboard_type=ft.KeyboardType.NUMBER, **_ESTILO_CAMPO)
    campo_proteina = ft.TextField(label="proteína (g/kg)", value=f"{d.proteina_g_por_kg:g}",
                                  keyboard_type=ft.KeyboardType.NUMBER, **_ESTILO_CAMPO)

    def _guardar(e):
        if not on_guardar_perfil:
            return
        try:
            peso = float(campo_peso.value)
            estatura = float(campo_estatura.value)
            edad = int(float(campo_edad.value))
            superavit_pct = float(campo_superavit.value) / 100.0
            proteina_g_por_kg = float(campo_proteina.value)
        except (TypeError, ValueError):
            return
        if peso <= 0 or estatura <= 0 or edad <= 0:
            return
        on_guardar_perfil(peso, estatura, edad, dd_actividad.value, superavit_pct,
                          proteina_g_por_kg)

    return t.panel([
        campo_peso, campo_estatura, campo_edad, dd_actividad,
        campo_superavit, campo_proteina,
        t.separador(),
        ft.Row([
            t.etiqueta("objetivo actual", color=t.APAGADO),
            t.texto(f"{d.objetivo_kcal_actual} kcal · {d.objetivo_prot_actual} g prot",
                    color=t.VIVO, size=t.CAPTION, weight=ft.FontWeight.W_600),
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
        t.boton("guardar peso y perfil", on_click=_guardar, primario=True),
    ], titulo="perfil físico")


# ---------------------------------------------------------------------------
# Jornada de hoy
# ---------------------------------------------------------------------------

def _campo_hora(label: str, valor_inicial: str) -> ft.TextField:
    return ft.TextField(label=label, value=valor_inicial, hint_text="HH:MM", width=110,
                        **_ESTILO_CAMPO)


def _parsear_hora(texto: str):
    if not texto or not texto.strip():
        return None
    try:
        hh, mm = texto.strip().split(":")
        hh, mm = int(hh), int(mm)
        if 0 <= hh < 24 and 0 <= mm < 60:
            return hh, mm
    except (ValueError, AttributeError):
        pass
    return None


def _bloque_jornada(d: DatosPerfil, on_guardar_jornada=None) -> ft.Container:
    campo_entrada = _campo_hora("entrada", d.jornada_hoy_entrada)
    campo_salida = _campo_hora("salida", d.jornada_hoy_salida)
    campo_almuerzo = _campo_hora("almuerzo", d.jornada_hoy_almuerzo)
    chip_libre = t.chip("día libre", activo=d.jornada_hoy_dia_libre)
    estado_libre = {"valor": d.jornada_hoy_dia_libre}

    def _toggle_libre(e):
        estado_libre["valor"] = not estado_libre["valor"]
        nuevo = t.chip("día libre", activo=estado_libre["valor"])
        chip_libre.bgcolor, chip_libre.border, chip_libre.content = (
            nuevo.bgcolor, nuevo.border, nuevo.content)
        if chip_libre.page:
            chip_libre.update()

    chip_libre.on_click = _toggle_libre
    chip_libre.ink = False

    def _guardar(e):
        if not on_guardar_jornada:
            return
        entrada = _parsear_hora(campo_entrada.value)
        salida = _parsear_hora(campo_salida.value)
        almuerzo = _parsear_hora(campo_almuerzo.value)
        on_guardar_jornada(
            entrada[0] if entrada else None, entrada[1] if entrada else 0,
            salida[0] if salida else None, salida[1] if salida else 0,
            almuerzo[0] if almuerzo else None, almuerzo[1] if almuerzo else 0,
            estado_libre["valor"],
        )

    return t.panel([
        ft.Row([campo_entrada, campo_salida, campo_almuerzo], spacing=8, wrap=True),
        chip_libre,
        t.boton("guardar jornada de hoy", on_click=_guardar, primario=True),
    ], titulo="jornada de hoy")


# ---------------------------------------------------------------------------
# Supuestos editables
# ---------------------------------------------------------------------------

def _fila_supuesto(s: FilaSupuesto, on_editar_supuesto=None) -> ft.Column:
    campo = ft.TextField(value=f"{s.valor:g}", width=70, text_align=ft.TextAlign.RIGHT,
                         **_ESTILO_CAMPO)

    def _guardar(e):
        if not on_editar_supuesto:
            return
        try:
            nuevo = float(campo.value)
        except (TypeError, ValueError):
            return
        on_editar_supuesto(s.clave, nuevo)

    campo.on_submit = _guardar
    campo.on_blur = _guardar

    return ft.Column([
        ft.Row([
            t.etiqueta(s.titulo, color=t.BASE, size=t.CAPTION),
            campo,
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN, vertical_alignment=ft.CrossAxisAlignment.CENTER),
        t.texto(s.explica, color=t.APAGADO, size=t.MICRO, no_wrap=False),
    ], spacing=4, tight=True)


def _bloque_supuestos(d: DatosPerfil, on_editar_supuesto=None):
    if not d.supuestos:
        return None
    contenido = []
    for s in d.supuestos:
        contenido.append(_fila_supuesto(s, on_editar_supuesto))
        contenido.append(t.separador())
    contenido.pop()
    return t.panel(contenido, titulo="supuestos del modelo")


# ---------------------------------------------------------------------------
# Suplementos pendientes
# ---------------------------------------------------------------------------

def _bloque_suplementos(d: DatosPerfil, on_marcar_suplemento=None):
    if not d.suplementos_pendientes:
        return None
    filas = []
    for s in d.suplementos_pendientes:
        filas.append(ft.Row([
            ft.Column([
                t.texto(s.nombre, color=t.BASE),
                t.texto(f"{s.hora} · {s.notas}" if s.notas else s.hora,
                        color=t.APAGADO, size=t.MICRO, no_wrap=False),
            ], spacing=1, tight=True, expand=True),
            t.boton("tomado", ancho=90,
                   on_click=(lambda e, n=s.nombre: on_marcar_suplemento(n))
                   if on_marcar_suplemento else None),
        ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER))
    return t.panel(filas, titulo="suplementos pendientes", color_borde=t.AMBAR_TENUE)


# ---------------------------------------------------------------------------
# Vista
# ---------------------------------------------------------------------------

def vista(d: DatosPerfil, on_guardar_perfil=None, on_guardar_jornada=None,
         on_editar_supuesto=None, on_marcar_suplemento=None) -> ft.Control:
    """
    on_guardar_perfil(peso_kg, estatura_cm, edad, nivel_actividad, superavit_pct, proteina_g_por_kg)
    on_guardar_jornada(hora_e, min_e, hora_s, min_s, hora_a, min_a, dia_libre)  — None si el campo quedó vacío
    on_editar_supuesto(clave, nuevo_valor)
    on_marcar_suplemento(nombre)
    """
    bloques = [
        _cabecera(),
        _bloque_suplementos(d, on_marcar_suplemento),
        _bloque_perfil_fisico(d, on_guardar_perfil),
        _bloque_jornada(d, on_guardar_jornada),
        _bloque_supuestos(d, on_editar_supuesto),
    ]
    bloques = [b for b in bloques if b is not None]

    columna = ft.Column(controls=bloques, spacing=t.ESPACIO, scroll=ft.ScrollMode.AUTO, expand=True)
    return ft.Container(content=columna, bgcolor=t.VOID, expand=True,
                        padding=ft.padding.only(left=t.ESPACIO, right=t.ESPACIO,
                                                bottom=t.ESPACIO * 2))
