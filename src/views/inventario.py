"""
HumanOS — Pantalla de inventario y compras.

RESPONSABILIDAD: ordenar y mostrar, mismo criterio que hoy.py y
comidas.py. No calcula la lista de compras ni decide qué está agotado
— eso es shopping_engine.py vía presentador.datos_inventario(). Esta
vista solo pinta DatosInventario y expone los campos de los formularios
como texto libre; quien valida y decide qué hacer con esos valores es
quien conecte los callbacks (main.py -> presentador -> database).

Sin fecha ni usuario: el inventario y el catálogo son globales, no por
día ni por persona (una sola fuente de verdad en database.py).
"""

import datetime as dt
from dataclasses import dataclass, field

import flet as ft

import theme as t


# ---------------------------------------------------------------------------
# Lo que la vista necesita
# ---------------------------------------------------------------------------

@dataclass
class FilaAlimento:
    nombre: str
    categoria: str = "otro"
    gramos_disponibles: float = 0.0
    kcal_100g: float = 0.0
    proteina_100g: float = 0.0
    unidad_compra: str = "g"
    confianza: str = "media"     # 'alta' | 'media' | 'baja' — antepone ≈ si no es 'alta'


@dataclass
class FilaListaCompra:
    nombre: str
    categoria: str
    prioridad: int                # 1 agotado · 2 faltante · 3 sugerencia
    motivo: str
    cantidad_texto: str = ""
    precio_estimado: float = None


@dataclass
class DatosInventario:
    alimentos: list = field(default_factory=list)            # FilaAlimento, todo el catálogo activo
    lista_por_categoria: dict = field(default_factory=dict)   # {categoria: [FilaListaCompra]}
    total_estimado: float = None
    nota_lista: str = ""


CATEGORIAS = ["proteina", "grano", "verdura", "fruta", "lacteo", "grasa", "bebida", "otro"]

_ETIQUETA_PRIORIDAD = {1: "agotado", 2: "faltante", 3: "sugerencia"}
_COLOR_PRIORIDAD = {1: t.ALARMA, 2: t.AMBAR, 3: t.TENUE}

_ESTILO_CAMPO = dict(
    bgcolor=t.PANEL, color=t.BASE, border_color=t.LINEA,
    focused_border_color=t.VIVO, border_radius=t.RADIO, content_padding=10,
    text_size=t.BODY,
)


# ---------------------------------------------------------------------------
# Cabecera
# ---------------------------------------------------------------------------

def _cabecera() -> ft.Container:
    return ft.Container(
        content=t.etiqueta("inventario", color=t.BASE, size=t.CAPTION),
        padding=ft.padding.only(left=t.ESPACIO, right=t.ESPACIO, top=t.ESPACIO, bottom=4),
    )


# ---------------------------------------------------------------------------
# Formulario: agregar alimento nuevo al catálogo
# ---------------------------------------------------------------------------

def _bloque_agregar_alimento(on_agregar_alimento=None) -> ft.Container:
    campo_nombre = ft.TextField(label="nombre", **_ESTILO_CAMPO)
    campo_kcal = ft.TextField(label="kcal / 100 g", keyboard_type=ft.KeyboardType.NUMBER, **_ESTILO_CAMPO)
    campo_prot = ft.TextField(label="proteína g / 100 g", keyboard_type=ft.KeyboardType.NUMBER, **_ESTILO_CAMPO)
    campo_categoria = ft.Dropdown(
        label="categoría", value="otro",
        options=[ft.dropdown.Option(key=c, text=c) for c in CATEGORIAS],
        bgcolor=t.PANEL, color=t.BASE, border_color=t.LINEA, text_size=t.BODY,
    )

    def _enviar(e):
        if not on_agregar_alimento:
            return
        nombre = (campo_nombre.value or "").strip()
        try:
            kcal = float(campo_kcal.value)
            prot = float(campo_prot.value)
        except (TypeError, ValueError):
            return
        if not nombre:
            return
        on_agregar_alimento(nombre, kcal, prot, campo_categoria.value or "otro")

    return t.panel([
        t.texto("Solo nombre, kcal y proteína son obligatorios. El resto se completa después.",
               color=t.APAGADO, size=t.MICRO, no_wrap=False),
        campo_nombre, campo_kcal, campo_prot, campo_categoria,
        t.boton("agregar al catálogo", on_click=_enviar, primario=True),
    ], titulo="agregar alimento")


# ---------------------------------------------------------------------------
# Formulario: registrar compra
# ---------------------------------------------------------------------------

def _bloque_registrar_compra(alimentos: list, on_registrar_compra=None) -> ft.Container:
    campo_alimento = ft.Dropdown(
        label="alimento",
        options=[ft.dropdown.Option(key=a.nombre, text=a.nombre.replace("_", " ")) for a in alimentos],
        bgcolor=t.PANEL, color=t.BASE, border_color=t.LINEA, text_size=t.BODY,
    )
    campo_gramos = ft.TextField(label="gramos comprados", keyboard_type=ft.KeyboardType.NUMBER, **_ESTILO_CAMPO)
    campo_precio = ft.TextField(label="precio (opcional)", keyboard_type=ft.KeyboardType.NUMBER, **_ESTILO_CAMPO)

    def _enviar(e):
        if not on_registrar_compra:
            return
        nombre = campo_alimento.value
        try:
            gramos = float(campo_gramos.value)
        except (TypeError, ValueError):
            return
        if not nombre or gramos <= 0:
            return
        precio = None
        if campo_precio.value:
            try:
                precio = float(campo_precio.value)
            except ValueError:
                precio = None
        on_registrar_compra(nombre, gramos, precio)

    return t.panel([
        campo_alimento, campo_gramos, campo_precio,
        t.boton("registrar compra", on_click=_enviar, primario=True),
    ], titulo="registrar compra")


