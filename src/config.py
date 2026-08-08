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
]

# ---------------------------------------------------------------------------
# Tabla de alimentos base — densos, baratos, sin licuadora
# (kcal, proteina_g, grasa_g, carb_g) por 100 g
# ---------------------------------------------------------------------------

ALIMENTOS = {
    "arroz_cocido":     {"kcal": 130, "prot": 2.7,  "etiquetas": set()},
    "avena_seca":       {"kcal": 389, "prot": 16.9, "etiquetas": set()},
    "huevo":            {"kcal": 155, "prot": 13.0, "etiquetas": set()},
    "pollo_pechuga":    {"kcal": 165, "prot": 31.0, "etiquetas": set()},
    "atun_lata":        {"kcal": 132, "prot": 28.0, "etiquetas": set()},
    "carne_res_molida": {"kcal": 250, "prot": 26.0, "etiquetas": set()},
    "lenteja_cocida":   {"kcal": 116, "prot": 9.0,  "etiquetas": {"legumbres", "lentejas"}},
    "frijol_cocido":    {"kcal": 127, "prot": 8.7,  "etiquetas": {"legumbres", "frijol"}},
    "pan_integral":     {"kcal": 247, "prot": 13.0, "etiquetas": set()},
    "papa_cocida":      {"kcal": 87,  "prot": 2.0,  "etiquetas": set()},
    "platano":          {"kcal": 89,  "prot": 1.1,  "etiquetas": set()},
    "platano_verde":    {"kcal": 122, "prot": 1.3,  "etiquetas": set()},
    "yuca":             {"kcal": 160, "prot": 1.4,  "etiquetas": set()},
    "leche_entera":     {"kcal": 61,  "prot": 3.2,  "etiquetas": {"leche"}},
    "queso_fresco":     {"kcal": 264, "prot": 18.0, "etiquetas": {"queso"}},
    "yogurt_natural":   {"kcal": 61,  "prot": 3.5,  "etiquetas": {"yogurt"}},
    "mani":             {"kcal": 567, "prot": 25.8, "etiquetas": set()},
    "aceite_oliva":     {"kcal": 884, "prot": 0.0,  "etiquetas": set()},
    "aguacate":         {"kcal": 160, "prot": 2.0,  "etiquetas": set()},
    "espinaca":         {"kcal": 23,  "prot": 2.9,  "etiquetas": {"espinaca"}},
    "brocoli":          {"kcal": 34,  "prot": 2.8,  "etiquetas": set()},
    "cafe":             {"kcal": 2,   "prot": 0.1,  "etiquetas": {"cafe"}},
    "te":               {"kcal": 1,   "prot": 0.0,  "etiquetas": {"te"}},
}

# ---------------------------------------------------------------------------
# Alarmas
# ---------------------------------------------------------------------------

# Minutos tras la hora objetivo antes de marcar la comida como omitida.
VENTANA_GRACIA_MIN = 90

# Intervalo del vigilante en primer plano (segundos).
INTERVALO_CHECK_S = 30

CANAL_NOTIF_ID = "humanos_comidas"
CANAL_NOTIF_NOMBRE = "Recordatorios HumanOS"
