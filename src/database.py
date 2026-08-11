"""
HumanOS — Capa de datos (SQLite + Peewee).

CAMBIO DE ARQUITECTURA vs v1: los alimentos ya no viven en un diccionario
fijo en config.py. Son una tabla editable (Alimento), y cuánto tienes de
cada uno es otra tabla (InventarioItem) que se descuenta al confirmar una
comida. El motor de combinaciones (nutrition_engine.py, siguiente archivo)
solo puede sugerir con lo que el inventario dice que existe — por eso ya
no va a sugerir yogurt si no lo tienes.

RegistroComida ya no guarda kcal/proteína como texto suelto: se calcula
desde ConsumoItem (qué alimento, cuántos gramos, en qué comida). Eso hace
que el inventario y el historial sean la misma fuente de verdad.
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
    En Android, Flet expone FLET_APP_STORAGE_DATA (almacenamiento privado
    de la app, persiste entre reinicios). En escritorio cae a ./data/.
    """
    base = os.getenv("FLET_APP_STORAGE_DATA")
    if not base:
        base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
    os.makedirs(base, exist_ok=True)
    return os.path.join(base, "humanos.db")


db = SqliteDatabase(
    _ruta_db(),
    pragmas={"journal_mode": "wal", "foreign_keys": 1, "synchronous": 1},
)


class BaseModel(Model):
    class Meta:
        database = db


# ---------------------------------------------------------------------------
# Perfil
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


# ---------------------------------------------------------------------------
# Alimentos e inventario
# ---------------------------------------------------------------------------

class Alimento(BaseModel):
    """
    Catálogo de alimentos. Editable desde la app — no es una lista fija.

    Los micronutrientes están aquí para que las interacciones se calculen
    con números, no con etiquetas: 'esta comida tiene 4.2 mg de hierro
    no-hemo y 89 mg de vitamina C' es más útil que 'tiene la etiqueta
    legumbres'. Permite además detectar combinaciones BUENAS, no solo
    advertencias.

    Cualquier campo puede ser null. Un dato ausente se trata como
    desconocido, nunca como cero — ver `confianza`.
    """
    id = AutoField()
    nombre = CharField(unique=True)
    kcal_100g = FloatField()
    proteina_100g = FloatField()

    # Macros
    grasa_100g = FloatField(null=True)
    carb_100g = FloatField(null=True)
    fibra_100g = FloatField(null=True)

    # Micros que participan en interacciones reales
    hierro_mg_100g = FloatField(null=True)
    hierro_es_hemo = BooleanField(default=False)  # animal = hemo, se absorbe mucho mejor
    calcio_mg_100g = FloatField(null=True)
    zinc_mg_100g = FloatField(null=True)
    vitc_mg_100g = FloatField(null=True)
    b12_mcg_100g = FloatField(null=True)
    sodio_mg_100g = FloatField(null=True)

    # Inhibición de hierro no-hemo. Campo explícito y no una etiqueta: si
    # dependiera de recordar poner "polifenoles" al crear un alimento, un
    # olvido apagaría la advertencia en silencio.
    inhibe_hierro_no_hemo = BooleanField(default=False)
    polifenoles_mg_100g = FloatField(null=True)   # opcional, casi nunca en tablas

    # Confianza del dato nutricional: 'alta' | 'media' | 'baja'
    # Si no tienes el valor real, no inventes uno — déjalo null y marca baja.
    confianza = CharField(default="media")

    # Compras
    categoria = CharField(default="otro")      # proteina|grano|verdura|fruta|lacteo|grasa|bebida|otro
    unidad_compra = CharField(default="g")     # g|kg|unidad|lata|paquete|libra
    gramos_por_unidad = FloatField(null=True)  # p.ej. 1 lata de atún = 140 g
    costo_referencia = FloatField(null=True)   # último precio conocido por unidad_compra
    etiquetas_csv = CharField(default="")
    activo = BooleanField(default=True)

    @property
    def etiquetas(self) -> set:
        return {t for t in self.etiquetas_csv.split(",") if t}

    @etiquetas.setter
    def etiquetas(self, valores):
        self.etiquetas_csv = ",".join(sorted(set(valores)))

    def macros(self, gramos: float) -> dict:
        f = gramos / 100.0
        return {"kcal": self.kcal_100g * f, "proteina_g": self.proteina_100g * f}

    def nutrientes(self, gramos: float) -> dict:
        """Todos los nutrientes para N gramos. Los null quedan fuera del dict."""
        f = gramos / 100.0
        campos = {
            "kcal": self.kcal_100g, "proteina_g": self.proteina_100g,
            "grasa_g": self.grasa_100g, "carb_g": self.carb_100g,
            "fibra_g": self.fibra_100g, "hierro_mg": self.hierro_mg_100g,
            "calcio_mg": self.calcio_mg_100g, "zinc_mg": self.zinc_mg_100g,
            "vitc_mg": self.vitc_mg_100g, "b12_mcg": self.b12_mcg_100g,
            "sodio_mg": self.sodio_mg_100g,
            "polifenoles_mg": self.polifenoles_mg_100g,
        }
        return {k: v * f for k, v in campos.items() if v is not None}


