"""
HumanOS — Pantalla principal.

RESPONSABILIDAD: ordenar y mostrar. No calcula calorías, proteína,
absorción ni rachas — todo eso llega ya resuelto por los motores. Si esta
vista tuviera que calcular algo, sería el segundo lugar donde vive esa
regla, y tarde o temprano los dos números dejarían de coincidir.

Por eso recibe un DatosHoy: un contenedor plano con todo listo. Así la
pantalla se puede probar sin base de datos, con valores inventados,
incluidos los casos raros que en uso real tardarían semanas en aparecer.

ORDEN DE LECTURA — de arriba abajo, por lo que necesitas decidir ahora:
  1. estado del día      qué régimen aplica hoy y con cuánta certeza
  2. progreso            cuánto llevas
  3. comidas             qué toca y qué se saltó
  4. comida cocinada     lo que caduca (sin nevera, esto es urgente)
  5. hábitos             la racha, sin competir con lo de arriba
  6. notas               sinergias, advertencias, clínica
"""

import datetime as dt
from dataclasses import dataclass, field

import flet as ft

import theme as t


# ---------------------------------------------------------------------------
# Lo que la vista necesita — nada más, nada calculado aquí
# ---------------------------------------------------------------------------

@dataclass
class FilaComida:
    orden: int
    nombre: str
    hora: str
    meta_kcal: float
    meta_prot: float
    estado: str              # 'ok' | 'aviso' | 'limite' | 'pendiente'
    detalle: str = ""


@dataclass
class FilaCoccion:
    nombre: str
    horas: float
    nivel: str
    mensaje: str


@dataclass
class FilaHabito:
    nombre: str
    icono: str = None
    cumplido: bool = False
    sin_dato: bool = True
    racha: int = 0


@dataclass
class DatosHoy:
    fecha: dt.date

    # Estado del día
    estado_dia: str = "sin_datos"        # 'jornada' | 'dia_libre' | 'sin_datos'
    confianza_dia: str = "baja"
    nota_dia: str = ""
    horas_jornada: float = None

    # Objetivo y progreso
    objetivo_kcal: int = 0
    kcal_hoy: float = 0.0
    objetivo_prot: int = 0
    prot_hoy: float = 0.0
    explicacion_proteina: str = ""

    # Bloques
    comidas: list = field(default_factory=list)
    cocciones: list = field(default_factory=list)
    habitos: list = field(default_factory=list)

    racha_minima: int = 0
    racha_global: int = 0
    puntaje_pct: float = 0.0
    sugerir_mision_minima: bool = False

    # Notas — llegan ya redactadas por los motores
    sinergias: list = field(default_factory=list)     # [(mensaje, magnitud)]
    advertencias: list = field(default_factory=list)  # [(mensaje, severidad)]
    notas_clinicas: list = field(default_factory=list)
    supuestos: list = field(default_factory=list)     # [(titulo, explicacion)]

    proxima_comida: str = ""


ETIQUETA_ESTADO = {
    "jornada":   "jornada registrada",
    "dia_libre": "día libre",
    "sin_datos": "sin datos",
}

MESES = ["ene","feb","mar","abr","may","jun","jul","ago","sep","oct","nov","dic"]


def _fecha_corta(f: dt.date) -> str:
    return f"{f.day:02d} {MESES[f.month-1]} {f.year}"


# ---------------------------------------------------------------------------
# Bloques
# ---------------------------------------------------------------------------

def _cabecera(d: DatosHoy) -> ft.Container:
    """
    Fecha y régimen del día. El sello de estado va aquí arriba porque
    condiciona todo lo que sigue: un objetivo de día libre y uno
    provisional por falta de datos no se leen igual.
    """
    izquierda = ft.Column([
        t.etiqueta("hoy", color=t.BASE, size=t.CAPTION),
        t.texto(_fecha_corta(d.fecha), color=t.TENUE, size=t.MICRO),
    ], spacing=2, tight=True)

    sello = t.sello_estado(ETIQUETA_ESTADO.get(d.estado_dia, d.estado_dia),
                           d.confianza_dia)
    if d.estado_dia == "jornada" and d.horas_jornada:
        sello = ft.Row([
            sello,
            t.texto(f"{d.horas_jornada:g} h", color=t.TENUE, size=t.MICRO),
        ], spacing=6, tight=True)

    return ft.Container(
        content=ft.Row([izquierda, sello],
                       alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                       vertical_alignment=ft.CrossAxisAlignment.CENTER),
        padding=ft.padding.only(left=t.ESPACIO, right=t.ESPACIO,
                                top=t.ESPACIO, bottom=4),
    )


