# CLAUDE.md — HumanOS v3

Offline-first, single-user Android app (Flutter) for nutrition, Heavy Duty
training, work heat/hydration, recovery telemetry (wrist band via Health
Connect) and habits. One person per phone; the profile is entered in the
app. The repository holds no personal data of anyone (see rule 10).

Identifiers and comments in English. **All UI strings in Spanish (es-EC).**

## Non-negotiable directives

1. **Archive, never destroy.** v1 (Python + Flet) lives on branch
   `archive/humanos-v1-flet`. Never delete that branch.
2. **GitHub Actions is the only build environment.** The owner does not
   program and has no local toolchain. Never install Flutter or the Android
   SDK in an agent session and never ask the owner to run commands. The
   owner's only actions are creating secrets (`KEYSTORE_PASSWORD`,
   `KEYSTORE_ENC_B64`), pressing "Run workflow" and the manual phone
   checklist. CI runs
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
10. **No personal data** in README, commits, issues, releases, table names,
    code or example texts: no names, schedules, trades, rates, weights or
    coordinates. Examples live only in `test/` and are invented.
11. **Money in integer cents, time in integer minutes.** No `double` for
    money in storage.
12. **Nothing static.** Zones, goals, work templates, expense categories and
    thresholds are user data (create / edit / pause / archive / complete).
13. **Audit before change, root cause over patches, one phase per PR** in the
    order of the adjustments brief. Every data migration keeps a verified
    copy first. What can only be checked on the phone (Keystore, alarms,
    on-device model) goes to the manual checklist; nothing is "done" without
    it.
14. **Signing key:** never rotate it (another signature forces an uninstall
    and the data is lost). It lives encrypted in the `KEYSTORE_ENC_B64`
    secret; `clave.yml` moves it from the old public release and deletes
    that release only after comparing certificate fingerprints.

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
│  ├─ lib/src/                 adaptive_tdee, macro_targets, hydration_plan,
│  │                           readiness, double_progression, rep_tempo, e1rm,
│  │                           pantry_scorer, lp_simplex, streaks, attributes,
│  │                           interaction_rules, cooked_food_safety, schedule,
│  │                           work, money, notification_policy, context_mode,
│  │                           alarms, text_es, log_parser, assistant_eval,
│  │                           assumptions, confidence, day, format_es,
│                           advisor/ (finance, rules: Fase 5, no LLM),
│                           day_schedule (B1: template + one-day changes),
│                           screen_time (B2: usage events → minutes, hiding),
│                           dns_filter (B3: domains, export, verdict),
│                           meal_plan, receipt_parser (B4), pay (B5),
│                           day_close (B6)
│  └─ test/                    one *_test.dart per lib/src file
├─ assets/                     db/ (CI-provided), fonts/ (OFL), shaders/, audio/,
│                              eval/ (assistant evaluation set, invented phrases)
├─ pigeons/                    Pigeon source of the model bridge (outputs committed)
├─ lib/                        Flutter app
│  ├─ main.dart
│  ├─ app/                     router, theme, providers, shared widgets
│  ├─ data/                    reference_db, user_db (drift), tables/, seed, export
│  ├─ telemetry/               health_connect_source, ble_hr_source, usage_stats, confidence
│  ├─ services/                notifications (native scheduler), device_context, …
│  └─ features/<estado|registro|despensa|indice|heavy_duty|trabajo|contexto|
│        inicio|pantalla|filtro|cierre|alarmas|asistente|finanzas|habitos|ajustes>/
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
  except by a user-initiated encrypted import. Encrypted at rest with
  SQLite3MultipleCiphers (`hooks: user_defines: sqlite3: source: sqlite3mc`);
  `PRAGMA hexkey` is the first statement of every connection. The 32-byte key
  is generated on first launch and kept in the Android Keystore
  (flutter_secure_storage). A plain v3.0 file is encrypted on a copy, the row
  count of every table is compared, an encrypted copy goes to `backups/`, and
  only then the plain file is replaced (`lib/data/db_open.dart`). An
  encrypted file without its key is moved aside, never deleted.
  `reference.sqlite` (public data) stays unencrypted.

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
| user `daily_logs.intake_complete` | bool, default false | "DÍA COMPLETO": only confirmed days feed the adaptive TDEE |
| user `work_entries`, `work_templates` (schema 2) | new tables | flexible work: cents and minutes, across midnight, user templates |
| user `daily_logs` (schema 2) | `heat_minutes`, `sweat_feel`, `effort_feel`, `mood`, `thermo_pre`, `thermo_break`; sweat test out | the thermos plan replaces the sweat-rate test |
| user `purchases.total_cents`, `pantry_items.price_cents_per_kg` (schema 2) | integer cents | no `double` for money |
| user `zones`, `context_events`, `mode_corrections`, `state_checkins`, `event_reminders` (schema 3) | new tables | location context: zones are user data; only ENTER/EXIT with a timestamp, no position history |
| user `morning_alarms` (schema 3) | new table | morning alarms rung by the phone |
| user `expenses`, `expense_categories`, `goals`, `purchase_pauses` (schema 5) | new tables | finance advisor: cents only, user categories, goals with sub-goals (`parent_id`), the wait before an unplanned purchase |
| user `schedule_blocks`, `schedule_adjustments` (schema 6) | new tables | B1: the weekly day template (user blocks, weekdays, alarm) and one-date changes (skip, move, end later, add) |
| user `app_classes`, `app_usage_days` (schema 7) | new tables | B2: the user's category per app and minutes per app per day (the phone keeps its usage events only some days) |
| user `dns_domains` (schema 8) | new table | B3: the user's blocked and allowed domains (nothing preset) |
| user `food_handling_flags`, `receipt_links` (schema 9) | new tables | B4: the user's word on how a food keeps (needs cold / lunch box / needs cooking) over the suggestion from its food group; receipt lines linked to a food once |
| user `pay_weeks`, `cash_counts` (schema 10) | new tables | B5: what the user was paid with its normal and overtime minutes (and the overtime part when the slip shows it); cash counts kept current with what is logged after them |
| user `day_closes`, `interaction_categories`, `day_close_interactions` (schema 11) | new tables | B6: the day's close (mood, energy, the user's own question) and minutes with people by the user's categories |
| user `app_settings.updated_at` (schema 4) | nullable text | the brief's `settings (key, value, updated_at)`; values from before schema 4 keep NULL (date unknown) |