class InventarioItem(BaseModel):
    """Cuánto hay AHORA de cada alimento. Se descuenta al confirmar comidas."""
    id = AutoField()
    alimento = ForeignKeyField(Alimento, backref="inventario", unique=True,
                               on_delete="CASCADE")
    gramos_disponibles = FloatField(default=0.0)
    actualizado = DateTimeField(default=dt.datetime.now)


class Compra(BaseModel):
    """
    Historial de compras. De aquí sale qué compras seguido y a qué precio,
    sin que tengas que declararlo — se deduce de lo que registras.
    El precio es opcional: sin él, la frecuencia sigue siendo útil.
    """
    id = AutoField()
    alimento = ForeignKeyField(Alimento, backref="compras", on_delete="CASCADE")
    fecha = DateField(default=dt.date.today)
    gramos = FloatField()
    precio = FloatField(null=True)     # total pagado por esos gramos
    lugar = CharField(default="")

    @property
    def precio_por_100g(self):
        if self.precio is None or not self.gramos:
            return None
        return round(self.precio / self.gramos * 100, 4)


# ---------------------------------------------------------------------------
# Horario de comidas y alarmas
# ---------------------------------------------------------------------------

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
    id = AutoField()
    comida = ForeignKeyField(Comida, backref="alarma", unique=True,
                             on_delete="CASCADE")
    activa = BooleanField(default=True)
    tipo_dismiss = CharField(default="confirmar")   # 'confirmar' | 'simple'
    vibrar = BooleanField(default=True)
    minutos_antes = IntegerField(default=0)


# ---------------------------------------------------------------------------
# Registro real de consumo
# ---------------------------------------------------------------------------

class RegistroComida(BaseModel):
    """Evento: esta Comida, en esta fecha, ¿se confirmó?"""
    id = AutoField()
    comida = ForeignKeyField(Comida, backref="registros", on_delete="CASCADE")
    fecha = DateField(default=dt.date.today)
    confirmada_en = DateTimeField(null=True)
    omitida = BooleanField(default=False)

    class Meta:
        indexes = ((("comida", "fecha"), True),)

    def totales(self) -> dict:
        """kcal y proteína reales, sumadas desde lo que de verdad se comió."""
        kcal = prot = 0.0
        for item in self.consumo:
            m = item.alimento.macros(item.gramos)
            kcal += m["kcal"]
            prot += m["proteina_g"]
        return {"kcal": kcal, "proteina_g": prot}


class ConsumoItem(BaseModel):
    """Qué se comió exactamente en un RegistroComida — alimento + gramos."""
    id = AutoField()
    registro = ForeignKeyField(RegistroComida, backref="consumo", on_delete="CASCADE")
    alimento = ForeignKeyField(Alimento, on_delete="RESTRICT")
    gramos = FloatField()


# ---------------------------------------------------------------------------
# Suplementos (complejo B, etc.)
# ---------------------------------------------------------------------------

class Suplemento(BaseModel):
    id = AutoField()
    nombre = CharField(unique=True)
    hora = IntegerField()
    minuto = IntegerField()
    notas = TextField(default="")
    activo = BooleanField(default=True)

    @property
    def hora_str(self) -> str:
        return f"{self.hora:02d}:{self.minuto:02d}"


class SuplementoLog(BaseModel):
    id = AutoField()
    suplemento = ForeignKeyField(Suplemento, backref="registros", on_delete="CASCADE")
    fecha = DateField(default=dt.date.today)
    tomado_en = DateTimeField(null=True)

    class Meta:
        indexes = ((("suplemento", "fecha"), True),)


# ---------------------------------------------------------------------------
# Sueño real (no solo calculadora de ciclos)
# ---------------------------------------------------------------------------

class SueñoLog(BaseModel):
    """Una fila por noche. fecha = fecha del día en que empezó la noche."""
    id = AutoField()
    fecha = DateField(unique=True, default=dt.date.today)
    hora_dormir_real = DateTimeField(null=True)
    hora_despertar_real = DateTimeField(null=True)

    @property
    def horas_dormidas(self):
        if self.hora_dormir_real and self.hora_despertar_real:
            delta = self.hora_despertar_real - self.hora_dormir_real
            return round(delta.total_seconds() / 3600, 2)
        return None


