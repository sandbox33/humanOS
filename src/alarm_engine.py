"""
HumanOS — Motor de alarmas.

Traduce lo que presentador.py ya calculó (comidas, cocciones) en avisos:
qué falta confirmar, qué bloquea la navegación, qué cocción se está por
pasar, y notificaciones del sistema operativo cuando se puede. No
recalcula nada — eso ya lo hizo presentador.py vía los motores. Este
módulo solo lee ese resultado y decide CUÁNDO avisar, no CUÁNTO.

DEGRADACIÓN LIMPIA: flet_notifications no está en PyPI — se instala
desde su repo de GitHub (pip install git+https://github.com/Bbalduzz/
flet_notifications), así que puede faltar en el entorno de build si no
se agrega a pyproject.toml, o si el build no tiene acceso a GitHub. Si
falta, pendientes_ahora/hay_bloqueante/coccion_urgente siguen
funcionando igual (son puro cálculo) y el diálogo bloqueante sigue
apareciendo — lo único que se pierde es la notificación del sistema
operativo, nunca el aviso en pantalla.

API real de flet_notifications (confirmada contra el paquete instalado,
no de memoria): LocalNotifications() es un control no-visual que se
cuelga de page.overlay; .show_notification(id, title, body, payload=None,
actions=None) y .schedule_notification(id, title, body, scheduled_date,
...) son ambos async y devuelven bool.
"""

import datetime as dt

import config
import database as db
import presentador as pr
import theme as t
import flet as ft

try:
    from flet_notifications import LocalNotifications
    NOTIFICACIONES_DISPONIBLES = True
except ImportError:
    LocalNotifications = None
    NOTIFICACIONES_DISPONIBLES = False


_notificador = None   # instancia única de LocalNotifications, colgada del overlay al primer uso
_avisos_disparados: dict = {}   # {fecha: {id_evento_ya_notificado, ...}} — en memoria, no persiste reinicios


# ---------------------------------------------------------------------------
# Helpers — no reavisar lo mismo dos veces el mismo día
# ---------------------------------------------------------------------------

def _ya_avisado(fecha: dt.date, id_evento: str) -> bool:
    return id_evento in _avisos_disparados.get(fecha, set())


def _marcar_avisado(fecha: dt.date, id_evento: str) -> None:
    _avisos_disparados.setdefault(fecha, set()).add(id_evento)
    for f in list(_avisos_disparados):   # no acumular días viejos indefinidamente
        if f != fecha:
            del _avisos_disparados[f]


def reiniciar_avisos() -> None:
    """Para pruebas, o si se quiere forzar que todo vuelva a avisar."""
    _avisos_disparados.clear()


# ---------------------------------------------------------------------------
# Notificación del sistema — con degradación limpia
# ---------------------------------------------------------------------------

def _asegurar_notificador(page):
    global _notificador
    if not NOTIFICACIONES_DISPONIBLES:
        return None
    if _notificador is None:
        _notificador = LocalNotifications()
        page.overlay.append(_notificador)
    return _notificador


async def _notificar(page, id_evento: str, titulo: str, cuerpo: str) -> None:
    """No hace nada si flet_notifications no está — una notificación que
    falla no debe tumbar el ciclo de vigilancia, no es crítica."""
    notificador = _asegurar_notificador(page)
    if notificador is None:
        return
    try:
        await notificador.show_notification(id=abs(hash(id_evento)) % 1_000_000,
                                            title=titulo, body=cuerpo)
    except Exception:
        pass


# ---------------------------------------------------------------------------
# API mínima — lo que main.py va a llamar
# ---------------------------------------------------------------------------

def pendientes_ahora(fecha: dt.date = None) -> list:
    """Nombres de comidas que todavía hay que confirmar (pendiente o aviso)."""
    fecha = fecha or dt.date.today()
    datos = pr.datos_hoy(db.get_usuario(), fecha)
    return [c.nombre for c in datos.comidas if c.estado in ("pendiente", "aviso")]


def hay_bloqueante(fecha: dt.date = None) -> bool:
    """
    True solo si hay una comida DENTRO de la ventana de gracia (estado
    'aviso') sin confirmar. 'pendiente' (todavía no llega la hora) y
    'limite' (ya se pasó, quedó omitida) no bloquean — bloquear después
    de que ya no hay nada que hacer sería solo molestar sin motivo.
    """
    fecha = fecha or dt.date.today()
    datos = pr.datos_hoy(db.get_usuario(), fecha)
    return any(c.estado == "aviso" for c in datos.comidas)


