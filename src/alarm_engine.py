"""
HumanOS — Motor de alarmas.

QUÉ SE PUEDE Y QUÉ NO
---------------------
Una alarma verdaderamente "imposible de desactivar" no existe en Android sin
permisos de administrador de dispositivo, que Play Store penaliza y que Flet
no expone. Lo que sí es alcanzable, en tres capas de fuerza decreciente:

  Capa 1 (fuerte, requiere extensión nativa):
      Notificación con importancia máxima + fullScreenIntent. En Android 14+
      necesita USE_FULL_SCREEN_INTENT y el permiso especial de alarmas exactas
      (SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM). Aparece sobre la pantalla de
      bloqueo. El usuario puede seguir descartándola desde el sistema.

  Capa 2 (garantizada, en la app):
      Al abrir la app, si hay una comida pendiente dentro de la ventana de
      gracia, se muestra un diálogo modal SIN salida que exige registrar la
      comida. Esto sí lo controlamos por completo.

  Capa 3 (contable):
      Toda comida no confirmada dentro de la ventana queda marcada como
      omitida y aparece en el historial. Lo que no se puede forzar, se mide.

Este módulo implementa las capas 2 y 3 completas, y la capa 1 detrás de una
interfaz que se activa sola si la extensión nativa está instalada.
"""

import datetime as dt
from dataclasses import dataclass

import config
import database as dbm


# ---------------------------------------------------------------------------
# Backend de notificaciones
# ---------------------------------------------------------------------------

class BackendNotificaciones:
    """Interfaz. Las implementaciones no deben lanzar excepciones nunca."""

    disponible = False

    def solicitar_permisos(self) -> bool:
        return False

    def programar(self, id_notif: int, titulo: str, cuerpo: str,
                  cuando: dt.datetime, diaria: bool = True) -> bool:
        return False

    def cancelar(self, id_notif: int) -> bool:
        return False

    def cancelar_todas(self) -> bool:
        return False


class BackendNulo(BackendNotificaciones):
    """
    Fallback silencioso. La app sigue funcionando por completo con las capas
    2 y 3; solo se pierde el aviso con la app cerrada.
    """
    disponible = False


class BackendFletNotifications(BackendNotificaciones):
    """
    Envoltorio sobre la extensión `flet_notifications`
    (que a su vez envuelve flutter_local_notifications).

    Se instancia solo si el import tiene éxito, por eso el import es local.
    """

    def __init__(self, page):
        self._page = page
        self._svc = None
        self.disponible = False
        try:
            import flet_notifications as fn  # noqa: F401
            self._fn = fn
            self._svc = fn.Notifications()
            page.overlay.append(self._svc)
            page.update()
            self.disponible = True
        except Exception:
            self._fn = None
            self.disponible = False

    def solicitar_permisos(self) -> bool:
        if not self.disponible:
            return False
        try:
            return bool(self._svc.request_permission())
        except Exception:
            return False

    def programar(self, id_notif, titulo, cuerpo, cuando, diaria=True) -> bool:
        if not self.disponible:
            return False
        try:
            self._svc.schedule(
                id=id_notif,
                title=titulo,
                body=cuerpo,
                scheduled_date=cuando,
                channel_id=config.CANAL_NOTIF_ID,
                channel_name=config.CANAL_NOTIF_NOMBRE,
                importance="max",
                full_screen_intent=True,
                repeat_daily=diaria,
            )
            return True
        except Exception:
            return False

    def cancelar(self, id_notif) -> bool:
        if not self.disponible:
            return False
        try:
            self._svc.cancel(id_notif)
            return True
        except Exception:
            return False

    def cancelar_todas(self) -> bool:
        if not self.disponible:
            return False
        try:
            self._svc.cancel_all()
            return True
        except Exception:
            return False


def crear_backend(page) -> BackendNotificaciones:
    backend = BackendFletNotifications(page)
    return backend if backend.disponible else BackendNulo()


# ---------------------------------------------------------------------------
# Lógica de programación (pura, sin dependencias de plataforma)
# ---------------------------------------------------------------------------

@dataclass
class Pendiente:
    comida: object
    registro: object
    programada: dt.datetime
    minutos_tarde: int
    vencida: bool          # fuera de la ventana de gracia
    exige_confirmacion: bool


