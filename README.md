# HumanOS v3

App de Android sin conexión para una sola persona por teléfono: comida y
despensa, entrenamiento Heavy Duty, calor e hidratación en el trabajo,
recuperación con datos de la banda (Health Connect) y hábitos. Todo queda en
el teléfono y la base de datos del usuario va cifrada.

La versión 1 (Python + Flet) está archivada en la rama
`archive/humanos-v1-flet`.

## Instalar (sin programar)

1. En GitHub: **Settings → Secrets and variables → Actions → Secrets → New
   repository secret**. Nombre `KEYSTORE_PASSWORD`; valor: una contraseña
   larga que no olvides (protege la clave con la que se firma la app).
2. **Actions → android → Run workflow** (la primera vez tarda 20–30 minutos).
3. **Releases → la versión v3.0.x más nueva → `app-arm64-v8a-release.apk`**.
4. Antes de instalar una versión nueva encima de otra: en la app, **Ajustes →
   Copia de seguridad → Exportar copia cifrada**, y guárdala fuera del
   teléfono.

### Mover la clave de firma a Secrets (una sola vez)

1. **Actions → clave → Run workflow → `exportar`**. El resumen de la ejecución
   muestra un bloque de texto (la clave, cifrada con tu contraseña).
2. Crea el secret `KEYSTORE_ENC_B64` y pega ese bloque.
3. **Actions → android → Run workflow** y comprueba que diga «Clave desde el
   secret».
4. **Actions → clave → `verificar-y-borrar-release`**: comprueba que sea la
   misma clave y borra la release pública `signing-key`. La clave nunca se
   cambia: otra firma obligaría a desinstalar y se perderían los datos.

## Pantallas

| Pantalla | Para qué |
|---|---|
| ESTADO | Preparación (VERDE/AMARILLO/ROJO), objetivo de energía y proteína, peso y tendencia |
| REGISTRO | Comidas, búsqueda sin tildes, código de barras, plantillas, «día completo» |
| HEAVY DUTY | Sesiones A/B, objetivo a superar, metrónomo, contador grande, descanso, récords |
| TURNO | Esfuerzo, horas de calor y plan del termo |
| DESPENSA | Stock, compras, lotes cocinados con su límite de seguridad, plan del día |
| ÍNDICE | Cada alimento con sus datos por 100 g, fuente y licencia; «sin dato» cuando falta |
| HÁBITOS | Rachas, misión mínima y atributos |
| AJUSTES | Perfil, SUPUESTOS (cada número del modelo con su explicación), avisos, datos de salud, copia cifrada, fuentes |

## Privacidad

- Sin cuentas ni servidores. La única conexión es buscar en Open Food Facts un
  código de barras que no está en la base local.
- La base de datos del usuario está cifrada (SQLite3MultipleCiphers) con una
  clave guardada en el Keystore de Android. Si se borran los datos de la app,
  la clave se pierde: el respaldo es la copia cifrada con contraseña.
- Los datos de salud solo salen del teléfono en la copia que tú exportas,
  cifrada con AES-256-GCM.
- Las notificaciones se ocultan en la pantalla de bloqueo.

## Datos

- `reference.sqlite` (solo lectura, datos públicos) lo construye `etl/` con
  USDA FoodData Central (CC0) y Open Food Facts (ODbL). Ningún valor
  nutricional se inventa: lo que falta se muestra como «sin dato».
- `user.sqlite` (drift, cifrada) guarda lo tuyo; solo cambia con migraciones
  o al restaurar una copia.

## Repositorio

```
etl/                     Python 3.11: construye reference.sqlite (con pytest)
packages/humanos_core/   motores puros en Dart, con pruebas
lib/                     app Flutter (pantallas, datos, telemetría, servicios)
test/                    pruebas de widgets, de datos y de cifrado
android/app/             solo los archivos propios; el resto lo genera CI
.github/workflows/       ci.yml (pruebas), etl.yml (base mensual),
                         android.yml (APK), clave.yml (clave de firma)
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
