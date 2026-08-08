# HumanOS — Fase 1

Nutrición de 5 comidas + alarmas, en Flet, compilado a APK desde GitHub Actions.

## Pasos desde Termux

```bash
cd ~/storage/shared/Download
unzip humanos.zip && cd humanos

git init
git add .
git commit -m "HumanOS fase 1"
git branch -M main
git remote add origin https://github.com/sandbox33/humanos.git
git push -u origin main
```

**Crea el repo como PÚBLICO.** Los runners de GitHub son gratis e ilimitados
en repos públicos, así que el build no toca los 2.000 min/mes que necesitas
para SPEL y AXIOM. La base de datos con tus datos reales está en `.gitignore`
y nunca se sube — solo viaja el código.

## Descargar el APK

1. GitHub → pestaña **Actions**
2. Corrida **Build APK** → espera ~10-15 min (el primer build es el lento;
   después la caché lo baja bastante)
3. Sección **Artifacts** → `humanos-apk`
4. Descargar, descomprimir, instalar (hay que permitir "orígenes desconocidos")

El workflow también tiene disparo manual: **Actions → Build APK → Run workflow**.

## Al instalar, concede estos permisos

Sin esto las alarmas no suenan con la app cerrada:

- **Notificaciones** — Android 13+ lo pide al primer arranque
- **Alarmas y recordatorios** — Ajustes → Apps → HumanOS → Alarmas y recordatorios
- **Desactivar optimización de batería** para HumanOS. Xiaomi, Samsung, Huawei
  y Oppo matan procesos en segundo plano de forma agresiva; ver dontkillmyapp.com
  si tu marca aparece ahí

## Arquitectura

| Archivo | Responsabilidad |
|---|---|
| `config.py` | Constantes: horario, reglas, tabla de alimentos. Sin números mágicos en otro lado |
| `database.py` | Modelos Peewee + acceso a datos |
| `nutrition_engine.py` | TDEE, reparto, porciones, interacciones, sueño. Puro, sin UI ni DB |
| `alarm_engine.py` | Programación, pendientes, backend de notificaciones |
| `main.py` | UI Flet |

`nutrition_engine.py` no importa `flet` ni `database`: recibe valores y devuelve
valores. Eso lo hace testeable y reutilizable en las fases siguientes.

## Las tres capas de alarma

Una alarma realmente imposible de desactivar no existe en Android sin permisos
de administrador de dispositivo, que Play penaliza y que Flet no expone.
Lo que sí es alcanzable:

1. **Notificación full-screen intent** — importancia máxima, aparece sobre la
   pantalla de bloqueo. Requiere la extensión `flet_notifications`; si no está
   presente, el sistema degrada solo sin romperse.
2. **Diálogo modal sin salida** — al abrir la app, una comida pendiente dentro
   de la ventana de gracia bloquea la pantalla hasta registrarla. Esta capa la
   controlamos al 100%, sin depender de permisos.
3. **Contabilidad** — lo no confirmado en 90 min se marca como omitido y queda
   en el historial. Lo que no se puede forzar, se mide.

La capa 2 es la que de verdad sostiene el sistema.

## Decisiones que quizá quieras revisar

- **`flet==0.28.3` fijado.** Flet 0.80+ rompe la API. No hagas `pip install -U flet`
  sin migrar primero.
- **Las interacciones nutricionales advierten, no bloquean.** El efecto del
  café sobre el hierro vegetal es real pero modesto. Un sistema que prohíbe
  comer por eso entrena a ignorarlo entero.
- **La proteína se reparte pareja, no por peso calórico.** La síntesis proteica
  responde a la dosis por toma (~0.4 g/kg), no al total diario acumulado. Por eso
  la suma diaria puede quedar ~10% sobre el objetivo: es intencional.
- **El sueño muestra rangos, no horas exactas.** Los ciclos varían 70-120 min.

## Siguiente fase

Entrenamiento + BRI. No se empieza hasta que esto corra en el teléfono.
