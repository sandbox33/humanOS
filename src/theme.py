"""
HumanOS — Sistema visual.

DIRECCIÓN: terminal de fósforo monocromo. Referencia Pip-Boy, pero con
datos reales en vez de estadísticas de juego.

La decisión que sostiene todo: NO HAY BLANCO NI GRIS. Un tubo de fósforo
único no puede producirlos — solo emite su propio color, variando en
intensidad. Casi todos los "temas Fallout" usan texto blanco y verde de
acento, y por eso se leen como una piel sobre un tema oscuro cualquiera.
Aquí hasta el texto más apagado es verde. Esa disciplina es la diferencia
entre parecer un CRT y ser uno.

El ámbar de advertencia tampoco es arbitrario: los monitores P3 eran
ámbar de verdad, así que cambiar de fósforo para señalar un estado
distinto es coherente con el mundo del que sale la referencia.

RENDIMIENTO: la app corre en un teléfono con recursos limitados. Nada de
sombras costosas, animaciones continuas ni capas apiladas. El "glow" se
simula con color, no con efectos de desenfoque.
"""

import flet as ft


# ---------------------------------------------------------------------------
# Paleta — rampa de fósforo, no "negro + acento"
# ---------------------------------------------------------------------------

VOID    = "#050A07"   # fondo: el tubo apagado, con tinte verde residual
PANEL   = "#0A140E"   # superficie elevada
LINEA   = "#14301F"   # hairlines, segmentos apagados
APAGADO = "#1F5236"   # texto deshabilitado, aún verde
TENUE   = "#2F7D52"   # etiquetas, texto secundario
BASE    = "#4FD98A"   # texto principal
VIVO    = "#18FF6D"   # valores, estado activo
BLOOM   = "#9DFFC4"   # realce: el halo del fósforo al máximo

AMBAR       = "#FFB000"   # advertencia — fósforo P3, no un color inventado
AMBAR_TENUE = "#8A6000"
ALARMA      = "#FF5F45"   # solo para límite real (seguridad alimentaria)
ALARMA_TENUE = "#5C2018"

# Regla de uso: BLOOM y VIVO son caros en atención. Un valor por pantalla
# merece BLOOM. Todo lo demás vive entre TENUE y BASE.


# ---------------------------------------------------------------------------
# Tipografía — monoespaciada en todo. Esa es la personalidad, no un detalle.
# ---------------------------------------------------------------------------

MONO = "monospace"   # main.py puede sustituirla por una fuente empaquetada

MICRO   = 10   # unidades, sufijos
CAPTION = 12   # etiquetas de campo
BODY    = 14   # texto corriente
VALOR   = 18   # cifras en fila
TITULO  = 22   # encabezado de sección
DISPLAY = 34   # la cifra protagonista de la pantalla

TRACK_ETIQUETA = 1.8   # el interletrado ancho en mayúsculas es lo que hace
TRACK_NORMAL   = 0.3   # que una etiqueta se lea como terminal y no como app

RADIO = 2       # casi recto: un CRT no tiene esquinas redondeadas
BORDE = 1
ESPACIO = 12


# ---------------------------------------------------------------------------
# Texto
# ---------------------------------------------------------------------------

def etiqueta(texto: str, color: str = TENUE, size: int = CAPTION) -> ft.Text:
    """Etiqueta de campo: mayúsculas, interletrado ancho."""
    return ft.Text(texto.upper(), size=size, color=color, font_family=MONO,
                   weight=ft.FontWeight.W_500,
                   style=ft.TextStyle(letter_spacing=TRACK_ETIQUETA))


def texto(contenido: str, color: str = BASE, size: int = BODY,
          weight=ft.FontWeight.W_400, **kw) -> ft.Text:
    return ft.Text(contenido, size=size, color=color, font_family=MONO,
                   weight=weight,
                   style=ft.TextStyle(letter_spacing=TRACK_NORMAL), **kw)


