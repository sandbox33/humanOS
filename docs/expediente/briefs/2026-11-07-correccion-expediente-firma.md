# BRIEF CORTO — CORRECCIÓN DEL PRIMER EXPEDIENTE Y DE LA FIRMA (humanOS)

**Repo:** `sandbox33/humanOS`, rama `main`. Una sola rama de trabajo y un PR a `main`.

## Contexto
La auditoría de solo lectura (commit `4fe525a`, 2026-11-07) se hizo con marcadores sin rellenar, sin `ESQUEMA.md` y la respuesta salió cortada en el chat. Sus hallazgos son útiles, pero el formato no es el v2 y HumanOS no puede importarlo.

## 1. Expediente en formato v2 (solo documentación, sin tocar código de la app)
- Crear `docs/expediente/ESQUEMA.md` con el archivo adjunto, sin cambios.
- Rehacer la auditoría de solo lectura y guardarla en `docs/expediente/expediente.json` siguiendo ESQUEMA.md:
  - `confianza`: alta → `verificado` (con su evidencia); media/baja → `inferido`.
  - Aristas con varios destinos → una arista por destino (`de`, `a`).
  - Incidentes como lista, uno por causa raíz, con `veces`, `primera`, `ultima` y evidencia (id de run).
  - Incluir `deuda`, `invariantes` y `estudio`, que en la versión anterior no llegaron.
  - Incorporar las fases, tareas, ideas, decisiones y briefs del expediente v1 adjunto (no perder IDs).
- Validar el JSON contra el esquema con un test en `test/` (o un script en CI) antes del commit.
- Repo público: nada de datos personales, montos ni rutina.

## 2. Hallazgo crítico: firma del APK (no ejecutar nada destructivo; solo reportar y preparar)
Reportar con evidencia y responder:
1. ¿Cuál es el último APK firmado con la clave de release? (Se reportó: solo v3.0.1, run `38395407147`, 2026-10-13.)
2. ¿Los APK de prueba del CI usan firma de depuración? Documentarlo. Estado actual: **el dueño no tiene ninguna versión instalada** (desinstaló el APK de prueba), así que la próxima instalación será limpia. Lo importante es que, desde esa instalación, todas las versiones salgan con la misma clave de release.
5. Cuando los puntos 3 y 4 estén resueltos, dejar listo (sin ejecutar) cómo generar el primer APK firmado de `main` actual con `android.yml`, con número de versión mayor que 3.0.1.
3. ¿En qué condición exacta `android.yml` genera una clave nueva? Proponer el cambio mínimo para que **nunca** genere una clave nueva sin confirmación manual (que falle en su lugar).
4. Preparar, sin ejecutar, el procedimiento de `clave.yml` (0 ejecuciones): exportar a Secrets, verificar huellas del certificado, y solo entonces borrar la release `signing-key`. Lo ejecuta el dueño a mano, paso por paso.

## 3. Cuello de botella del CI
De las 30 ejecuciones revisadas, las 8 fallas fueron del job *App Flutter*, y la causa principal es que los errores de `flutter analyze` solo se ven en CI.
- Proponer y, si es seguro, implementar: un job rápido que corra solo `flutter analyze` y el formato primero, y que el job de tests y el APK dependan de él, para fallar en minutos y no al final.
- Medir duración media de los jobs antes y después (desde la API de Actions) y ponerlo en el PR.

## Criterios
- [ ] `docs/expediente/ESQUEMA.md` y `expediente.json` v2 válidos en el PR.
- [ ] Ningún cambio en código de la app salvo el workflow del punto 3.
- [ ] La firma: reporte con evidencia y procedimiento escrito; ninguna clave generada, borrada ni movida.
- [ ] CI en verde.