# ---------------------------------------------------------------------------
# Jornada laboral — variable día a día
# ---------------------------------------------------------------------------
# El horario de comidas NO es fijo: depende de a qué hora entraste ese día.
# Sin esto, la app asume 7:00 siempre y las alarmas quedan corridas.

class Jornada(BaseModel):
    id = AutoField()
    fecha = DateField(unique=True, default=dt.date.today)
    hora_entrada = IntegerField(null=True)
    minuto_entrada = IntegerField(default=0)
    hora_salida = IntegerField(null=True)
    minuto_salida = IntegerField(default=0)
    dia_libre = BooleanField(default=False)
    # Inicio real del receso de almuerzo (variable 12:00-13:00)
    hora_almuerzo = IntegerField(null=True)
    minuto_almuerzo = IntegerField(default=0)

    @property
    def entrada_str(self):
        if self.hora_entrada is None:
            return "—"
        return f"{self.hora_entrada:02d}:{self.minuto_entrada:02d}"

    @property
    def salida_str(self):
        if self.hora_salida is None:
            return "—"
        return f"{self.hora_salida:02d}:{self.minuto_salida:02d}"


# ---------------------------------------------------------------------------
# Cocción — ventana de seguridad sin refrigeración
# ---------------------------------------------------------------------------
# Bacillus cereus: las esporas sobreviven la cocción y germinan a
# temperatura ambiente. La toxina emética que producen es termoestable —
# recalentar NO la destruye. Por eso el reloj corre desde que se cocinó,
# no desde que se recalentó.

class Coccion(BaseModel):
    id = AutoField()
    alimento = ForeignKeyField(Alimento, backref="cocciones", on_delete="CASCADE")
    cocinado_en = DateTimeField(default=dt.datetime.now)
    gramos = FloatField(default=0.0)
    consumido = BooleanField(default=False)
    descartado = BooleanField(default=False)

    @property
    def horas_transcurridas(self) -> float:
        delta = dt.datetime.now() - self.cocinado_en
        return round(delta.total_seconds() / 3600, 2)


# ---------------------------------------------------------------------------
# Hábitos — completamente genéricos, el usuario define todo.
# ---------------------------------------------------------------------------
# 'tipo' es 'mantener' o 'moderar', no 'bueno'/'malo' — la etiqueta moral no
# va en el dato. 'moderar' es simplemente el que quieres reducir; el sistema
# no necesita juzgarlo para poder medirlo.

class Habito(BaseModel):
    id = AutoField()
    nombre = CharField(unique=True)               # lo que tú escribas, incluido alias discreto
    conjunto = CharField(default="general")       # una sola categoría por ahora
    tipo = CharField()                            # 'mantener' | 'moderar'
    metrica = CharField(default="check")          # 'check' | 'contador' | 'duracion_min'
    tipo_objetivo = CharField(default="binario")  # 'binario' | 'aumentar' | 'reducir'
    valor_objetivo = FloatField(default=1.0)     # qué valor cuenta como "cumplido" (binario: 1.0; aumentar/reducir: límite)
    umbral = FloatField(default=1.0)              # fracción 0-1 del valor_objetivo para contar "completado"
    peso = FloatField(default=1.0)                # peso relativo en el puntaje global ponderado
    esencial = BooleanField(default=False)        # participa en racha mínima (2-3 acciones esenciales)
    icono = CharField(null=True)                  # referencia libre, se asigna cuando definamos íconos
    activo = BooleanField(default=True)
    creado = DateTimeField(default=dt.datetime.now)


class HabitoLog(BaseModel):
    id = AutoField()
    habito = ForeignKeyField(Habito, backref="registros", on_delete="CASCADE")
    fecha = DateField(default=dt.date.today)
    valor = FloatField(default=1.0)   # 1.0 = check cumplido; contador/duración usan el número real
    nota = TextField(default="")      # contexto libre — antecedente/consecuencia, sin formato fijo

    class Meta:
        indexes = ((("habito", "fecha"), True),)


MODELOS = [Usuario, Alimento, InventarioItem, Compra, Comida, AlarmaConfig,
           RegistroComida, ConsumoItem, Suplemento, SuplementoLog, SueñoLog,
           Jornada, Coccion, Habito, HabitoLog]


# ---------------------------------------------------------------------------
# Seed data — solo se usa una vez, en la primera inicialización.
# Después de esto, la app es la fuente de verdad, no este archivo.
# ---------------------------------------------------------------------------

