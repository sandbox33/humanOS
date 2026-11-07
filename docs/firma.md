# Firma del APK: reporte y procedimiento

Fecha: 2026-11-07 · base: `main` en `4fe525a`.

Solo reporte y preparación. Nada de esto se ejecutó: no se generó, movió ni
borró ninguna clave o release.

## 1. Último APK firmado con la clave de release

- **v3.0.1** es el único: release `v3.0.1` (commit `5d91b3a`, 2026-10-13) con
  `app-arm64-v8a-release.apk`, `app-armeabi-v7a-release.apk` y
  `app-x86_64-release.apk`. La publicó la única ejecución de `android.yml`:
  run `38395407147` (job `115289233507`).
- Esa misma ejecución creó la clave. Su log dice «Primera compilación: se crea
  la clave de firma.» y la dejó cifrada en la release pública `signing-key`
  (`upload.jks.enc`, 2 624 bytes, mismo commit).
- **La huella del certificado nunca se registró.** El `android.yml` de
  `5d91b3a` no la imprimía; esa línea llegó con `f3bf5f9` (2026-10-31). La
  primera vez que se verá será al ejecutar `clave → exportar` o el próximo
  `android`.
- Desde v3.0.1 hay 59 commits en `main` (fases 0–5 y B1–B7) sin ningún APK
  firmado.

## 2. APK de prueba del CI

- El job «APK de prueba (firma de depuración)» de `ci.yml` compila con
  `flutter build apk --release` sin `KEYSTORE_PATH`. Por eso
  `android/app/build.gradle.kts:49` elige la firma **de depuración**
  (`build.gradle.kts:7-13`).
- Ese APK **no se publica**: ningún workflow de v3 sube artefactos (no hay
  `upload-artifact` desde `a1753df`). Solo comprueba que la app compila.
- Un APK con firma de depuración y uno con la clave de release no pueden
  actualizarse entre sí: cambiar de firma obliga a desinstalar.
- Estado que reporta el dueño: no hay ninguna versión instalada, así que la
  próxima instalación será limpia. Desde ella, cada versión tiene que salir de
  `android.yml` con la misma clave.
- Dato a confirmar: v3 nunca publicó un APK con firma de depuración. Lo único
  descargable ha sido v3.0.1, firmado con la clave de release. El «APK de
  prueba» desinstalado era probablemente v3.0.1. Como no queda nada
  instalado, no cambia nada.

## 3. ¿Cuándo crea `android.yml` una clave nueva?

Paso «Clave de firma», con `set -euo pipefail` (`android.yml:78-122`):

| Secret `KEYSTORE_ENC_B64` | Release `signing-key` | Qué pasa |
|---|---|---|
| con texto | — | usa el secret (`:91-94`); si no se descifra, falla |
| vacío | existe y se descarga | usa la release, con aviso (`:95-98`) |
| vacío | existe pero la descarga falla | entra al `else` (`:99`), genera otra clave (`:101`) y al subirla falla, porque `upload.jks.enc` ya existe y no se usa `--clobber` (`:108-109`). No hay rotación, pero el error confunde. |
| vacío | **no existe** | genera otra clave (`:101`), crea la release (`:111`) y **firma con la clave nueva** → **rotación** |

En resumen, la rotación ocurre solo con `KEYSTORE_ENC_B64` vacío **y** la
release `signing-key` borrada. Ese es justo el estado que deja
`clave → verificar-y-borrar-release` si después alguien borra o vacía el
secret.

### Cambio mínimo propuesto (no aplicado)

Que el `else` falle salvo que el dueño lo confirme a mano al ejecutar el
workflow:

