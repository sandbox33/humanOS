# HumanOS v3

App personal de Android para un soldador que entra a las 07:00, sale a las
17:00 y entrena después del turno: comida con despensa, entrenamiento Heavy
Duty, calor e hidratación del taller, recuperación con la banda Xiaomi (a
través de Health Connect) y hábitos. Un solo usuario. Todo queda en el
teléfono.

La versión 1 (Python + Flet) está archivada en la rama
`archive/humanos-v1-flet`.

## Instalar (tres pasos, sin programar)

1. En GitHub: **Settings → Secrets and variables → Actions → New repository
   secret**. Nombre `KEYSTORE_PASSWORD`; valor: una contraseña larga que no
   olvides (protege la clave con la que se firma la app).
2. **Actions → android → Run workflow**. La primera vez tarda unos 15–20
   minutos porque construye la base de alimentos y crea la clave de firma.
3. **Releases → la versión v3.0.x más nueva → descarga
   `app-arm64-v8a-release.apk`** e instálala. Si tenías HumanOS v1,
   desinstálala antes: es la misma app con otra firma. Los datos de v1 no se
   migran.

## Pantallas

| Pantalla | Para qué |
|---|---|
| ESTADO | Banda de recuperación (VERDE/AMARILLO/ROJO), objetivo de energía y proteína, peso y tendencia, lo esencial del día |
| REGISTRO | Comidas por bloque del turno, búsqueda sin tildes ("platano", "caraota", "cambur"), código de barras, plantillas, repetir el día, "día completo" |
| HEAVY DUTY | Próxima sesión A/B, TARGET TO SMASH, Big 3 de McGill, rampa, metrónomo 4-1-X-2, contador gigante (también con las teclas de volumen), descanso, récords |
| TURNO | Esfuerzo, horas de calor, equipo completo, plan del termo con sodio, avisos de agua, prueba de sudor |
| DESPENSA | Stock con la mejor opción ahora, compras con lectura del recibo, lotes cocinados con su límite de seguridad, plan más barato |
| ÍNDICE | Cada alimento con sus datos por 100 g, fuente y licencia; "sin dato" cuando la fuente no lo trae |
| HÁBITOS | Rachas mínima, global y por hábito, comodines, misión mínima y atributos |
| AJUSTES | Perfil y turno, SUPUESTOS (cada número del modelo con su explicación), avisos, Health Connect y diagnóstico, pulso por Bluetooth, copia cifrada, fuentes |

## Privacidad

- Sin cuentas ni servidores. La única conexión es buscar en Open Food Facts
  un código de barras que no está en la base local.
- Los datos de salud nunca salen del teléfono, salvo la copia que tú
  exportas, cifrada con AES-256-GCM y tu contraseña.
- La clave de firma se guarda solo cifrada (release `signing-key`); la
  versión sin cifrar se borra al terminar cada compilación.

## Datos

- `reference.sqlite` (solo lectura) lo construye `etl/` con USDA FoodData
  Central (CC0) y Open Food Facts (ODbL), más tablas locales opcionales en
  `etl/data/local/`. Ningún valor nutricional se inventa: lo que falta se
  muestra como "sin dato".
- `user.sqlite` (drift) guarda lo tuyo; solo cambia con migraciones o al
  importar una copia cifrada.

## Repositorio

```
etl/                     Python 3.11: construye reference.sqlite (con pytest)
packages/humanos_core/   motores puros en Dart (TDEE adaptativo, hidratación,
                         recuperación, progresión, despensa, rachas…), con pruebas
lib/                     app Flutter (pantallas, datos, telemetría, servicios)
test/                    pruebas de widgets y de datos
android/app/             solo los archivos propios; el resto lo genera CI
.github/workflows/       ci.yml (pruebas), etl.yml (base mensual), android.yml (APK)
```

Las reglas para quien programe están en `CLAUDE.md`.

## Licencias de terceros

- USDA FoodData Central: dominio público (CC0 1.0).
- Open Food Facts: Open Database License (ODbL); contenidos bajo Database
  Contents License.
- Índice glucémico: Atkinson, Foster-Powell y Brand-Miller (2008), Diabetes
  Care 31(12):2281–2283.
- Fuentes VT323, Share Tech Mono e IBM Plex Mono: SIL Open Font License 1.1
  (`assets/fonts/`).