# Valores por 100 g, en rangos de referencia estándar de tablas de composición.
# 'confianza' marca qué tan firme es el dato: los que no tengo con certeza
# quedan en null, no en cero — un cero dice "no tiene", null dice "no sé".
# hemo=True solo en fuentes animales: ese hierro se absorbe mucho mejor y
# casi no lo afectan los inhibidores.

def _al(nombre, kcal, prot, categoria, unidad="g", grasa=None, carb=None,
        fibra=None, hierro=None, hemo=False, calcio=None, zinc=None,
        vitc=None, b12=None, sodio=None, gxu=None, conf="media",
        inhibe_fe=False, etiquetas=()):
    return dict(nombre=nombre, kcal_100g=kcal, proteina_100g=prot,
                grasa_100g=grasa, carb_100g=carb, fibra_100g=fibra,
                hierro_mg_100g=hierro, hierro_es_hemo=hemo,
                calcio_mg_100g=calcio, zinc_mg_100g=zinc, vitc_mg_100g=vitc,
                b12_mcg_100g=b12, sodio_mg_100g=sodio, confianza=conf,
                inhibe_hierro_no_hemo=inhibe_fe,
                categoria=categoria, unidad_compra=unidad,
                gramos_por_unidad=gxu, etiquetas=etiquetas)


