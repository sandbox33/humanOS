# HumanOS

App personal de Android para nutrición, hábitos, sueño y jornada — Python +
[Flet](https://flet.dev), estética Pip-Boy/Fallout (fósforo verde monocromo).
Un solo usuario, base de datos local (SQLite), sin red.

## Estructura

```
src/
  config.py             constantes y supuestos del modelo — no depende de nada
  database.py           esquema SQLite + acceso — solo config
  nutrition_engine.py   motores puros (objetivo diario, combinación,
  schedule_engine.py    interacciones, ventanas de sueño, seguridad
  shopping_engine.py    alimentaria, lista de compras) — nunca tocan
  sleep_engine.py       database ni flet, solo config
  habits_engine.py
  theme.py              fósforo monocromo — cero lógica de negocio
  presentador.py         única capa que toca database + los motores;
                         traduce eso a los DatosX que consume cada vista
  alarm_engine.py        avisos y notificaciones a partir de lo que ya
                         calculó presentador — config + database
  main.py                arranque, navegación de 5 pestañas, cablea cada
                         vista con presentador/database
  views/
    hoy.py, comidas.py, habitos.py, inventario.py, sueno.py, perfil.py
    — solo theme.py; reciben datos ya calculados, no tocan la base
  tests_contrato.py      40 contratos sobre los motores puros (~2 s, sin IO)
```

Cada capa solo depende de las de arriba en esta lista — así se prueban los
motores sin base de datos ni interfaz, y las vistas sin base de datos ni
motores.

## Desarrollo

```bash
pip install -r requirements.txt

# Contratos de los motores puros (rápido, sin IO)
cd src && python tests_contrato.py
```

No se compila localmente (Termux no soporta bien el toolchain de
Flutter/Android). El build es exclusivamente vía GitHub Actions.

## Compilar el APK

Cualquier push a `main` que toque `src/`, `pyproject.toml` o
`requirements.txt` dispara el workflow **Build APK**. También se puede
lanzar a mano desde la pestaña *Actions* → *Build APK* → *Run workflow*.

Primer build: ~12 min (arma la caché de Flutter/Android). Builds
siguientes: bastante menos, gracias a la caché.

El `.apk` queda en *Actions* → la corrida → *Artifacts* → `humanos-apk`.

## Privacidad

- Repo público, pero sin datos reales: `*.db`, `src/data/` y `.env` están
  en `.gitignore`.
- Los hábitos usan alias discretos — el nombre no necesita decir qué
  significa; en pantalla se identifican por ícono/glifo, no por
  descripción.
