"""
HumanOS — Configuración central.

Todo valor ajustable vive aquí. Ningún módulo debe tener números mágicos.
"""

APP_NAME = "HumanOS"
APP_VERSION = "1.0.0-fase1"

# ---------------------------------------------------------------------------
# Perfil por defecto (editable desde la app)
# ---------------------------------------------------------------------------

DEFAULT_PESO_KG = 60.0
DEFAULT_ESTATURA_CM = 172.0
DEFAULT_EDAD = 28

# Superávit calórico para hipertrofia: +10-20% sobre mantenimiento.
# Más superávit no produce más músculo, solo más grasa.
SUPERAVIT_PCT = 0.15

# Proteína: 1.6-2.2 g/kg/dia. Por encima de ~2.2 no hay beneficio adicional
# demostrado para hipertrofia.
PROTEINA_G_POR_KG = 1.8

# Proteína por toma que maximiza la respuesta de síntesis proteica muscular.
# Se usa como piso, no como techo.
PROTEINA_MIN_POR_COMIDA_G_KG = 0.4

# Factor de actividad (Mifflin-St Jeor -> TDEE).
# Trabajo de taller de pie + entrenamiento = moderado-alto.
FACTOR_ACTIVIDAD = {
    "sedentario": 1.2,
    "ligero": 1.375,
    "moderado": 1.55,
    "alto": 1.725,
    "muy_alto": 1.9,
}
DEFAULT_ACTIVIDAD = "alto"

# ---------------------------------------------------------------------------
# Horario de comidas — derivado de la jornada laboral real
# turno mañana 07:00-13:00 | descanso 1h | turno tarde 14:00-17:00/18:00
# ---------------------------------------------------------------------------

# (orden, nombre, hora, minuto, peso_calorico, contexto)
# Los pesos suman 1.0 y reparten el total diario.
# Densidad concentrada en desayuno y cena: evita pesadez digestiva en taller.
HORARIO_COMIDAS = [
    (1, "Desayuno denso",  6, 30, 0.25, "Antes del turno mañana"),
    (2, "Snack media mañana", 10, 0, 0.15, "Durante turno mañana"),
    (3, "Almuerzo",        13,  0, 0.25, "Hora de descanso"),
    (4, "Snack post-turno", 17, 30, 0.10, "Al salir del turno tarde"),
    (5, "Cena hipercalórica", 19, 0, 0.25, "Post-jornada"),
]

# Entrenamiento y anclaje circadiano
HORA_DESPERTAR = (5, 45)
HORA_LUZ_SOLAR = (5, 50)   # 10 min de luz exterior — ancla la fase circadiana
HORA_ENTRENAMIENTO = (6, 0)
HORA_DORMIR = (21, 0)

SUEÑO_OBJETIVO_H = 8.0

# ---------------------------------------------------------------------------
# Reglas de interacción nutricional
# ---------------------------------------------------------------------------
# IMPORTANTE: son ADVERTENCIAS, no bloqueos.
# El efecto de estas interacciones es modesto. Un sistema que prohíbe comer
# por una interacción menor entrena al usuario a ignorarlo por completo.

VENTANA_INTERACCION_MIN = 90

REGLAS_INTERACCION = [
    {
        "id": "hierro_polifenoles",
        "grupo_a": {"legumbres", "espinaca", "lentejas", "frijol", "garbanzo"},
        "grupo_b": {"cafe", "te", "te_negro", "te_verde"},
        "ventana_min": 90,
        "mensaje": (
            "Los polifenoles del café/té reducen la absorción de hierro no-hemo "
            "(vegetal). Separar ~90 min. No afecta al hierro de carne."
        ),
        "severidad": "media",
    },
    {
        "id": "calcio_hierro",
        "grupo_a": {"legumbres", "espinaca", "lentejas", "frijol"},
        "grupo_b": {"leche", "queso", "yogurt"},
        "ventana_min": 60,
        "mensaje": (
            "El calcio compite con el hierro en la misma toma. Efecto pequeño "
            "y se atenúa con el tiempo; relevante solo si el hierro está bajo."
        ),
        "severidad": "baja",
    },
    {
        "id": "fibra_pre_turno",
        "grupo_a": {"salvado", "col", "brocoli_crudo", "coliflor"},
        "grupo_b": set(),
        "ventana_min": 0,
        "solo_comidas": {1, 2},
        "mensaje": (
            "Fibra cruda en volumen antes del turno físico tiende a producir "
            "molestia digestiva. Mejor cocida o en comidas 4-5."
        ),
        "severidad": "media",
    },
    {
        "id": "grasa_pre_entreno",
        "grupo_a": {"frito", "grasa_pesada", "manteca"},
        "grupo_b": set(),
        "ventana_min": 0,
        "solo_comidas": {1},
        "mensaje": (
            "Vaciado gástrico lento antes de entrenar. Mover a cena."
        ),
        "severidad": "baja",
    },
    {
        "id": "grasa_reflujo",
        "grupo_a": {"frito", "grasa_pesada", "manteca"},
        "grupo_b": set(),
        "ventana_min": 0,
        "mensaje": (
            "La grasa relaja el esfínter esofágico y retrasa el vaciado "
            "gástrico — puede empeorar el reflujo. Cantidad moderada, no "
            "hay que evitarla del todo."
        ),
        "severidad": "media",
    },
]