ALIMENTOS_SEED = [
    # --- Proteína animal (hierro hemo, B12) ---
    _al("huevo", 155, 13.0, "proteina", "unidad", grasa=11, carb=1.1, fibra=0,
        hierro=1.2, calcio=50, zinc=1.1, vitc=0, b12=1.1, gxu=50, conf="alta"),
    _al("pollo_pechuga", 165, 31.0, "proteina", "g", grasa=3.6, carb=0, fibra=0,
        hierro=1.0, hemo=True, calcio=15, zinc=1.0, vitc=0, b12=0.3, conf="alta"),
    _al("atun_lata", 132, 28.0, "proteina", "lata", grasa=1.0, carb=0, fibra=0,
        hierro=1.3, hemo=True, calcio=10, zinc=0.7, vitc=0, b12=2.2,
        sodio=350, gxu=140, conf="alta"),
    _al("carne_res_molida", 250, 26.0, "proteina", "g", grasa=15, carb=0, fibra=0,
        hierro=2.6, hemo=True, calcio=18, zinc=6.3, vitc=0, b12=2.6, conf="alta"),

    # --- Legumbres (hierro NO-hemo: sensible a inhibidores y potenciadores) ---
    _al("lenteja_cocida", 116, 9.0, "grano", "g", grasa=0.4, carb=20, fibra=7.9,
        hierro=3.3, calcio=19, zinc=1.3, vitc=1.5, b12=0, conf="alta",
        etiquetas=("legumbres", "lentejas")),
    _al("frijol_cocido", 127, 8.7, "grano", "g", grasa=0.5, carb=23, fibra=6.4,
        hierro=2.1, calcio=27, zinc=1.0, vitc=0, b12=0, conf="alta",
        etiquetas=("legumbres", "frijol")),

    # --- Granos y tubérculos ---
    _al("arroz_cocido", 130, 2.7, "grano", "g", grasa=0.3, carb=28, fibra=0.4,
        hierro=0.2, calcio=10, zinc=0.5, vitc=0, b12=0, conf="alta"),
    _al("avena_seca", 389, 16.9, "grano", "g", grasa=6.9, carb=66, fibra=10.6,
        hierro=4.7, calcio=54, zinc=4.0, vitc=0, b12=0, conf="alta"),
    _al("pan_integral", 247, 13.0, "grano", "paquete", grasa=3.4, carb=41,
        fibra=7.0, hierro=2.5, calcio=107, zinc=1.8, vitc=0, b12=0,
        sodio=450, conf="media"),
    _al("papa_cocida", 87, 2.0, "verdura", "g", grasa=0.1, carb=20, fibra=1.8,
        hierro=0.3, calcio=8, zinc=0.3, vitc=13, b12=0, conf="alta"),
    _al("yuca", 160, 1.4, "verdura", "g", grasa=0.3, carb=38, fibra=1.8,
        hierro=0.3, calcio=16, zinc=0.3, vitc=20, b12=0, conf="alta"),
    _al("platano", 89, 1.1, "fruta", "unidad", grasa=0.3, carb=23, fibra=2.6,
        hierro=0.3, calcio=5, zinc=0.2, vitc=8.7, b12=0, gxu=120, conf="alta"),

    # --- Lácteos (calcio alto: inhibe hierro y zinc si coinciden) ---
    _al("leche_entera", 61, 3.2, "lacteo", "g", grasa=3.3, carb=4.8, fibra=0,
        hierro=0, calcio=113, zinc=0.4, vitc=0, b12=0.5, conf="alta",
        etiquetas=("leche",)),
    _al("queso_fresco", 264, 18.0, "lacteo", "g", grasa=21, carb=3.0, fibra=0,
        hierro=0.2, calcio=500, zinc=2.8, vitc=0, b12=0.8, sodio=600,
        conf="media", etiquetas=("queso",)),

    # --- Verduras (vitamina C: potencia el hierro no-hemo) ---
    _al("espinaca", 23, 2.9, "verdura", "g", grasa=0.4, carb=3.6, fibra=2.2,
        hierro=2.7, calcio=99, zinc=0.5, vitc=28, b12=0, conf="alta",
        etiquetas=("espinaca",)),
    _al("brocoli", 34, 2.8, "verdura", "g", grasa=0.4, carb=7.0, fibra=2.6,
        hierro=0.7, calcio=47, zinc=0.4, vitc=89, b12=0, conf="alta"),

    # --- Grasas y frutos secos ---
    _al("mani", 567, 25.8, "grasa", "g", grasa=49, carb=16, fibra=8.5,
        hierro=4.6, calcio=92, zinc=3.3, vitc=0, b12=0, conf="alta"),
    _al("aguacate", 160, 2.0, "grasa", "unidad", grasa=15, carb=9, fibra=6.7,
        hierro=0.6, calcio=12, zinc=0.6, vitc=10, b12=0, gxu=200, conf="alta"),
    _al("aceite_oliva", 884, 0.0, "grasa", "g", grasa=100, carb=0, fibra=0,
        hierro=0.6, calcio=1, zinc=0, vitc=0, b12=0, conf="alta"),

    # --- Bebidas e infusiones ---
    _al("cafe", 2, 0.1, "bebida", "g", grasa=0, carb=0, fibra=0,
        hierro=0, calcio=2, zinc=0, vitc=0, b12=0, conf="alta",
        inhibe_fe=True, etiquetas=("cafe", "polifenoles")),
    _al("te", 1, 0.0, "bebida", "g", grasa=0, carb=0, fibra=0,
        hierro=0, calcio=0, zinc=0, vitc=0, b12=0, conf="alta",
        inhibe_fe=True, etiquetas=("te", "polifenoles")),
    # Jamaica: dos entradas distintas a propósito.
    # Los valores de tabla (150 mg calcio, 3 mg hierro, 17 mg vit C por 100 g)
    # son de CÁLICES SECOS, y nadie come 100 g de cálices. La proporción real
    # de infusión es 10-15 g por litro, y al beber el agua los minerales se
    # quedan mayormente en la flor. Los polifenoles y ácidos orgánicos sí
    # pasan al agua — por eso la infusión conserva la etiqueta polifenoles
    # (inhibe hierro no-hemo) aunque su aporte nutricional sea casi nulo.
    _al("jamaica_seca", 49, 2.0, "verdura", "g", grasa=0.1, carb=10.2,
        fibra=2.5, hierro=3.0, calcio=150, zinc=None, vitc=17, b12=0,
        conf="media",
        inhibe_fe=True, etiquetas=("jamaica", "polifenoles", "acida", "diuretico")),
    _al("jamaica_infusion", 1, 0.0, "bebida", "g", grasa=0, carb=0.2, fibra=0,
        hierro=0.05, calcio=2, zinc=0, vitc=0.3, b12=0, conf="baja",
        inhibe_fe=True, etiquetas=("infusion", "jamaica", "polifenoles", "diuretico")),
    _al("jengibre", 80, 1.8, "bebida", "g", grasa=0.8, carb=18, fibra=2.0,
        hierro=0.6, calcio=16, zinc=0.3, vitc=5, b12=0, conf="media",
        etiquetas=("infusion", "jengibre")),
]

# Complejo B en la mañana: no es una regla dura, es que las B suelen ser
# estimulantes en algunas personas, y tomarlo tarde puede pelear con
# dormir a las 21:00.
SUPLEMENTOS_SEED = [
    ("Complejo B", 6, 30,
     "Con el desayuno. Tomarlo de noche puede interferir con el sueño."),
]


# ---------------------------------------------------------------------------
# Inicialización
# ---------------------------------------------------------------------------