def _bloque_objetivo(d: DatosHoy) -> ft.Container:
    """
    La cifra protagonista de la pantalla. Lleva el signo ≈ cuando el
    objetivo depende de supuestos, para que no se lea como una medición.
    """
    cifra = t.display(d.objetivo_kcal, "kcal")
    contenido = [
        t.con_confianza(cifra, d.confianza_dia),
        t.texto(d.nota_dia, color=t.TENUE, size=t.MICRO, no_wrap=False),
        t.separador(),
        t.barra_etiquetada("energía", round(d.kcal_hoy), d.objetivo_kcal, " kcal"),
        t.barra_etiquetada("proteína", round(d.prot_hoy), d.objetivo_prot, " g"),
    ]
    if d.explicacion_proteina:
        contenido.append(t.dato_incierto(d.explicacion_proteina))
    return t.panel(contenido, titulo="objetivo")


def _bloque_comidas(d: DatosHoy, on_registrar=None) -> ft.Container:
    """
    Las cinco comidas. La barra de cinco segmentos es literal: un segmento
    por comida, no una escala arbitraria.
    """
    if not d.comidas:
        return t.panel([
            t.texto("No hay comidas configuradas.", color=t.TENUE),
            t.texto("Defínelas en Perfil para empezar a registrar.",
                    color=t.APAGADO, size=t.CAPTION),
        ], titulo="comidas")

    hechas = sum(1 for c in d.comidas if c.estado == "ok")
    filas = [
        ft.Row([
            t.barra(hechas / len(d.comidas), segmentos=len(d.comidas)),
        ]),
        ft.Row([
            t.etiqueta(f"{hechas} de {len(d.comidas)} registradas"),
            t.texto(d.proxima_comida, color=t.TENUE, size=t.MICRO)
            if d.proxima_comida else ft.Container(),
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
        t.separador(),
    ]

    for c in d.comidas:
        etiqueta_hora = t.texto(c.hora, color=t.TENUE, size=t.CAPTION)
        nombre = t.texto(c.nombre,
                         color=t.BASE if c.estado != "pendiente" else t.TENUE,
                         size=t.BODY)
        meta = t.texto(f"{c.meta_kcal:.0f} kcal · {c.meta_prot:.0f} g",
                       color=t.APAGADO, size=t.MICRO)

        accion = ft.Container(
            content=t.texto("+", color=t.VIVO, size=t.VALOR),
            padding=ft.padding.symmetric(horizontal=10, vertical=2),
            on_click=(lambda e, orden=c.orden: on_registrar(orden))
            if on_registrar else None,
            ink=False,
        )

        filas.append(ft.Row([
            t.estado(c.estado),
            ft.Column([
                ft.Row([etiqueta_hora, nombre], spacing=10),
                meta if not c.detalle else t.texto(c.detalle, color=t.APAGADO,
                                                  size=t.MICRO),
            ], spacing=2, tight=True, expand=True),
            accion,
        ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER))

    return t.panel(filas, titulo="comidas")


def _bloque_cocciones(d: DatosHoy) -> ft.Container:
    """
    Sin refrigeración, esto caduca con reloj. Va por encima de hábitos
    porque es lo único de la pantalla que se vuelve urgente solo.
    """
    if not d.cocciones:
        return None

    borde = t.LINEA
    if any(c.nivel == "limite" for c in d.cocciones):
        borde = t.ALARMA_TENUE
    elif any(c.nivel == "aviso" for c in d.cocciones):
        borde = t.AMBAR_TENUE

    filas = []
    for c in d.cocciones:
        color = t.COLOR_POR_NIVEL.get(c.nivel, t.BASE)
        restante = max(0.0, 4.0 - c.horas)
        filas.append(ft.Column([
            ft.Row([
                t.estado(c.nivel),
                t.texto(c.nombre, color=t.BASE, expand=True),
                t.texto(f"{c.horas:.1f} h", color=color, size=t.CAPTION),
            ], spacing=10),
            t.barra(min(c.horas / 4.0, 1.0), segmentos=8, color=color,
                    alto=5, exceso_color=t.ALARMA),
            t.texto(c.mensaje, color=t.TENUE, size=t.MICRO, no_wrap=False),
        ], spacing=5, tight=True))

    return t.panel(filas, titulo="cocinado hoy", color_borde=borde)


def _bloque_habitos(d: DatosHoy, on_marcar=None) -> ft.Container:
    if not d.habitos:
        return t.panel([
            t.texto("Aún no has definido hábitos.", color=t.TENUE),
            t.texto("Agrégalos con el nombre que quieras.",
                    color=t.APAGADO, size=t.CAPTION),
        ], titulo="hábitos")

    filas = []
    for h in d.habitos:
        nivel = "pendiente" if h.sin_dato else ("ok" if h.cumplido else "aviso")
        marca = ft.Container(
            content=t.estado(nivel),
            on_click=(lambda e, n=h.nombre: on_marcar(n)) if on_marcar else None,
            ink=False, padding=2,
        )
        filas.append(ft.Row([
            marca,
            t.icono(h.icono, 20) if h.icono else ft.Container(width=20),
            t.texto(h.nombre, color=t.BASE if not h.sin_dato else t.TENUE,
                    expand=True),
            t.texto(f"{h.racha} d" if h.racha else "—",
                    color=t.VIVO if h.racha else t.APAGADO, size=t.CAPTION),
        ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.CENTER))

    filas.append(t.separador())
    # Racha mínima primero: es la que sobrevive los días malos, y por eso
    # es la que conviene mirar cuando el día va mal.
    filas.append(ft.Row([
        ft.Column([
            t.etiqueta("racha mínima", color=t.TENUE),
            t.barra(min(d.racha_minima / 7, 1.0), segmentos=7, alto=6),
        ], spacing=5, expand=True),
        ft.Column([
            t.valor(d.racha_minima, "días", size=t.VALOR),
        ], horizontal_alignment=ft.CrossAxisAlignment.END, tight=True),
    ], spacing=14, vertical_alignment=ft.CrossAxisAlignment.CENTER))

    filas.append(ft.Row([
        t.etiqueta("día completo", color=t.APAGADO),
        t.texto(f"{d.puntaje_pct:.0f}%  ·  racha {d.racha_global} d",
                color=t.TENUE, size=t.MICRO),
    ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN))

    if d.sugerir_mision_minima:
        # Rampa de reentrada, no reproche: dice qué hacer ahora, no cuántos
        # días llevas fallando.
        filas.append(t.aviso(
            "Dos días flojos. Haz una sola cosa corta hoy — 10 minutos "
            "cuentan para la racha mínima.", "baja"))

    return t.panel(filas, titulo="hábitos")


def _bloque_notas(d: DatosHoy) -> ft.Container:
    """
    Sinergias primero, luego advertencias, y la nota clínica al final en su
    propio nivel visual. Si todo se mezclara, lo importante pesaría menos.
    """
    bloques = []
    for mensaje, _magnitud in d.sinergias:
        bloques.append(t.aviso(mensaje, "sinergia"))
    for mensaje, severidad in d.advertencias:
        bloques.append(t.aviso(mensaje, severidad))
    for mensaje in d.notas_clinicas:
        bloques.append(t.aviso_clinico(mensaje))
    for titulo, explica in d.supuestos:
        bloques.append(t.supuesto_nota(titulo, explica))

    if not bloques:
        return None
    return t.panel(bloques, titulo="notas")


# ---------------------------------------------------------------------------
# Vista
# ---------------------------------------------------------------------------

def vista(d: DatosHoy, on_registrar=None, on_marcar_habito=None) -> ft.Control:
    """
    Devuelve la pantalla completa. Los callbacks son opcionales: sin ellos
    la vista se renderiza igual, solo que sin interacción — útil para
    probarla aislada.
    """
    bloques = [
        _cabecera(d),
        _bloque_objetivo(d),
        _bloque_comidas(d, on_registrar),
        _bloque_cocciones(d),
        _bloque_habitos(d, on_marcar_habito),
        _bloque_notas(d),
    ]
    bloques = [b for b in bloques if b is not None]

    columna = ft.Column(
        controls=bloques,
        spacing=t.ESPACIO,
        scroll=ft.ScrollMode.AUTO,
        expand=True,
    )
    return ft.Container(content=columna, bgcolor=t.VOID, expand=True,
                        padding=ft.padding.only(left=t.ESPACIO, right=t.ESPACIO,
                                                bottom=t.ESPACIO * 2))