```diff
 on:
   workflow_dispatch:
+    inputs:
+      crear_clave_nueva:
+        description: 'Déjalo vacío. Solo si NO existe ninguna clave (ni secret ni release), escribe CREAR CLAVE NUEVA.'
+        required: false
+        default: ''
 ...
     env:
       GH_TOKEN: ${{ github.token }}
       KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
       KEYSTORE_ENC_B64: ${{ secrets.KEYSTORE_ENC_B64 }}
+      CREAR_CLAVE_NUEVA: ${{ inputs.crear_clave_nueva }}
 ...
           else
+            if [ "${CREAR_CLAVE_NUEVA}" != "CREAR CLAVE NUEVA" ]; then
+              echo "::error::No hay clave de firma (ni el secret KEYSTORE_ENC_B64 ni la release signing-key). No se crea otra sin confirmación: otra firma obliga a desinstalar. Revisa los secrets; solo si de verdad no existe ninguna clave, ejecuta de nuevo escribiendo CREAR CLAVE NUEVA."
+              exit 1
+            fi
             echo "Primera compilación: se crea la clave de firma."
```

- La confirmación entra como variable de entorno, no pegada en el script, para
  evitar inyección de comandos.
- El caso «existe pero la descarga falla» también termina en ese error claro.
- Hay que aplicarlo **antes** del paso 4 de abajo.

## 4. Procedimiento de `clave.yml` (lo hace el dueño, paso a paso)

Antes de empezar:
- El cambio del punto 3 ya está en `main`.
- El secret `KEYSTORE_PASSWORD` existe y es la contraseña original de la
  primera compilación.

`clave` y `android` comparten el grupo de concurrencia `android`, así que
nunca corren a la vez.

1. **Actions → clave → Run workflow → `exportar`.** El resumen muestra
   «Clave de firma (cifrada) para el secret», la **huella del certificado** y
   un bloque de texto. Anota la huella (no es secreta).
   - Si sale «KEYSTORE_PASSWORD no abre la clave de la release»: **detente.**
     La contraseña no es la original. Mira la nota al final.
2. **Settings → Secrets and variables → Actions → New repository secret.**
   Nombre `KEYSTORE_ENC_B64`; valor: el bloque completo.
3. **Actions → android → Run workflow** (con `crear_clave_nueva` vacío).
   - El log debe decir «Clave desde el secret KEYSTORE_ENC_B64.».
   - La huella del resumen debe ser **igual** a la del paso 1.
   - Esta ejecución publica el primer APK firmado de `main` (punto 5).
4. **Actions → clave → Run workflow → `verificar-y-borrar-release`.**
   - Compara la huella del secret con la de la release y solo borra
     `signing-key` si son iguales (`clave.yml:118-122`).
   - El resumen debe decir «Listo».
5. **Borra la ejecución del paso 1** (Actions → esa ejecución → ⋯ → Delete
   workflow run), para que el texto cifrado no quede a la vista.

Si algo sale distinto de lo descrito, detente y avisa. Solo el paso 4 borra
algo, y únicamente si las huellas coinciden.

**Si se perdió `KEYSTORE_PASSWORD`:** la clave de la release ya no sirve.
Como no hay nada instalado, se puede crear una clave nueva una sola vez:
`android` con `CREAR CLAVE NUEVA` (requiere el cambio del punto 3). Desde ahí,
esa es la clave para siempre.

## 5. Primer APK firmado de `main` (listo, sin ejecutar)

- `android.yml` pone la versión con su número de ejecución
  (`android.yml:133-140`):
  - `--build-name 3.0.<n>`
  - `--build-number <n>`
  - tag `v3.0.<n>`
- Solo hubo una ejecución (n = 1, v3.0.1), así que la próxima será **v3.0.2**
  o mayor (versionCode 2 o mayor) sin cambiar código. El `version: 3.0.0+1`
  de `pubspec.yaml` no cuenta, porque esos parámetros lo reemplazan
  (`build.gradle.kts:32-33`).
- Antes de compilar, ese workflow:
  - corre `flutter test` (`:129`);
  - verifica `reference.sqlite` con su `.sha256` (`:76`).
- Cómo hacerlo, cuando los puntos 3 y 4 estén resueltos (es el paso 3 del
  procedimiento):
  1. **Actions → android → Run workflow** sobre `main`. Tarda unos 25–30
     minutos.
  2. **Releases → v3.0.N → `app-arm64-v8a-release.apk`**. Instálalo en limpio.
  3. Guarda la huella del resumen. Cada versión siguiente debe mostrar la
     misma.
- Detalle menor: las notas de esa release todavía dicen «La primera vez
  desinstala HumanOS v1» (`android.yml:144`). Es inofensivo.