def init_db() -> Usuario:
    # El directorio se crea al importar, pero si desapareció desde entonces
    # connect() falla con un error poco claro. Reasegurarlo aquí es barato.
    os.makedirs(os.path.dirname(db.database), exist_ok=True)
    db.connect(reuse_if_open=True)
    db.create_tables(MODELOS)

    usuario = Usuario.select().first()
    if usuario is None:
        usuario = Usuario.create()

    if Comida.select().count() == 0:
        for orden, nombre, hora, minuto, peso, contexto in config.HORARIO_COMIDAS:
            comida = Comida.create(orden=orden, nombre=nombre, hora=hora,
                                   minuto=minuto, peso_calorico=peso,
                                   contexto=contexto)
            AlarmaConfig.create(comida=comida)

    if Alimento.select().count() == 0:
        for datos in ALIMENTOS_SEED:
            datos = dict(datos)
            etiquetas = datos.pop("etiquetas", ())
            a = Alimento.create(**datos)
            a.etiquetas = etiquetas
            a.save()
            InventarioItem.create(alimento=a, gramos_disponibles=0.0)

    if Suplemento.select().count() == 0:
        for nombre, hora, minuto, notas in SUPLEMENTOS_SEED:
            Suplemento.create(nombre=nombre, hora=hora, minuto=minuto, notas=notas)

    return usuario


def get_usuario() -> Usuario:
    return Usuario.select().first() or Usuario.create()


# ---------------------------------------------------------------------------
# Alimentos e inventario — acceso
# ---------------------------------------------------------------------------

def catalogo_alimentos():
    return list(Alimento.select().where(Alimento.activo == True).order_by(Alimento.nombre))


def alimento(nombre: str):
    return Alimento.get_or_none(Alimento.nombre == nombre)


def agregar_alimento(nombre, kcal_100g, proteina_100g, etiquetas=(), **campos):
    """
    Agrega un alimento al catálogo. Solo nombre, kcal y proteína son
    obligatorios; el resto de nutrientes es opcional y queda null si no lo
    pasas — null significa "no sé", no "no tiene".

    Ejemplo:
        agregar_alimento("zanahoria", 41, 0.9, categoria="verdura",
                         vitc_mg_100g=5.9, fibra_100g=2.8, confianza="alta")
    """
    a = Alimento.create(nombre=nombre, kcal_100g=kcal_100g,
                        proteina_100g=proteina_100g, **campos)
    a.etiquetas = etiquetas
    a.save()
    InventarioItem.get_or_create(alimento=a, defaults={"gramos_disponibles": 0.0})
    return a


def alimentos_por_categoria(categoria: str):
    return list(Alimento.select().where(Alimento.activo == True,
                                        Alimento.categoria == categoria)
                .order_by(Alimento.nombre))


# ---------------------------------------------------------------------------
# Compras — acceso
# ---------------------------------------------------------------------------

def registrar_compra(alimento_obj, gramos: float, precio: float = None,
                     fecha: dt.date = None, lugar: str = "",
                     sumar_inventario: bool = True) -> Compra:
    """Registra la compra y, por defecto, suma lo comprado al inventario."""
    c = Compra.create(alimento=alimento_obj, gramos=gramos, precio=precio,
                      fecha=fecha or dt.date.today(), lugar=lugar)
    if precio is not None and gramos:
        alimento_obj.costo_referencia = precio
        alimento_obj.save()
    if sumar_inventario:
        item, _ = InventarioItem.get_or_create(alimento=alimento_obj)
        item.gramos_disponibles += gramos
        item.actualizado = dt.datetime.now()
        item.save()
    return c


def compras_de(alimento_obj, dias: int = 180):
    desde = dt.date.today() - dt.timedelta(days=dias)
    return list(Compra.select()
                .where(Compra.alimento == alimento_obj, Compra.fecha >= desde)
                .order_by(Compra.fecha.desc()))


def historial_compras(dias: int = 180):
    desde = dt.date.today() - dt.timedelta(days=dias)
    return list(Compra.select().where(Compra.fecha >= desde)
                .order_by(Compra.fecha.desc()))


def inventario_dict() -> dict:
    """{nombre_alimento: gramos_disponibles} — solo lo que hay en stock."""
    return {i.alimento.nombre: i.gramos_disponibles
            for i in InventarioItem.select().join(Alimento)
            if i.gramos_disponibles > 0}


def set_inventario(alimento_obj, gramos: float):
    """Fija el stock a un valor absoluto (para cuando compras/actualizas)."""
    item, _ = InventarioItem.get_or_create(alimento=alimento_obj)
    item.gramos_disponibles = max(0.0, gramos)
    item.actualizado = dt.datetime.now()
    item.save()
    return item


