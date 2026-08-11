"""
HumanOS — main.py

Lo último: arranque, navegación de 5 pestañas y el cableado de cada
callback de cada vista hacia presentador.py / database.py. No calcula
nada — cada _vista_X() de aquí abajo pide datos ya resueltos a
presentador.py y le pasa a la vista funciones que, cuando se llaman,
escriben en la base y piden que se vuelva a renderizar. Este archivo es
el único que conoce las 5 pestañas y cómo se navega entre ellas; ninguna
vista sabe que las otras existen.

ESTADO DE SESIÓN (EstadoApp): qué pestaña está activa, qué comida está
expandida en Comidas, y los borradores de gramos/extras que el usuario
ajustó antes de confirmar. Nada de esto vive en la base de datos — se
pierde si se cierra la app, y así debe ser: es UI, no datos.

INVENTARIO no es una de las 5 pestañas (el prompt de ignición solo
nombra Hoy/Comidas/Hábitos/Sueño/Perfil) — se llega por un atajo en la
barra superior, visible en cualquier pestaña, porque es la pantalla que
menos se usa a diario pero conviene tener a mano mientras se cocina.
"""

import asyncio
import datetime as dt

import flet as ft

import config
import database as db
import presentador as pr
import theme as t
import alarm_engine as ae

from views import hoy as vhoy
from views import comidas as vcomidas
from views import habitos as vhabitos
from views import inventario as vinventario
from views import sueno as vsueno
from views import perfil as vperfil


# ---------------------------------------------------------------------------
# Estado de sesión — no persiste, es de la UI, no de la base
# ---------------------------------------------------------------------------

class EstadoApp:
    def __init__(self):
        self.tab = 0                  # 0-4 (las 5 pestañas) o "inventario" (pantalla sin ícono en la barra)
        self.tab_anterior = 0         # a dónde vuelve 'volver' desde inventario
        self.foco_comida = None       # orden de la comida expandida en Comidas; se calcula la primera vez
        self.ediciones: dict = {}     # {orden: {nombre: gramos}} — borrador de gramos editados
        self.extras: dict = {}        # {orden: {nombre: gramos}} — borrador de extras agregados


def _foco_comida_por_defecto(usuario: db.Usuario) -> int:
    datos = pr.datos_hoy(usuario)
    primera = next((c for c in datos.comidas if c.estado in ("pendiente", "aviso")), None)
    return primera.orden if primera else 1


# ---------------------------------------------------------------------------
# Hoy
# ---------------------------------------------------------------------------

def _vista_hoy(page, estado: EstadoApp, refrescar) -> ft.Control:
    usuario = db.get_usuario()
    datos = pr.datos_hoy(usuario)

    def _on_registrar(orden):
        estado.tab = 1
        estado.foco_comida = orden
        refrescar()

    def _on_marcar_habito(nombre):
        # hoy.py solo manda el nombre (pantalla resumen) — acá se decide el
        # valor nuevo, igual criterio que el toggle de views/habitos.py.
        fila = next((h for h in datos.habitos if h.nombre == nombre), None)
        h_db = next((h for h in db.habitos_activos() if h.nombre == nombre), None)
        if not fila or not h_db:
            return
        nuevo_valor = 0.0 if fila.cumplido else (h_db.valor_objetivo or 1.0)
        db.registrar_habito(h_db, valor=nuevo_valor)
        refrescar()

    return vhoy.vista(datos, on_registrar=_on_registrar, on_marcar_habito=_on_marcar_habito)


# ---------------------------------------------------------------------------
# Comidas
# ---------------------------------------------------------------------------

def _vista_comidas(page, estado: EstadoApp, refrescar) -> ft.Control:
    usuario = db.get_usuario()
    fecha = dt.date.today()
    orden = estado.foco_comida or _foco_comida_por_defecto(usuario)
    estado.foco_comida = orden

    ediciones = estado.ediciones.get(orden, {})
    extras = estado.extras.get(orden, {})
    datos = pr.datos_comidas(usuario, fecha, orden, ediciones=ediciones, extras_agregados=extras)

    def _on_expandir(nuevo_orden):
        estado.foco_comida = nuevo_orden
        refrescar()

    def _on_cambiar_gramos(o, nombre, gramos):
        estado.ediciones.setdefault(o, {})[nombre] = max(0.0, gramos)
        refrescar()

    def _on_agregar_extra(o, nombre, gramos_sugeridos):
        estado.extras.setdefault(o, {})[nombre] = gramos_sugeridos
        refrescar()

    def _on_quitar(o, nombre):
        # si es un extra agregado en esta sesión, se saca del todo; si es
        # parte de la sugerencia del motor, se deja en 0 g (armar_combinacion
        # no tiene un mecanismo de "excluir este alimento").
        if nombre in estado.extras.get(o, {}):
            estado.extras[o].pop(nombre, None)
        else:
            estado.ediciones.setdefault(o, {})[nombre] = 0.0
        refrescar()

    def _on_confirmar(o):
        fresco = pr.datos_comidas(usuario, fecha, o, ediciones=estado.ediciones.get(o, {}),
                                  extras_agregados=estado.extras.get(o, {}))
        items = {f.nombre: f.gramos for f in (fresco.ingredientes + fresco.extras) if f.gramos > 0}
        comida_obj = next((c for c in db.comidas_ordenadas() if c.orden == o), None)
        if comida_obj:
            db.confirmar_consumo(comida_obj, items, fecha)
        estado.ediciones.pop(o, None)
        estado.extras.pop(o, None)
        refrescar()

    return vcomidas.vista(datos, on_expandir=_on_expandir, on_cambiar_gramos=_on_cambiar_gramos,
                          on_agregar_extra=_on_agregar_extra, on_quitar=_on_quitar,
                          on_confirmar=_on_confirmar)