`sqlite3_flutter_libs` is end-of-life (`0.6.0+eol`): `sqlite3` 3.x bundles
SQLite (with FTS5) through build hooks, so the app depends on `drift`,
`drift_flutter` and `sqlite3` instead.

`wakelock_plus` (needs `dbus` 0.8) cannot be resolved together with
`flutter_blue_plus` (pins `bluez` < 0.9, `dbus` 0.7); the session screen keeps
the display on with `FLAG_KEEP_SCREEN_ON` through the app's own channel
(`com.altair.humanos/screen`, `DeviceChannels.kt`). Screen time uses
`com.altair.humanos/usage_stats` on the same file.

`build_runner` 2.16 removed `--delete-conflicting-outputs`; workflows run
`dart run build_runner build`.

Every schema version has its export in `drift_schemas/` (CI fails if the
code and the saved export differ). A migration copies `user.sqlite` to
`backups/` first, counts every table's rows after, and restores the copy on
any loss (`lib/data/db_open.dart`).

Reminders and alarms are scheduled by the phone (`Scheduler.kt`,
`Alarms.kt`, channel `com.altair.humanos/scheduler`), not by
flutter_local_notifications, so a zone that silences reminders (chamba or
entreno) applies even with the app closed: each reminder carries its
`ContextRule` (allow / defer / drop). Zones use Google Play services'
`GeofencingClient` only (`play-services-location`, channel
`com.altair.humanos/context`): no foreground location service, no
continuous location updates. What the phone needs while the app is closed
(zones to re-register after a reboot, pending reminders, alarms, unread
transitions) lives in small AES-GCM files keyed by the Android Keystore
(`SecureStore.kt`) and is rebuilt from the encrypted database on every
start.

The assistant only turns a phrase into one record of a fixed schema
(`log_parser.dart`) and the user confirms in the usual form. Rules come
first; the on-device model (LiteRT-LM `litertlm-android`, CPU, bridge
`LlmBridge` generated by Pigeon 29.1.0 from `pigeons/llm_bridge.dart`; the
app does not depend on pigeon) is asked only when the rules find nothing,
and its JSON is validated like any input. Gemma 3 270M has no official INT4
`.litertlm` (only a web `.task`): the app offers its official INT8 file and
Gemma 3 1B INT4. Models are not in the APK: they download over Wi-Fi with
the user's own Hugging Face token (license-gated) and are used only when the
size pinned in `model_manager.dart` and the SHA-256 published by the source
match. `assets/eval/asistente_es.json` (invented phrases) ships with the app
because the brief requires measuring accuracy and latency on the phone; the
model is on by default only at or above the accuracy assumption.

HumanOS can be the phone's home screen (B1): `MainActivity` also answers
`MAIN` + `HOME` + `DEFAULT`, and `LauncherChannel.kt`
(`com.altair.humanos/launcher`) lists and opens apps, gives the system's
own dialer and opens Ajustes → Apps predeterminadas. The way out never
depends on HumanOS working: holding the clock on INICIO for 5 s opens that
settings page, a screen that fails to build is replaced by a plain app list
(`ErrorWidget.builder` → `SafeAppList`), and the system launcher is never
disabled. Pinned apps are the user's choice (`launcher_pinned`); no package
name is hard-coded. Blocks marked with an alarm ring through the same
native alarm list as the morning alarms (template weekdays, plus today's
moved or added blocks), rebuilt on every start, resume and change.

Screen time (B2) pairs the phone's resume/pause usage events per app
(`usage_stats` channel, `events`), splits them at midnight and by schedule
block, and stores minutes per app per day in the encrypted database; usage
data never leaves the phone. The first category of an app is a suggestion
from the category it declares to Android; the user's choice wins. Apps of
the categories the user hides disappear from INICIO only during the blocks
they mark; leisure outside those blocks opens directly, and the 10 s pause
before social apps is optional and off by default. Per-site detail inside
Chrome is not available to third-party apps (said on screen).

