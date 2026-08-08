"""
HumanOS — Capa de datos (SQLite + Peewee).

Peewee es Python puro: no requiere wheels precompiladas para Android,
que es exactamente lo que necesita `flet build apk`.
"""

import os
import datetime as dt

from peewee import (
    SqliteDatabase, Model,
    AutoField, CharField, FloatField, IntegerField,
    BooleanField, DateField, DateTimeField, ForeignKeyField, TextField,
)

import config


def _ruta_db() -> str:
    """
    Resuelve dónde vive la base de datos.

    En Android, Flet expone FLET_APP_STORAGE_DATA (almacenamiento privado de
    la app, persiste entre reinicios y no se borra con la caché).
    En escritorio cae a ./data/.
    """
    base = os.getenv("FLET_APP_STORAGE_DATA")
    if not base:
        base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
    os.makedirs(base, exist_ok=True)
    return os.path.join(base, "humanos.db")


db = SqliteDatabase(
    _ruta_db(),
    pragmas={
        "journal_mode": "wal",      # sobrevive a cierres abruptos de la app
        "foreign_keys": 1,
        "synchronous": 1,
    },
)


class BaseModel(Model):
    class Meta:
        database = db


# ---------------------------------------------------------------------------
# Modelos
# ---------------------------------------------------------------------------

class Usuario(BaseModel):
    id = AutoField()
    peso_kg = FloatField(default=config.DEFAULT_PESO_KG)
    estatura_cm = FloatField(default=config.DEFAULT_ESTATURA_CM)
    edad = IntegerField(default=config.DEFAULT_EDAD)
    nivel_actividad = CharField(default=config.DEFAULT_ACTIVIDAD)
    superavit_pct = FloatField(default=config.SUPERAVIT_PCT)
    proteina_g_por_kg = FloatField(default=config.PROTEINA_G_POR_KG)
    num_comidas = IntegerField(default=5)
    actualizado = DateTimeField(default=dt.datetime.now)


class Comida(BaseModel):
    """Plantilla de comida: define el horario, no un evento concreto."""
    id = AutoField()
    orden = IntegerField(unique=True)
    nombre = CharField()
    hora = IntegerField()
    minuto = IntegerField()
    peso_calorico = FloatField()
    contexto = CharField(default="")
    activa = BooleanField(default=True)

    @property
    def hora_str(self) -> str:
        return f"{self.hora:02d}:{self.minuto:02d}"

    def hora_de(self, dia: dt.date) -> dt.datetime:
        return dt.datetime.combine(dia, dt.time(self.hora, self.minuto))


class AlarmaConfig(BaseModel):
    """Configuración de alarma por comida."""
    id = AutoField()
    comida = ForeignKeyField(Comida, backref="alarma", unique=True,
                             on_delete="CASCADE")
    activa = BooleanField(default=True)
    # 'confirmar' exige registrar la comida para descartar.
    # 'simple' se descarta con un toque.
    tipo_dismiss = CharField(default="confirmar")
    vibrar = BooleanField(default=True)
    minutos_antes = IntegerField(default=0)


class RegistroComida(BaseModel):
    """Evento real: qué se comió, cuándo, y si se confirmó."""
    id = AutoField()
    comida = ForeignKeyField(Comida, backref="registros", on_delete="CASCADE")
    fecha = DateField(default=dt.date.today)
    kcal = FloatField(default=0.0)
    proteina_g = FloatField(default=0.0)
    detalle = TextField(default="")
    confirmada_en = DateTimeField(null=True)
    omitida = BooleanField(default=False)

    class Meta:
        indexes = ((("comida", "fecha"), True),)


MODELOS = [Usuario, Comida, AlarmaConfig, RegistroComida]


# ---------------------------------------------------------------------------
# Inicialización
# ---------------------------------------------------------------------------

def init_db() -> Usuario:
    """Crea tablas y siembra datos base. Idempotente."""
    db.connect(reuse_if_open=True)
    db.create_tables(MODELOS)

    usuario = Usuario.select().first()
    if usuario is None:
        usuario = Usuario.create()

    if Comida.select().count() == 0:
        for orden, nombre, hora, minuto, peso, contexto in config.HORARIO_COMIDAS:
            comida = Comida.create(
                orden=orden, nombre=nombre, hora=hora, minuto=minuto,
                peso_calorico=peso, contexto=contexto,
            )
            AlarmaConfig.create(comida=comida)

    return usuario


def get_usuario() -> Usuario:
    usuario = Usuario.select().first()
    return usuario if usuario else Usuario.create()


def comidas_ordenadas():
    return list(Comida.select().where(Comida.activa == True).order_by(Comida.orden))


def registro_de(comida: Comida, fecha: dt.date = None) -> RegistroComida:
    """Devuelve (creando si hace falta) el registro de una comida en un día."""
    fecha = fecha or dt.date.today()
    registro, _ = RegistroComida.get_or_create(comida=comida, fecha=fecha)
    return registro


def registros_del_dia(fecha: dt.date = None):
    fecha = fecha or dt.date.today()
    return {r.comida_id: r for r in
            RegistroComida.select().where(RegistroComida.fecha == fecha)}


def totales_del_dia(fecha: dt.date = None) -> dict:
    fecha = fecha or dt.date.today()
    kcal = prot = 0.0
    confirmadas = 0
    for r in RegistroComida.select().where(RegistroComida.fecha == fecha):
        if r.confirmada_en:
            kcal += r.kcal
            prot += r.proteina_g
            confirmadas += 1
    return {"kcal": kcal, "proteina_g": prot, "confirmadas": confirmadas}


def historial(dias: int = 14):
    """Totales diarios de los últimos N días, más reciente primero."""
    hoy = dt.date.today()
    salida = []
    for i in range(dias):
        f = hoy - dt.timedelta(days=i)
        t = totales_del_dia(f)
        t["fecha"] = f
        salida.append(t)
    return salida


def cerrar():
    if not db.is_closed():
        db.close()