# ---------------------------------------------------------------------------
# Hábitos
# ---------------------------------------------------------------------------

def _vista_habitos(page, estado: EstadoApp, refrescar) -> ft.Control:
    usuario = db.get_usuario()
    datos = pr.datos_habitos(usuario)

    def _on_marcar(nombre, valor):
        h = next((x for x in db.habitos_activos() if x.nombre == nombre), None)
        if h:
            db.registrar_habito(h, valor=valor)
        refrescar()

    def _on_crear_habito(nombre, tipo, metrica, tipo_objetivo, valor_objetivo, esencial):
        db.crear_habito(nombre=nombre, tipo=tipo, metrica=metrica, tipo_objetivo=tipo_objetivo,
                        valor_objetivo=valor_objetivo, esencial=esencial)
        refrescar()

    return vhabitos.vista(datos, on_marcar=_on_marcar, on_crear_habito=_on_crear_habito)


# ---------------------------------------------------------------------------
# Inventario — sin pestaña propia, se llega por el atajo de la barra superior
# ---------------------------------------------------------------------------

def _vista_inventario(page, estado: EstadoApp, refrescar) -> ft.Control:
    datos = pr.datos_inventario()

    def _on_agregar_alimento(nombre, kcal, prot, categoria):
        db.agregar_alimento(nombre, kcal, prot, categoria=categoria)
        refrescar()

    def _on_registrar_compra(nombre, gramos, precio):
        a = db.alimento(nombre)
        if a:
            db.registrar_compra(a, gramos, precio=precio)
        refrescar()

    def _on_ajustar_inventario(nombre, nuevos_gramos):
        a = db.alimento(nombre)
        if a:
            db.set_inventario(a, nuevos_gramos)
        refrescar()

    return vinventario.vista(datos, on_agregar_alimento=_on_agregar_alimento,
                             on_registrar_compra=_on_registrar_compra,
                             on_ajustar_inventario=_on_ajustar_inventario)


# ---------------------------------------------------------------------------
# Sueño
# ---------------------------------------------------------------------------

def _vista_sueno(page, estado: EstadoApp, refrescar) -> ft.Control:
    usuario = db.get_usuario()
    datos = pr.datos_sueno(usuario)

    def _on_dormir():
        db.dormir_ahora()
        refrescar()

    def _on_despertar():
        db.despertar_ahora()
        refrescar()

    return vsueno.vista(datos, on_dormir=_on_dormir, on_despertar=_on_despertar)


# ---------------------------------------------------------------------------
# Perfil
# ---------------------------------------------------------------------------

def _vista_perfil(page, estado: EstadoApp, refrescar) -> ft.Control:
    usuario = db.get_usuario()
    datos = pr.datos_perfil(usuario)

    def _on_guardar_perfil(peso, estatura, edad, nivel_actividad, superavit_pct, prot_g_kg):
        u = db.get_usuario()
        u.peso_kg, u.estatura_cm, u.edad = peso, estatura, edad
        u.nivel_actividad = nivel_actividad
        u.superavit_pct, u.proteina_g_por_kg = superavit_pct, prot_g_kg
        u.save()
        refrescar()

    def _on_guardar_jornada(he, me, hs, ms, ha, ma, dia_libre):
        db.registrar_jornada(hora_entrada=he, minuto_entrada=me, hora_salida=hs,
                             minuto_salida=ms, hora_almuerzo=ha, minuto_almuerzo=ma,
                             dia_libre=dia_libre)
        refrescar()

    def _on_editar_supuesto(clave, nuevo_valor):
        # vive en memoria del proceso, no se guarda en disco — config.py es
        # código fuente, no un registro editable. Se resetea a lo que diga
        # el archivo en el próximo arranque; documentado, no es un bug.
        if clave in config.SUPUESTOS:
            config.SUPUESTOS[clave]["valor"] = nuevo_valor
        refrescar()

    def _on_marcar_suplemento(nombre):
        s = next((x for x in db.suplementos_activos() if x.nombre == nombre), None)
        if s:
            db.marcar_suplemento_tomado(s)
        refrescar()

    return vperfil.vista(datos, on_guardar_perfil=_on_guardar_perfil,
                         on_guardar_jornada=_on_guardar_jornada,
                         on_editar_supuesto=_on_editar_supuesto,
                         on_marcar_suplemento=_on_marcar_suplemento)