_PRIORIDAD_NIVEL = {"limite": 2, "aviso": 1, "ok": 0}


def coccion_urgente():
    """La cocción abierta que más atención necesita ahora, o None si ninguna
    está en aviso/limite (evaluar_coccion() ya hizo ese cálculo)."""
    datos = pr.datos_hoy(db.get_usuario())
    urgentes = [c for c in datos.cocciones if c.nivel in ("aviso", "limite")]
    if not urgentes:
        return None
    return max(urgentes, key=lambda c: (_PRIORIDAD_NIVEL.get(c.nivel, 0), c.horas))


# ---------------------------------------------------------------------------
# Diálogo bloqueante
# ---------------------------------------------------------------------------

def _dialogo_ya_abierto(page) -> bool:
    d = getattr(page, "dialog", None)
    return bool(d is not None and getattr(d, "open", False) and
               getattr(d, "data", None) == "humanos_bloqueante")


def _mostrar_dialogo_bloqueante(page, comidas_en_aviso: list) -> None:
    if _dialogo_ya_abierto(page):
        return   # ya está mostrándose este ciclo, no lo reconstruye

    nombres = ", ".join(c.nombre for c in comidas_en_aviso)

    def _cerrar(e):
        dialogo.open = False
        page.update()

    dialogo = ft.AlertDialog(
        modal=True,
        bgcolor=t.PANEL,
        title=t.texto(f"{nombres} sin confirmar", color=t.BASE, size=t.BODY),
        content=t.texto(
            "Estás dentro de la ventana de gracia de 90 minutos. "
            "Confírmala en Comidas antes de que se pase.",
            color=t.TENUE, size=t.CAPTION, no_wrap=False,
        ),
        actions=[t.boton("entendido", on_click=_cerrar)],
        data="humanos_bloqueante",   # marca para reconocer ESTE diálogo en el próximo ciclo
    )
    page.dialog = dialogo
    dialogo.open = True
    page.update()


# ---------------------------------------------------------------------------
# Ciclo de vigilancia
# ---------------------------------------------------------------------------

async def verificar_y_alertar(page) -> None:
    """
    Pensado para llamarse periódicamente desde main.py (paso 7) — un
    ft.Timer o similar, no más seguido que cada 1-2 minutos. Revisa
    comidas en ventana de gracia, cocciones urgentes y suplementos
    vencidos; dispara UNA notificación por evento nuevo (no reavisa lo
    que ya avisó hoy, ver _ya_avisado) y muestra el diálogo bloqueante
    si corresponde.
    """
    fecha = dt.date.today()
    usuario = db.get_usuario()
    datos = pr.datos_hoy(usuario, fecha)

    # 1. Comidas en ventana de gracia
    en_aviso = [c for c in datos.comidas if c.estado == "aviso"]
    for c in en_aviso:
        id_evento = f"comida:{fecha}:{c.orden}"
        if not _ya_avisado(fecha, id_evento):
            await _notificar(page, id_evento, f"{c.nombre} sin confirmar",
                            "Dentro de la ventana de gracia — confírmala pronto.")
            _marcar_avisado(fecha, id_evento)
    if en_aviso:
        _mostrar_dialogo_bloqueante(page, en_aviso)

    # 2. Cocción urgente
    coccion = coccion_urgente()
    if coccion:
        id_evento = f"coccion:{fecha}:{coccion.nombre}:{coccion.nivel}"
        if not _ya_avisado(fecha, id_evento):
            titulo = "Cocción por vencer" if coccion.nivel == "aviso" else "Cocción vencida"
            await _notificar(page, id_evento, titulo, coccion.mensaje)
            _marcar_avisado(fecha, id_evento)

    # 3. Suplementos vencidos sin tomar — suplementos_pendientes_hoy() ya
    # filtra por hora, acá solo falta no repetir el aviso.
    for s in db.suplementos_pendientes_hoy():
        id_evento = f"suplemento:{fecha}:{s.nombre}"
        if not _ya_avisado(fecha, id_evento):
            await _notificar(page, id_evento, s.nombre, s.notas or "Hora de tomarlo.")
            _marcar_avisado(fecha, id_evento)