# ---------------------------------------------------------------------------
# Catálogo — gramos reales, editables
# ---------------------------------------------------------------------------

def _fila_alimento(a: FilaAlimento, on_ajustar_inventario=None) -> ft.Row:
    campo = ft.TextField(value=f"{a.gramos_disponibles:g}", width=64,
                         text_align=ft.TextAlign.RIGHT, **_ESTILO_CAMPO)

    def _guardar(e):
        if not on_ajustar_inventario:
            return
        try:
            nuevo = max(0.0, float(campo.value))
        except (TypeError, ValueError):
            return
        on_ajustar_inventario(a.nombre, nuevo)

    campo.on_submit = _guardar
    campo.on_blur = _guardar

    prefijo = t.texto("≈", color=t.APAGADO, size=t.MICRO) if a.confianza != "alta" else ft.Container(width=10)

    return ft.Row([
        prefijo,
        ft.Column([
            t.texto(a.nombre.replace("_", " "), color=t.BASE),
            t.texto(f"{a.kcal_100g:.0f} kcal · {a.proteina_100g:.1f} g / 100 g",
                    color=t.APAGADO, size=t.MICRO),
        ], spacing=1, tight=True, expand=True),
        campo,
        t.texto("g", color=t.TENUE, size=t.CAPTION),
    ], spacing=8, vertical_alignment=ft.CrossAxisAlignment.CENTER)


def _bloque_catalogo(d: DatosInventario, on_ajustar_inventario=None) -> ft.Container:
    if not d.alimentos:
        return t.panel([
            t.texto("El catálogo está vacío.", color=t.TENUE),
        ], titulo="catálogo")

    grupos = {}
    for a in d.alimentos:
        grupos.setdefault(a.categoria, []).append(a)

    contenido = []
    for categoria in sorted(grupos):
        contenido.append(t.etiqueta(categoria, color=t.APAGADO, size=t.MICRO))
        for a in sorted(grupos[categoria], key=lambda x: x.nombre):
            contenido.append(_fila_alimento(a, on_ajustar_inventario))
        contenido.append(t.separador())
    if contenido:
        contenido.pop()   # quita el último separador sobrante

    return t.panel(contenido, titulo="catálogo")


# ---------------------------------------------------------------------------
# Lista de compras
# ---------------------------------------------------------------------------

def _fila_lista_compra(linea: FilaListaCompra) -> ft.Row:
    color = _COLOR_PRIORIDAD.get(linea.prioridad, t.TENUE)
    return ft.Row([
        ft.Container(
            content=t.texto(_ETIQUETA_PRIORIDAD.get(linea.prioridad, "·"), color=color, size=t.MICRO),
            width=64,
        ),
        ft.Column([
            t.texto(linea.nombre.replace("_", " "), color=t.BASE),
            t.texto(linea.motivo, color=t.APAGADO, size=t.MICRO, no_wrap=False),
        ], spacing=1, tight=True, expand=True),
        ft.Column([
            t.texto(linea.cantidad_texto, color=t.TENUE, size=t.CAPTION),
            t.texto(f"~{linea.precio_estimado:.2f}", color=t.APAGADO, size=t.MICRO)
            if linea.precio_estimado is not None else ft.Container(),
        ], horizontal_alignment=ft.CrossAxisAlignment.END, spacing=1, tight=True),
    ], spacing=10, vertical_alignment=ft.CrossAxisAlignment.START)


def _bloque_lista_compras(d: DatosInventario):
    if not d.lista_por_categoria:
        return None

    contenido = []
    for categoria in sorted(d.lista_por_categoria):
        lineas = d.lista_por_categoria[categoria]
        if not lineas:
            continue
        contenido.append(t.etiqueta(categoria, color=t.APAGADO, size=t.MICRO))
        for linea in sorted(lineas, key=lambda l: l.prioridad):
            contenido.append(_fila_lista_compra(linea))
        contenido.append(t.separador())
    if not contenido:
        return None
    contenido.pop()

    if d.total_estimado is not None:
        contenido.append(ft.Row([
            t.etiqueta("total estimado", color=t.APAGADO),
            t.texto(f"{d.total_estimado:.2f}", color=t.VIVO, size=t.CAPTION,
                    weight=ft.FontWeight.W_600),
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN))
    if d.nota_lista:
        contenido.append(t.texto(d.nota_lista, color=t.APAGADO, size=t.MICRO, no_wrap=False))

    return t.panel(contenido, titulo="lista de compras")


# ---------------------------------------------------------------------------
# Vista
# ---------------------------------------------------------------------------

def vista(d: DatosInventario, on_agregar_alimento=None, on_registrar_compra=None,
         on_ajustar_inventario=None) -> ft.Control:
    """
    Callbacks, todos opcionales:
      on_agregar_alimento(nombre, kcal_100g, proteina_100g, categoria)
      on_registrar_compra(nombre, gramos, precio_o_None)
      on_ajustar_inventario(nombre, nuevos_gramos)   — al salir del campo o enviar
    """
    bloques = [
        _cabecera(),
        _bloque_lista_compras(d),
        _bloque_catalogo(d, on_ajustar_inventario),
        _bloque_registrar_compra(d.alimentos, on_registrar_compra),
        _bloque_agregar_alimento(on_agregar_alimento),
    ]
    bloques = [b for b in bloques if b is not None]

    columna = ft.Column(controls=bloques, spacing=t.ESPACIO, scroll=ft.ScrollMode.AUTO, expand=True)
    return ft.Container(content=columna, bgcolor=t.VOID, expand=True,
                        padding=ft.padding.only(left=t.ESPACIO, right=t.ESPACIO,
                                                bottom=t.ESPACIO * 2))