def descontar_inventario(alimento_obj, gramos: float) -> bool:
    """
    Descuenta del inventario al usar. Devuelve False si no había
    suficiente (igual descuenta lo que hay, deja en 0 — no bloquea
    el registro de la comida por falta de stock).
    """
    item, _ = InventarioItem.get_or_create(alimento=alimento_obj)
    suficiente = item.gramos_disponibles >= gramos
    item.gramos_disponibles = max(0.0, item.gramos_disponibles - gramos)
    item.actualizado = dt.datetime.now()
    item.save()
    return suficiente


# ---------------------------------------------------------------------------
# Comidas — acceso
# ---------------------------------------------------------------------------

def comidas_ordenadas():
    return list(Comida.select().where(Comida.activa == True).order_by(Comida.orden))


def registro_de(comida: Comida, fecha: dt.date = None) -> RegistroComida:
    fecha = fecha or dt.date.today()
    registro, _ = RegistroComida.get_or_create(comida=comida, fecha=fecha)
    return registro


def registros_del_dia(fecha: dt.date = None):
    fecha = fecha or dt.date.today()
    return {r.comida_id: r for r in
            RegistroComida.select().where(RegistroComida.fecha == fecha)}


def confirmar_consumo(comida: Comida, items: dict, fecha: dt.date = None) -> dict:
    """
    items = {'pollo_pechuga': 150, 'arroz_cocido': 200, ...}

    Crea el ConsumoItem por cada alimento, descuenta inventario, y marca
    la comida como confirmada. Devuelve totales reales + qué alimentos
    no tenían suficiente stock (informativo, no bloquea).
    """
    fecha = fecha or dt.date.today()
    registro = registro_de(comida, fecha)

    # si se re-confirma, no duplicar el consumo anterior
    ConsumoItem.delete().where(ConsumoItem.registro == registro).execute()

    insuficientes = []
    for nombre, gramos in items.items():
        a = alimento(nombre)
        if not a or gramos <= 0:
            continue
        ConsumoItem.create(registro=registro, alimento=a, gramos=gramos)
        if not descontar_inventario(a, gramos):
            insuficientes.append(nombre)

    registro.confirmada_en = dt.datetime.now()
    registro.omitida = False
    registro.save()

    totales = registro.totales()
    return {
        "registro": registro,
        "kcal": totales["kcal"],
        "proteina_g": totales["proteina_g"],
        "stock_insuficiente": insuficientes,
    }


def totales_del_dia(fecha: dt.date = None) -> dict:
    fecha = fecha or dt.date.today()
    kcal = prot = 0.0
    confirmadas = 0
    for r in RegistroComida.select().where(
            RegistroComida.fecha == fecha,
            RegistroComida.confirmada_en.is_null(False)):
        t = r.totales()
        kcal += t["kcal"]
        prot += t["proteina_g"]
        confirmadas += 1
    return {"kcal": kcal, "proteina_g": prot, "confirmadas": confirmadas}


def historial(dias: int = 14):
    hoy = dt.date.today()
    salida = []
    for i in range(dias):
        f = hoy - dt.timedelta(days=i)
        t = totales_del_dia(f)
        t["fecha"] = f
        salida.append(t)
    return salida


# ---------------------------------------------------------------------------
# Suplementos — acceso
# ---------------------------------------------------------------------------

def suplementos_activos():
    return list(Suplemento.select().where(Suplemento.activo == True))


def marcar_suplemento_tomado(suplemento: Suplemento, fecha: dt.date = None):
    fecha = fecha or dt.date.today()
    log, _ = SuplementoLog.get_or_create(suplemento=suplemento, fecha=fecha)
    log.tomado_en = dt.datetime.now()
    log.save()
    return log


def suplementos_pendientes_hoy():
    """Suplementos cuya hora ya pasó y no se han marcado como tomados hoy."""
    hoy = dt.date.today()
    ahora = dt.datetime.now()
    pendientes = []
    for s in suplementos_activos():
        log = SuplementoLog.get_or_none(SuplementoLog.suplemento == s,
                                        SuplementoLog.fecha == hoy)
        if log and log.tomado_en:
            continue
        objetivo = dt.datetime.combine(hoy, dt.time(s.hora, s.minuto))
        if objetivo <= ahora:
            pendientes.append(s)
    return pendientes


# ---------------------------------------------------------------------------
# Sueño real — acceso
# ---------------------------------------------------------------------------

def dormir_ahora(fecha_noche: dt.date = None) -> SueñoLog:
    """Botón 'Me voy a dormir'. fecha_noche = el día en que empieza la noche."""
    fecha_noche = fecha_noche or dt.date.today()
    log, _ = SueñoLog.get_or_create(fecha=fecha_noche)
    log.hora_dormir_real = dt.datetime.now()
    log.save()
    return log