def valor(numero, unidad: str = "", color: str = VIVO,
          size: int = VALOR) -> ft.Row:
    """
    Cifra con su unidad en menor jerarquía. Separarlas evita que la unidad
    compita con el número, que es lo que en realidad se lee de un vistazo.
    """
    hijos = [ft.Text(str(numero), size=size, color=color, font_family=MONO,
                     weight=ft.FontWeight.W_600)]
    if unidad:
        hijos.append(ft.Text(unidad, size=max(MICRO, size - 8), color=TENUE,
                             font_family=MONO))
    return ft.Row(hijos, spacing=4, alignment=ft.MainAxisAlignment.START,
                  vertical_alignment=ft.CrossAxisAlignment.END, tight=True)


def display(numero, unidad: str = "", color: str = BLOOM) -> ft.Row:
    """La cifra protagonista. Una por pantalla, no más."""
    return valor(numero, unidad, color=color, size=DISPLAY)


# ---------------------------------------------------------------------------
# ELEMENTO FIRMA — barra segmentada
# ---------------------------------------------------------------------------
# Un solo componente para toda métrica de la app: calorías, proteína,
# rachas, cuenta atrás de la comida cocinada.
#
# Los segmentos no son decoración. Su cantidad significa algo: 5 segmentos
# para 5 comidas, 7 para los días de la semana. Cuando la unidad no tiene
# un número natural, se usan 20 como escala de lectura.

def barra(fraccion: float, segmentos: int = 20, color: str = VIVO,
          color_apagado: str = LINEA, alto: int = 10,
          exceso_color: str = AMBAR) -> ft.Row:
    """
    fraccion: 0.0 a 1.0+. Por encima de 1.0 los segmentos sobrantes se
    marcan en ámbar — pasarse se ve distinto de llegar, que es información
    real y no un detalle estético.
    """
    fraccion = max(0.0, fraccion)
    llenos = int(round(min(fraccion, 1.0) * segmentos))
    sobra = fraccion > 1.02

    celdas = []
    for i in range(segmentos):
        if i < llenos:
            c = exceso_color if sobra else color
        else:
            c = color_apagado
        celdas.append(ft.Container(width=None, height=alto, bgcolor=c,
                                   expand=True, border_radius=0))
    return ft.Row(celdas, spacing=2, height=alto)