The DNS filter (B3) cannot be set by an app (Android allows changing the
private DNS only with root or device-owner rights): HumanOS keeps the
user's lists, exports them (one domain per line, or AdGuard rules), guides
the setup of a NextDNS or AdGuard DNS profile, and checks it by resolving
the first blocked and the first allowed domain through the system resolver
(`InternetAddress.lookup`, which the private DNS answers). A local VPN
filter is not included (conflicts with other VPNs, battery).

Meals (B4) are the meal blocks of the user's schedule: each gets its share
of the day's energy and protein from the meal weights (SUPUESTOS → HORARIO
DE COMIDAS), and REGISTRO, the meal reminders and INICIO's one-tap COMER
AHORA follow them (without meal blocks, the work-shift engine as before).
The day's energy can be a fixed target set by the user (AJUSTES → METAS DE
COMIDA, with RESTABLECER). The plan by meal uses only pantry food that fits
the meal: lunch-box food that needs no cooking for mid-morning and
mid-afternoon; without a fridge, fresh food only on the day it was bought.
How a food keeps is suggested from its food group and the user corrects it.
A purchase is also an expense (the user's category), and receipt text read
on the phone becomes lines the user confirms, each product linked to the
reference database once.

Money from real income (B5): the value of an hour and of an overtime hour
comes from the pay the user records (the slip's overtime part when given,
else a least-squares split of weeks with different mixes, else only the
average); recorded pay replaces the work entries' money for its week in the
advisor, never both. Cash is the user's last count minus the expenses and
plus the pay logged after it; the days it lasts use the spending pace of
the last days (SUPUESTOS → FINANZAS) and warn, never block, when it does
not reach the next income date the user wrote down. GASTÉ on INICIO logs an
expense with an amount and one tap on a category.

The day's close (B6) takes under half a minute: mood and energy 1–5,
minutes with people by the user's own categories (reference: today's
minutes in apps the user classed as communication; the call log is not
read) and the user's own yes/no question; after a "sí" the phrase the user
wrote for next time is shown. No question, category or phrase is preset;
no score, no reproach. Trends appear only after the minimum days
(SUPUESTOS → CIERRE DEL DÍA), always with the number of days and
"correlación no es causa".

The Android project is generated in CI by `flutter create`; only these files
are committed: `android/app/build.gradle.kts`, `proguard-rules.pro`,
`src/main/AndroidManifest.xml`, `src/main/kotlin/com/altair/humanos/*`,
`res/drawable/ic_stat_humanos.xml`, `res/drawable/ic_launcher_foreground.xml`,
`res/mipmap-anydpi-v26/ic_launcher.xml`, `res/values/ic_launcher_background.xml`,
`res/raw/keep.xml`. `ci.yml` builds a debug-signed release APK as a check.

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
  locally, the user-started model download (Fase 3) and the DNS filter
  check (B3: two lookups of the user's own domains through the phone's
  resolver).
* Health data never leaves the device except via the user-initiated,
  AES-GCM encrypted export.

## Modelling rules

* The finance advisor (`humanos_core/lib/src/advisor/`) is rules and
  templates only: every piece of advice shows its numbers and its rule, can
  be dismissed, at most `max_advice_per_day` a day and none in CHAMBA or
  ENTRENO. The fixed notice "Información general, no es asesoría financiera
  personalizada." is always on screen. No trading, no investment advice, no
  hard-coded bank rates or prices; the LLM never writes advice.

* Every model constant lives in `packages/humanos_core/lib/src/assumptions.dart`
  (`assumptionCatalog`) with value, Spanish title, explanation and source;
  the app seeds the `assumptions` table from it and the SUPUESTOS screen
  edits it. Engines receive an `Assumptions` map.
* Unknown is not zero: NULL inputs drop their term and lower confidence.
* Warnings never block (interactions, readiness ROJO, low stock).
* Gamification: feedback only on real events (PR, streak, attribute up),
  ≤ 600 ms + haptic, can be disabled. No loot, no lotteries, no decorative
  animation. A broken streak shows "mejor racha" and "días cumplidos en 30".
* Two original themes in `ThemeRegistry` (`lib/app/theme.dart`), chosen in
  AJUSTES and switched live (the settings stream rebuilds `MaterialApp`):
  * **WASTELAND** — retro terminal: black background, one accent (phosphor
    green `#39FF14` or safety orange `#FF6B00`) with the other as secondary,
    VT323 / Share Tech Mono headings, IBM Plex Mono data, static scanlines.
  * **GRIMORIO** — parchment, leather and ink, Cinzel headings, IM Fell
    English labels, IBM Plex Mono data, a still rune rule drawn in code.
  Status colours (readiness, food safety) come from the `HosLook` theme
  extension, never from a fixed colour. `test/theme_test.dart` checks WCAG
  AA (4.5:1) for every text colour in both themes. All fonts are OFL with
  their licence in `assets/fonts/`. No Fallout names or assets.