# ---------------------------------------------------------------------------
# Armazón: barra superior, navegación, despacho por pestaña
# ---------------------------------------------------------------------------

def _barra_superior(estado: EstadoApp, refrescar) -> ft.Container:
    if estado.tab == "inventario":
        def _volver(e):
            estado.tab = estado.tab_anterior if isinstance(estado.tab_anterior, int) else 0
            refrescar()
        derecha = ft.Container(content=t.texto("◂ volver", color=t.TENUE, size=t.MICRO),
                               on_click=_volver, ink=False, padding=6)
    else:
        def _ir_a_inventario(e):
            estado.tab_anterior = estado.tab
            estado.tab = "inventario"
            refrescar()
        derecha = ft.Container(content=t.texto("▤ inventario", color=t.TENUE, size=t.MICRO),
                               on_click=_ir_a_inventario, ink=False, padding=6)

    return ft.Container(
        content=ft.Row([
            t.texto("humanOS", color=t.TENUE, size=t.MICRO),
            ft.Container(expand=True),
            derecha,
        ], alignment=ft.MainAxisAlignment.SPACE_BETWEEN),
        padding=ft.padding.symmetric(horizontal=t.ESPACIO, vertical=6),
        bgcolor=t.PANEL,
        border=ft.border.only(bottom=ft.BorderSide(t.BORDE, t.LINEA)),
    )


_DESTINOS = [(0, "⌂", "hoy"), (1, "▣", "comidas"), (2, "◈", "hábitos"),
            (3, "☾", "sueño"), (4, "◇", "perfil")]


def _glifo_nav(caracter: str, color: str) -> ft.Text:
    return ft.Text(caracter, size=20, color=color, font_family=t.MONO)


def _barra_navegacion(estado: EstadoApp, cambiar_tab) -> ft.NavigationBar:
    destinos = [
        ft.NavigationBarDestination(icon=_glifo_nav(g, t.APAGADO),
                                    selected_icon=_glifo_nav(g, t.VIVO), label=nombre)
        for _i, g, nombre in _DESTINOS
    ]
    idx = estado.tab if isinstance(estado.tab, int) else 0
    return ft.NavigationBar(
        destinations=destinos, selected_index=idx,
        bgcolor=t.PANEL, indicator_color=t.LINEA,
        on_change=lambda e: cambiar_tab(e.control.selected_index),
    )


def _contenido_por_tab(page, estado: EstadoApp, refrescar) -> ft.Control:
    if estado.tab == "inventario":
        return _vista_inventario(page, estado, refrescar)
    despacho = {0: _vista_hoy, 1: _vista_comidas, 2: _vista_habitos,
               3: _vista_sueno, 4: _vista_perfil}
    fn = despacho.get(estado.tab, _vista_hoy)
    return fn(page, estado, refrescar)


# ---------------------------------------------------------------------------
# Vigilante en segundo plano
# ---------------------------------------------------------------------------

async def _vigilar(page) -> None:
    """No más de una vez por minuto — alarm_engine ya evita reavisar lo
    mismo, esto solo evita gastar ciclos revisando más seguido de lo útil."""
    while True:
        try:
            await ae.verificar_y_alertar(page)
        except Exception:
            pass   # un ciclo fallido no debe tumbar la app
        await asyncio.sleep(60)


# ---------------------------------------------------------------------------
# Arranque
# ---------------------------------------------------------------------------

async def main(page: ft.Page) -> None:
    db.init_db()
    t.aplicar_tema(page)

    estado = EstadoApp()
    barra_superior = ft.Container()
    area = ft.Container(expand=True)

    def refrescar():
        barra_superior.content = _barra_superior(estado, refrescar)
        area.content = _contenido_por_tab(page, estado, refrescar)
        if isinstance(estado.tab, int):
            nav.selected_index = estado.tab
        page.update()

    def cambiar_tab(idx):
        estado.tab = idx
        refrescar()

    nav = _barra_navegacion(estado, cambiar_tab)
    page.navigation_bar = nav
    page.add(ft.Column([barra_superior, area], spacing=0, expand=True))

    refrescar()
    page.run_task(_vigilar, page)


if __name__ == "__main__":
    ft.app(target=main, assets_dir="assets")