def proxima_ocurrencia(hora: int, minuto: int,
                       ahora: dt.datetime = None) -> dt.datetime:
    """Siguiente vez que el reloj marque esa hora."""
    ahora = ahora or dt.datetime.now()
    objetivo = ahora.replace(hour=hora, minute=minuto, second=0, microsecond=0)
    if objetivo <= ahora:
        objetivo += dt.timedelta(days=1)
    return objetivo


def evaluar_pendientes(ahora: dt.datetime = None) -> list:
    """
    Comidas de hoy cuya hora ya pasó y que aún no se confirmaron.

    Ordenadas por antigüedad: la más atrasada primero, que es la que debe
    bloquear la pantalla.
    """
    ahora = ahora or dt.datetime.now()
    hoy = ahora.date()
    registros = dbm.registros_del_dia(hoy)
    pendientes = []

    for comida in dbm.comidas_ordenadas():
        programada = comida.hora_de(hoy)
        if programada > ahora:
            continue

        registro = registros.get(comida.id)
        if registro and (registro.confirmada_en or registro.omitida):
            continue

        minutos_tarde = int((ahora - programada).total_seconds() // 60)
        vencida = minutos_tarde > config.VENTANA_GRACIA_MIN

        alarma = comida.alarma.first() if hasattr(comida, "alarma") else None
        exige = bool(alarma and alarma.activa and alarma.tipo_dismiss == "confirmar")

        pendientes.append(Pendiente(
            comida=comida,
            registro=registro or dbm.registro_de(comida, hoy),
            programada=programada,
            minutos_tarde=minutos_tarde,
            vencida=vencida,
            exige_confirmacion=exige,
        ))

    pendientes.sort(key=lambda p: p.minutos_tarde, reverse=True)
    return pendientes


def pendiente_bloqueante(ahora: dt.datetime = None):
    """
    La comida que debe forzar el diálogo modal.

    Solo bloquea dentro de la ventana de gracia. Pasada esa ventana ya no
    tiene sentido exigir el registro de una comida que no ocurrió: se marca
    como omitida y se deja pasar. Bloquear indefinidamente convertiría la app
    en algo que se desinstala.
    """
    for p in evaluar_pendientes(ahora):
        if p.exige_confirmacion and not p.vencida:
            return p
    return None


def marcar_vencidas(ahora: dt.datetime = None) -> int:
    """Cierra como omitidas las comidas fuera de la ventana. Devuelve cuántas."""
    n = 0
    for p in evaluar_pendientes(ahora):
        if p.vencida and not p.registro.omitida:
            p.registro.omitida = True
            p.registro.save()
            n += 1
    return n


def confirmar(comida, kcal: float, proteina_g: float, detalle: str = "",
              fecha: dt.date = None):
    """Registra la comida y libera el bloqueo."""
    registro = dbm.registro_de(comida, fecha or dt.date.today())
    registro.kcal = kcal
    registro.proteina_g = proteina_g
    registro.detalle = detalle
    registro.confirmada_en = dt.datetime.now()
    registro.omitida = False
    registro.save()
    return registro


# ---------------------------------------------------------------------------
# Sincronización con el sistema
# ---------------------------------------------------------------------------

def reprogramar_todo(backend: BackendNotificaciones) -> int:
    """
    Vuelve a registrar todas las alarmas en el sistema.

    Se llama al iniciar la app y cada vez que cambia el horario. Android borra
    las alarmas al reiniciar el dispositivo, así que reprogramar en cada
    arranque no es redundante: es lo que las mantiene vivas.
    """
    if not backend.disponible:
        return 0

    backend.cancelar_todas()
    programadas = 0

    for comida in dbm.comidas_ordenadas():
        alarma = comida.alarma.first()
        if not alarma or not alarma.activa:
            continue

        cuando = proxima_ocurrencia(comida.hora, comida.minuto)
        if alarma.minutos_antes:
            cuando -= dt.timedelta(minutes=alarma.minutos_antes)

        ok = backend.programar(
            id_notif=comida.orden,
            titulo=f"Comida {comida.orden} — {comida.nombre}",
            cuerpo=f"{comida.hora_str} · {comida.contexto}. Toca para registrar.",
            cuando=cuando,
            diaria=True,
        )
        if ok:
            programadas += 1

    return programadas