def despertar_ahora():
    """Cierra el registro de sueño más reciente que sigue abierto."""
    log = (SueñoLog.select()
           .where(SueñoLog.hora_dormir_real.is_null(False),
                  SueñoLog.hora_despertar_real.is_null(True))
           .order_by(SueñoLog.hora_dormir_real.desc())
           .first())
    if log:
        log.hora_despertar_real = dt.datetime.now()
        log.save()
    return log


def historial_sueño(dias: int = 7):
    desde = dt.date.today() - dt.timedelta(days=dias)
    return list(SueñoLog.select()
                .where(SueñoLog.fecha >= desde)
                .order_by(SueñoLog.fecha))


# ---------------------------------------------------------------------------
# Jornada — acceso
# ---------------------------------------------------------------------------

def jornada_de(fecha: dt.date = None) -> Jornada:
    fecha = fecha or dt.date.today()
    j, _ = Jornada.get_or_create(fecha=fecha)
    return j


def registrar_jornada(fecha=None, hora_entrada=None, minuto_entrada=0,
                      hora_salida=None, minuto_salida=0,
                      hora_almuerzo=None, minuto_almuerzo=0,
                      dia_libre=False) -> Jornada:
    j = jornada_de(fecha)
    if hora_entrada is not None:
        j.hora_entrada = hora_entrada
        j.minuto_entrada = minuto_entrada
    if hora_salida is not None:
        j.hora_salida = hora_salida
        j.minuto_salida = minuto_salida
    if hora_almuerzo is not None:
        j.hora_almuerzo = hora_almuerzo
        j.minuto_almuerzo = minuto_almuerzo
    j.dia_libre = dia_libre
    j.save()
    return j


def jornadas_recientes(dias: int = 14):
    desde = dt.date.today() - dt.timedelta(days=dias)
    return list(Jornada.select().where(Jornada.fecha >= desde).order_by(Jornada.fecha))


# ---------------------------------------------------------------------------
# Cocción — acceso
# ---------------------------------------------------------------------------

def registrar_coccion(alimento_obj, gramos: float = 0.0,
                      cocinado_en: dt.datetime = None) -> Coccion:
    return Coccion.create(alimento=alimento_obj, gramos=gramos,
                          cocinado_en=cocinado_en or dt.datetime.now())


def cocciones_abiertas():
    """Lo que está cocinado y aún no se comió ni se descartó."""
    return list(Coccion.select()
                .where(Coccion.consumido == False, Coccion.descartado == False)
                .order_by(Coccion.cocinado_en))


def marcar_coccion(coccion: Coccion, consumido=False, descartado=False):
    coccion.consumido = consumido
    coccion.descartado = descartado
    coccion.save()
    return coccion


# ---------------------------------------------------------------------------
# Hábitos — acceso
# ---------------------------------------------------------------------------

def crear_habito(nombre, tipo, conjunto="general", metrica="check",
                 tipo_objetivo="binario", valor_objetivo=1.0, umbral=1.0,
                 peso=1.0, esencial=False, icono=None):
    return Habito.create(nombre=nombre, tipo=tipo, conjunto=conjunto,
                         metrica=metrica, tipo_objetivo=tipo_objetivo,
                         valor_objetivo=valor_objetivo, umbral=umbral,
                         peso=peso, esencial=esencial, icono=icono)


def habitos_activos(conjunto: str = None):
    q = Habito.select().where(Habito.activo == True)
    if conjunto:
        q = q.where(Habito.conjunto == conjunto)
    return list(q.order_by(Habito.nombre))


def registrar_habito(habito: Habito, valor: float = 1.0,
                     fecha: dt.date = None, nota: str = "") -> HabitoLog:
    fecha = fecha or dt.date.today()
    log, _ = HabitoLog.get_or_create(habito=habito, fecha=fecha)
    log.valor = valor
    log.nota = nota
    log.save()
    return log


def habito_de_hoy(habito: Habito, fecha: dt.date = None):
    fecha = fecha or dt.date.today()
    return HabitoLog.get_or_none(HabitoLog.habito == habito, HabitoLog.fecha == fecha)


def historial_habito(habito: Habito, dias: int = 30):
    desde = dt.date.today() - dt.timedelta(days=dias)
    return list(HabitoLog.select()
                .where(HabitoLog.habito == habito, HabitoLog.fecha >= desde)
                .order_by(HabitoLog.fecha))


def cerrar():
    if not db.is_closed():
        db.close()