def barra_etiquetada(nombre: str, actual, meta, unidad: str = "",
                     segmentos: int = 20, color: str = VIVO) -> ft.Column:
    """Barra con su lectura numérica encima — la barra da la forma, el número el dato."""
    fraccion = (actual / meta) if meta else 0.0
    pct = int(round(fraccion * 100))
    color_pct = AMBAR if fraccion > 1.02 else (color if fraccion >= 0.85 else TENUE)

    return ft.Column([
        ft.Row([
            etiqueta(nombre),
            ft.Row([
                texto(f"{actual:g}", color=BASE, size=CAPTION),
                texto(f"/{meta:g}{unidad}", color=TENUE, size=CAPTION),
                texto(f"{pct}%", color=color_pct, size=CAPTION,
                      weight=ft.FontWeight.W_600),
            ], spacing=6, tight=True),
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
        barra(fraccion, segmentos=segmentos, color=color),
    ], spacing=6, tight=True)


# ---------------------------------------------------------------------------
# Estructura — marcos y encabezados
# ---------------------------------------------------------------------------

def panel(contenido, titulo: str = None, color_borde: str = LINEA,
          padding: int = ESPACIO) -> ft.Container:
    """Superficie enmarcada. El marco delimita datos, no adorna."""
    hijos = []
    if titulo:
        hijos.append(encabezado(titulo))
    if isinstance(contenido, list):
        hijos.extend(contenido)
    else:
        hijos.append(contenido)

    return ft.Container(
        content=ft.Column(hijos, spacing=ESPACIO - 2, tight=True),
        bgcolor=PANEL,
        border=ft.border.all(BORDE, color_borde),
        border_radius=RADIO,
        padding=padding,
    )


def encabezado(titulo: str, color: str = TENUE) -> ft.Row:
    """
    Encabezado entre corchetes con una regla que ocupa el resto del ancho.
    Los corchetes son gramática de terminal; la regla marca dónde termina
    la sección sin necesidad de otro borde.
    """
    return ft.Row([
        etiqueta(f"[ {titulo} ]", color=color),
        ft.Container(height=1, bgcolor=LINEA, expand=True,
                     margin=ft.margin.only(left=8, bottom=4)),
    ], spacing=0, vertical_alignment=ft.CrossAxisAlignment.CENTER)


def fila_dato(nombre: str, contenido, color_valor: str = BASE) -> ft.Row:
    """Etiqueta a la izquierda, dato a la derecha. La unidad de lectura básica."""
    derecha = contenido if isinstance(contenido, ft.Control) else \
        texto(str(contenido), color=color_valor)
    return ft.Row([etiqueta(nombre), derecha],
                  alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                  vertical_alignment=ft.CrossAxisAlignment.CENTER)


def separador() -> ft.Container:
    return ft.Container(height=1, bgcolor=LINEA,
                        margin=ft.margin.symmetric(vertical=4))


# ---------------------------------------------------------------------------
# Estado — glifos, no emoji
# ---------------------------------------------------------------------------
# Emoji rompería la ilusión del fósforo único: trae color propio. Estos
# glifos se renderizan en el color que se les pida.

GLIFO_OK       = "●"
GLIFO_AVISO    = "▲"
GLIFO_LIMITE   = "■"
GLIFO_PENDIENTE = "○"
GLIFO_ACTIVO   = "▶"

COLOR_POR_NIVEL = {
    "ok": VIVO,
    "aviso": AMBAR,
    "limite": ALARMA,
    "pendiente": APAGADO,
}

GLIFO_POR_NIVEL = {
    "ok": GLIFO_OK,
    "aviso": GLIFO_AVISO,
    "limite": GLIFO_LIMITE,
    "pendiente": GLIFO_PENDIENTE,
}


def estado(nivel: str, size: int = BODY) -> ft.Text:
    return ft.Text(GLIFO_POR_NIVEL.get(nivel, GLIFO_PENDIENTE), size=size,
                   color=COLOR_POR_NIVEL.get(nivel, APAGADO), font_family=MONO)


def chip(texto_chip: str, color: str = TENUE, activo: bool = False) -> ft.Container:
    """Selector compacto. Activo = fondo de fósforo tenue, no un color nuevo."""
    return ft.Container(
        content=ft.Text(texto_chip, size=CAPTION,
                        color=VOID if activo else color,
                        font_family=MONO, weight=ft.FontWeight.W_500),
        bgcolor=VIVO if activo else "transparent",
        border=ft.border.all(BORDE, VIVO if activo else LINEA),
        border_radius=RADIO,
        padding=ft.padding.symmetric(horizontal=10, vertical=5),
    )


# ---------------------------------------------------------------------------
# Avisos — jerarquía por severidad
# ---------------------------------------------------------------------------

def aviso(mensaje: str, severidad: str = "media") -> ft.Container:
    """
    Advertencia o sinergia. La franja izquierda lleva el color; el texto se
    mantiene legible. Un bloque entero en ámbar cansa la vista y hace que
    se ignoren los avisos, que es lo contrario de lo que se busca.
    """
    colores = {
        "sinergia": (VIVO, "+"),
        "baja": (TENUE, "·"),
        "media": (AMBAR, "!"),
        "alta": (ALARMA, "!!"),
    }
    color, marca = colores.get(severidad, (AMBAR, "!"))

    return ft.Container(
        content=ft.Row([
            ft.Container(width=3, bgcolor=color, border_radius=0),
            ft.Column([
                ft.Row([
                    ft.Text(marca, size=CAPTION, color=color, font_family=MONO,
                            weight=ft.FontWeight.W_700),
                    ft.Text(mensaje, size=CAPTION, color=BASE, font_family=MONO,
                            expand=True, no_wrap=False),
                ], spacing=8, vertical_alignment=ft.CrossAxisAlignment.START),
            ], expand=True, tight=True),
        ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.STRETCH),
        bgcolor=PANEL,
        border=ft.border.all(BORDE, LINEA),
        border_radius=RADIO,
        padding=ft.padding.symmetric(horizontal=10, vertical=8),
    )


def dato_incierto(mensaje: str) -> ft.Row:
    """
    Marca visible para estimaciones y datos de confianza baja. Existe
    porque el motor distingue medido de estimado, y esa distinción se
    pierde si en pantalla ambos se ven igual.
    """
    return ft.Row([
        ft.Text("≈", size=CAPTION, color=APAGADO, font_family=MONO),
        ft.Text(mensaje, size=MICRO, color=APAGADO, font_family=MONO,
                expand=True, no_wrap=False, italic=True),
    ], spacing=6, vertical_alignment=ft.CrossAxisAlignment.START)


# ---------------------------------------------------------------------------
# Botones
# ---------------------------------------------------------------------------

def boton(texto_boton: str, on_click=None, primario: bool = False,
          color: str = None, ancho: int = None) -> ft.Container:
    c = color or (VIVO if primario else TENUE)
    return ft.Container(
        content=ft.Text(texto_boton.upper(), size=CAPTION,
                        color=VOID if primario else c, font_family=MONO,
                        weight=ft.FontWeight.W_600,
                        style=ft.TextStyle(letter_spacing=TRACK_ETIQUETA),
                        text_align=ft.TextAlign.CENTER),
        bgcolor=c if primario else "transparent",
        border=ft.border.all(BORDE, c),
        border_radius=RADIO,
        padding=ft.padding.symmetric(horizontal=16, vertical=11),
        width=ancho,
        on_click=on_click,
        ink=False,   # el ripple de Material rompería la ilusión de terminal
        alignment=ft.alignment.center,
    )


# ---------------------------------------------------------------------------
# Íconos
# ---------------------------------------------------------------------------
# Solo glifos — se probó con imágenes propias (siluetas recortadas del
# fondo) pero se decidió no usarlas: la estética queda 100% Fallout/Pip-Boy
# con el monocromo de fósforo y estos caracteres, sin arte externo que
# mantener. Registro por clave para que agregar un hábito con ícono nuevo
# no obligue a tocar las vistas — solo agregar la clave acá.

ICONOS = {
    "vicios":        "◉",
    "masturbacion":  "◑",
    "comida":        "▣",
    "entrenamiento": "▲",
    "correr":        "▶",
    "progreso":      "◆",
    "concentracion": "◈",
    "trabajo":       "■",
    "fumar":         "◎",
    "deterioro":     "▽",
}


def icono(clave: str, size: int = 28, color: str = BASE) -> ft.Text:
    """Glifo de fósforo para la clave dada. Clave desconocida -> ◇, nunca falla."""
    return ft.Text(ICONOS.get(clave, "◇"), size=size, color=color, font_family=MONO)


# ---------------------------------------------------------------------------
# Textura CRT
# ---------------------------------------------------------------------------

def con_scanlines(contenido: ft.Control, opacidad: float = 0.05) -> ft.Stack:
    """
    Líneas de barrido sobre el contenido. Deliberadamente barato: un solo
    gradiente repetido, no cientos de contenedores. En un teléfono con
    recursos justos, una textura pesada costaría fluidez a cambio de nada.
    """
    lineas = ft.Container(
        expand=True,
        gradient=ft.LinearGradient(
            begin=ft.alignment.top_center,
            end=ft.alignment.bottom_center,
            colors=[VOID, "#00000000", VOID],
            stops=[0.0, 0.5, 1.0],
            tile_mode=ft.GradientTileMode.REPEATED,
        ),
        opacity=opacidad,
    )
    return ft.Stack([contenido, lineas], expand=True)


def aplicar_tema(page: ft.Page, titulo: str = "HumanOS") -> None:
    """Configuración global de la página."""
    page.title = titulo
    page.bgcolor = VOID
    page.padding = 0
    page.theme_mode = ft.ThemeMode.DARK
    page.theme = ft.Theme(font_family=MONO)
    page.fonts = {}


# ---------------------------------------------------------------------------
# Confianza y supuestos
# ---------------------------------------------------------------------------
# El motor distingue medido, calculado y estimado. Si en pantalla los tres
# se ven igual, esa distinción se pierde y un número estimado se lee como
# una medición.

SELLO_CONFIANZA = {
    "alta":  ("", BASE),           # medido o derivado de datos que diste
    "media": ("≈", TENUE),         # estimado con supuestos razonables
    "baja":  ("≈", APAGADO),       # provisional, faltan datos
}


def con_confianza(control_valor: ft.Control, nivel: str = "alta") -> ft.Row:
    """Antepone el signo de aproximación al valor, no a una leyenda aparte."""
    signo, color = SELLO_CONFIANZA.get(nivel, ("", BASE))
    hijos = []
    if signo:
        hijos.append(ft.Text(signo, size=CAPTION, color=color, font_family=MONO))
    hijos.append(control_valor)
    return ft.Row(hijos, spacing=4, tight=True,
                  vertical_alignment=ft.CrossAxisAlignment.END)


def sello_estado(texto_estado: str, confianza: str = "alta") -> ft.Container:
    """
    Etiqueta de estado del día. 'día libre' y 'sin datos' NO son lo mismo y
    no deben compartir texto: uno es información, el otro es su ausencia.
    """
    colores = {"alta": TENUE, "media": AMBAR_TENUE, "baja": APAGADO}
    c = colores.get(confianza, TENUE)
    return ft.Container(
        content=etiqueta(texto_estado, color=AMBAR if confianza == "media" else c,
                         size=MICRO),
        border=ft.border.all(BORDE, c),
        border_radius=RADIO,
        padding=ft.padding.symmetric(horizontal=7, vertical=3),
    )


def supuesto_nota(titulo_sup: str, explica: str) -> ft.Container:
    """
    Muestra un supuesto del modelo. Va desplegado, no escondido en un
    tooltip: en un teléfono los tooltips casi no se descubren, y el punto
    es que estos números se vean como decisiones y no como hechos.
    """
    return ft.Container(
        content=ft.Column([
            ft.Row([
                ft.Text("§", size=MICRO, color=APAGADO, font_family=MONO),
                etiqueta(titulo_sup, color=APAGADO, size=MICRO),
            ], spacing=6),
            ft.Text(explica, size=MICRO, color=APAGADO, font_family=MONO,
                    no_wrap=False),
        ], spacing=3, tight=True),
        padding=ft.padding.only(left=10, top=4, bottom=4),
        border=ft.border.only(left=ft.BorderSide(1, LINEA)),
    )


def aviso_clinico(mensaje: str) -> ft.Container:
    """
    Nivel visual propio, separado de los avisos nutricionales. Una nota
    sobre medicamentos no pertenece a la misma categoría que "el café baja
    la absorción del hierro", y mezclarlas hace que ambas pesen menos.
    """
    return ft.Container(
        content=ft.Row([
            ft.Text("⚕", size=BODY, color=AMBAR, font_family=MONO),
            ft.Column([
                etiqueta("nota clínica", color=AMBAR, size=MICRO),
                ft.Text(mensaje, size=CAPTION, color=BASE, font_family=MONO,
                        no_wrap=False),
            ], spacing=4, tight=True, expand=True),
        ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.START),
        bgcolor=PANEL,
        border=ft.border.all(BORDE, AMBAR_TENUE),
        border_radius=RADIO,
        padding=ft.padding.symmetric(horizontal=12, vertical=10),
    )


def ingerido_vs_absorbido(nombre: str, ingerido: str, absorbido: str,
                          nota: str = None) -> ft.Column:
    """
    Dos cifras que la gente confunde y que el motor calcula por separado:
    lo que hay en el plato y lo que probablemente aprovechas. Se muestran
    juntas y jerarquizadas para que la diferencia sea el mensaje.
    """
    hijos = [
        ft.Row([
            etiqueta(nombre),
            ft.Row([
                texto(ingerido, color=TENUE, size=CAPTION),
                ft.Text("→", size=CAPTION, color=APAGADO, font_family=MONO),
                ft.Text("≈", size=CAPTION, color=TENUE, font_family=MONO),
                texto(absorbido, color=VIVO, size=CAPTION,
                      weight=ft.FontWeight.W_600),
            ], spacing=6, tight=True),
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
    ]
    if nota:
        hijos.append(dato_incierto(nota))
    return ft.Column(hijos, spacing=4, tight=True)