# NOTA: la tabla fija de alimentos que vivía aquí se eliminó. Alimento
# ahora es una tabla editable en la base de datos — ver database.py,
# ALIMENTOS_SEED, para la siembra inicial. Una sola fuente de verdad.

# ---------------------------------------------------------------------------
# Recordatorios generales
# ---------------------------------------------------------------------------
# A diferencia de REGLAS_INTERACCION, esto no se evalúa por combinación de
# alimentos — es un tip fijo que main.py muestra en el contexto que
# corresponda (ej. al confirmar cualquier comida). No depende de qué
# etiquetas tenga cada alimento.

RECORDATORIOS_GENERALES = [
    {
        "id": "liquidos_con_comida",
        "mensaje": (
            "Evita tomar líquidos en volumen junto con la comida — la "
            "distensión extra puede empeorar el reflujo. Espera ~30 min "
            "antes o después."
        ),
    },
    {
        "id": "jamaica_uso",
        "mensaje": (
            "Jamaica: 10-15 g por litro es la proporción de referencia. "
            "Puede bajar la presión arterial y tiene efecto diurético — si "
            "tomas antihipertensivos o diuréticos, conviene consultarlo antes "
            "de usarla a diario. Con anticoagulantes la evidencia es más "
            "escasa, pero vale mencionarlo al médico si la tomas concentrada "
            "y seguido. Una cantidad culinaria ocasional es otra cosa que un "
            "extracto diario."
        ),
    },
]

# ---------------------------------------------------------------------------
# Alarmas
# ---------------------------------------------------------------------------

# Minutos tras la hora objetivo antes de marcar la comida como omitida.
VENTANA_GRACIA_MIN = 90

# Intervalo del vigilante en primer plano (segundos).
INTERVALO_CHECK_S = 30

CANAL_NOTIF_ID = "humanos_comidas"
CANAL_NOTIF_NOMBRE = "Recordatorios HumanOS"


# ---------------------------------------------------------------------------
# Supuestos del modelo
# ---------------------------------------------------------------------------
# Estos números NO son leyes fisiológicas: son decisiones de modelado que
# se eligieron porque hacían falta para calcular algo. Viven aquí, con
# nombre y explicación, para que la interfaz pueda mostrarlos y tú puedas
# cambiarlos — no escondidos como constantes mágicas dentro de un motor.

SUPUESTOS = {
    "actividad_dia_libre": {
        "valor": 0.40,
        "titulo": "Actividad en día libre",
        "explica": ("Un día sin trabajar conserva ~40% del gasto por "
                    "actividad: caminar, cocinar, moverse. No es reposo "
                    "absoluto. Si entrenas fuerte, come más que eso."),
    },
    "fraccion_actividad": {
        "valor": 0.25,
        "titulo": "Peso de la actividad en el gasto",
        "explica": ("Se asume que ~25% del gasto diario viene de actividad y "
                    "el resto es basal. Solo se escala esa parte según las "
                    "horas trabajadas; el gasto basal no cambia."),
    },
    "eficacia_vitc_con_inhibidor": {
        "valor": 0.60,
        "titulo": "Eficacia de la vitamina C con polifenoles",
        "explica": ("Con café, té o jamaica presentes, la vitamina C recupera "
                    "~60% de su efecto: parte del hierro ya quedó complejado "
                    "antes de que pudiera actuar. Mitiga, no neutraliza."),
    },
    "techo_absorcion_no_hemo": {
        "valor": 0.25,
        "titulo": "Techo de absorción de hierro vegetal",
        "explica": ("Límite operativo del modelo: ni en las mejores "
                    "condiciones se absorbe más del 25% del hierro no-hemo "
                    "de una comida."),
    },
    "tolerancia_proteina": {
        "valor": 0.15,
        "titulo": "Margen del plan de proteína",
        "explica": ("El mínimo por toma (0.4 g/kg) puede empujar el plan por "
                    "encima del objetivo diario. Se permite hasta 15% de "
                    "exceso; más que eso, se reparte parejo."),
    },
}


def supuesto(clave: str, por_defecto=None):
    entrada = SUPUESTOS.get(clave)
    return entrada["valor"] if entrada else por_defecto
