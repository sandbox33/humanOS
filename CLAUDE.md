# CLAUDE.md — HumanOS v3

Offline-first, single-user Android app (Flutter) for nutrition, Heavy Duty
training, workshop heat/hydration, recovery telemetry (Xiaomi Smart Band via
Health Connect) and habits. Owner: Abraham "Altair" Fuenmayor (welder,
07:00–17:00 shift, 1 h lunch, trains after the shift).

Identifiers and comments in English. **All UI strings in Spanish (es-EC).**

## Non-negotiable directives

1. **Archive, never destroy.** v1 (Python + Flet) lives on branch
   `archive/humanos-v1-flet`. Never delete that branch.
2. **GitHub Actions is the only build environment.** The owner does not
   program and has no local toolchain. Never install Flutter or the Android
   SDK in an agent session and never ask the owner to run commands. The
   owner's only actions are creating the `KEYSTORE_PASSWORD` secret and
   pressing "Run workflow". CI runs
   `flutter create --org com.altair --project-name humanos --platforms android .`
   (it only adds missing files), codegen, tests and the build.
3. This file holds the directives, tree, checkpoints and acceptance criteria.
4. Production code only. No `TODO`, `FIXME`, `placeholder`, `lorem`, and no
   mock data outside `test/`. CI greps for these words.
5. **Test before deliver.** Every file in `packages/humanos_core/lib/src/`
   has a test (enforced by `test/structure_test.dart`). Run `dart test` there
   and `python -m pytest etl/tests` when the toolchains exist; otherwise CI
   runs them. Always report which suites actually ran.
6. **Stop rule.** Never run `flutter build`, `flutter run` or
   `dart run build_runner` in a session, never trigger workflows, never push
   tags. Commit, push, summarise, wait for human audit.
7. **Never invent nutrient values.** Missing = `NULL`, shown as "sin dato".
   No hard-coded nutrient numbers in Dart (identifiers such as FDC nutrient
   ids are not values).
8. Use the latest stable versions resolved by `pub`; never pin from memory.
   Commit `pubspec.lock` files.
9. Ask before any destructive or irreversible action not listed here.

## Tree

```
humanOS/
├─ CLAUDE.md, README.md
├─ etl/                        Python 3.11 ETL → assets/db/reference.sqlite
│  ├─ build_reference_db.py    orchestrator (CLI)
│  ├─ sources/                 fdc.py, off.py, ecuador_tables.py
│  ├─ derive/                  taxonomy, nova_rules, nrf93, energy_density, names_es
│  ├─ data/                    gi_values, synonyms_es, terms_es, recipes, exercises (CSV)
│  │  └─ local/                user-provided local tables (optional)
│  └─ tests/                   pytest
├─ packages/humanos_core/      pure Dart engines (no Flutter imports)
│  ├─ lib/src/                 adaptive_tdee, macro_targets, sweat_hydration,
│  │                           readiness, double_progression, rep_tempo, e1rm,
│  │                           pantry_scorer, lp_simplex, streaks, attributes,
│  │                           interaction_rules, cooked_food_safety, schedule,
│  │                           assumptions, confidence, day, format_es
│  └─ test/                    one *_test.dart per lib/src file
├─ assets/                     db/ (CI-provided), fonts/ (OFL), shaders/, audio/
├─ lib/                        Flutter app
│  ├─ main.dart
│  ├─ app/                     router, theme, providers, shared widgets
│  ├─ data/                    reference_db, user_db (drift), tables/, seed, export
│  ├─ telemetry/               health_connect_source, ble_hr_source, usage_stats, confidence
│  └─ features/<estado|registro|despensa|indice|heavy_duty|turno|habitos|ajustes>/
│        data/ domain/ presentation/
├─ android/app/                build.gradle.kts, proguard-rules.pro,
│                              src/main/{AndroidManifest.xml, kotlin/…, res/…}
├─ test/                       widget and integration tests
└─ .github/workflows/          ci.yml, etl.yml, android.yml
```

## Data

* `reference.sqlite` — read-only, built by the ETL (DDL in
  `etl/build_reference_db.py`), downloaded by CI from the latest `refdb-v*`
  release into `assets/db/` and verified with `sha256sum -c`. The app copies
  it to app storage on first launch and whenever the bundled `.sha256`
  changes (which also covers a `PRAGMA user_version` change).
* `user.sqlite` — read-write, drift, migrations only, never overwritten
  except by a user-initiated encrypted import.

### Documented extensions to the v3 DDL

These were needed to implement the plan without hiding state elsewhere:

| Where | Extension | Why |
|---|---|---|
| reference `food_nutrients` | `WITHOUT ROWID` | halves the asset size; same columns and key |
| reference `nutrients` | extra columns none; derivation kept in ETL | — |
| reference `exercise_templates(template, position, exercise_id)` | new table | §7 templates A/B/BASELINE come from `exercises.csv` |
| reference `products_fts` | new FTS5 table | REGISTRO search also finds packaged products |
| user `habits.source` | nullable column | auto-filled habits (protein, weigh-in, sleep…) |
| user `sessions.mode` | `normal/deload/retest` | deload week and re-test must be remembered |
| user `food_user_flags` | `user_excluded`, `user_trigger_reflux` | §5.2 user flags cannot live in the read-only DB |
| user `app_settings` | key/value | accent colour, toggles, onboarding state |

`sqlite3_flutter_libs` is end-of-life (`0.6.0+eol`): `sqlite3` 3.x bundles
SQLite (with FTS5) through build hooks, so the app depends on `drift`,
`drift_flutter` and `sqlite3` instead.

## Audit checkpoints

* **CP1** — ETL tests pass; zero nutrient numbers in Dart.
* **CP2** — 100 % of `humanos_core/lib/src` files tested; no fixed HRV
  baseline, no per-hour electrolyte constants, no `K = 0.4 × Na`.
* **CP3** — no JSON ingredient column; `meal_items` uses ids + grams.
* **CP4** — no decorative animation; PR feedback ≤ 600 ms and disable-able;
  no variable rewards; no Fallout names or assets.
* **CP5** — the forbidden-words grep in `ci.yml` returns nothing.

## Acceptance criteria

* "platano" finds "plátano"; "caraota" finds black beans; "cambur" finds
  banana, not plantain.
* Logging from the pantry decrements `grams_remaining`; insufficient stock
  warns, never blocks.
* Adaptive TDEE changes the target only with ≥ 14 valid days.
* Heavy Duty works one-handed, the screen stays on during a session, the
  metronome is audible with the screen dimmed.
* Fully offline except Open Food Facts barcode lookups for products missing
  locally.
* Health data never leaves the device except via the user-initiated,
  AES-GCM encrypted export.

## Modelling rules

* Every model constant lives in `packages/humanos_core/lib/src/assumptions.dart`
  (`assumptionCatalog`) with value, Spanish title, explanation and source;
  the app seeds the `assumptions` table from it and the SUPUESTOS screen
  edits it. Engines receive an `Assumptions` map.
* Unknown is not zero: NULL inputs drop their term and lower confidence.
* Warnings never block (interactions, readiness ROJO, low stock).
* Gamification: feedback only on real events (PR, streak, attribute up),
  ≤ 600 ms + haptic, can be disabled. No loot, no lotteries, no decorative
  animation. A broken streak shows "mejor racha" and "días cumplidos en 30".
* Visual identity is an original retro terminal: black background, one
  accent (phosphor green `#39FF14` or safety orange `#FF6B00`), VT323 /
  Share Tech Mono headings, IBM Plex Mono data. No Fallout names or assets.
