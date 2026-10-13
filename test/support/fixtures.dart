import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:humanos/app/providers.dart';
import 'package:humanos/app/theme.dart';
import 'package:humanos/data/reference_db.dart';
import 'package:humanos/data/settings.dart';
import 'package:humanos/data/user_db.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// In-memory user database for tests.
UserDb memoryUserDb() => UserDb(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true),
    );

/// The reference DDL taken from the ETL itself, so the fixture schema can
/// never drift from the real database.
String referenceDdl() {
  final source = File('etl/build_reference_db.py').readAsStringSync();
  final start = source.indexOf('DDL = """') + 'DDL = """'.length;
  final end = source.indexOf('"""', start);
  return source.substring(start, end);
}

/// Small reference database: test values only (never shipped).
ReferenceDb fixtureReferenceDb() {
  final db = sql.sqlite3.openInMemory();
  db.execute(referenceDdl());
  db.execute(
    'INSERT INTO sources(id, code, name, license, url, version) VALUES '
    "(1, 'fdc_sr', 'USDA FoodData Central SR Legacy', 'CC0 1.0', 'https://fdc.nal.usda.gov', '2018-04')",
  );
  const foods = [
    (1, 'Plátano verde', 'Plantains, green, raw', 'Frutas', 'raw', 'green'),
    (2, 'Plátano maduro', 'Plantains, yellow, raw', 'Frutas', 'raw', 'ripe'),
    (3, 'Banano', 'Bananas, raw', 'Frutas', 'raw', 'ripe'),
    (4, 'Frijol negro cocido', 'Beans, black, cooked', 'Leguminosas', 'cooked', 'na'),
    (5, 'Harina de maíz precocida', 'Cornmeal, precooked', 'Cereales', 'prepared', 'na'),
  ];
  for (final f in foods) {
    db.execute(
      'INSERT INTO foods(id, source_id, source_ref, canonical_name_es, canonical_name_en, '
      'food_group, state, ripeness) VALUES (?, 1, ?, ?, ?, ?, ?, ?)',
      [f.$1, 'test-${f.$1}', f.$2, f.$3, f.$4, f.$5, f.$6],
    );
    db.execute(
      'INSERT INTO food_properties(food_id, macro_dominant, energy_density_kcal_g, confidence) '
      "VALUES (?, 'carb_starch', 1.2, 'media')",
      [f.$1],
    );
  }
  const names = [
    (1, 'Plátano verde', 'GEN', 1),
    (1, 'verde', 'EC', 0),
    (2, 'Plátano maduro', 'GEN', 1),
    (3, 'Banano', 'GEN', 1),
    (3, 'guineo', 'EC', 0),
    (3, 'cambur', 'VE', 0),
    (4, 'Frijol negro cocido', 'GEN', 1),
    (4, 'caraota negra', 'VE', 0),
    (5, 'Harina de maíz precocida', 'GEN', 1),
  ];
  for (final n in names) {
    db.execute(
      'INSERT INTO food_names(food_id, name, region, is_primary) VALUES (?, ?, ?, ?)',
      [n.$1, n.$2, n.$3, n.$4],
    );
  }
  db.execute('INSERT INTO food_names_fts(name, food_id) SELECT name, food_id FROM food_names');
  db.execute(
    'INSERT INTO nutrients(id, fdc_nutrient_id, name_es, unit, category) VALUES '
    "(1, 1008, 'Energía', 'kcal', 'Energía'), (2, 1003, 'Proteína', 'g', 'Macronutrientes')",
  );
  db.execute(
    'INSERT INTO food_nutrients(food_id, nutrient_id, amount_per_100g) VALUES '
    '(4, 1, 132), (4, 2, 8.9), (5, 1, 360), (5, 2, 7)',
  );
  db.execute(
    'INSERT INTO products(barcode, name, brand, kcal_100g, protein_100g) VALUES '
    "('7861234567890', 'Atún en agua', 'Marca prueba', 116, 26)",
  );
  db.execute("INSERT INTO products_fts(name, brand, barcode) VALUES ('Atún en agua', 'Marca prueba', '7861234567890')");
  db.execute("INSERT INTO recipes(id, name_es) VALUES (1, 'Arepa')");
  db.execute('INSERT INTO recipe_items(recipe_id, food_id, grams) VALUES (1, 5, 120)');
  db.execute(
    'INSERT INTO exercises(id, name_es, equipment, muscles, failure_safe, rep_min, rep_max, '
    'min_increment_kg, tempo, cue_es) VALUES '
    "(1, 'Prensa de piernas', 'maquina', 'piernas', 1, 6, 10, 5, '4-1-X-2', 'Espalda pegada al respaldo.'), "
    "(5, 'Peso muerto rumano', 'barra', 'isquios', 0, 6, 8, 2.5, '4-1-X-2', 'Cadera atrás, espalda neutra.')",
  );
  db.execute(
    'INSERT INTO exercise_templates(template, position, exercise_id) VALUES '
    "('A', 1, 1), ('B', 1, 5), ('BASELINE', 1, 1)",
  );
  return ReferenceDb.fromDatabase(db);
}

/// Wraps [child] like the app does (theme, Spanish locale, providers).
Widget testApp({
  required UserDb db,
  required Widget child,
  ReferenceDb? reference,
  DateTime? now,
  List<Override> extra = const [],
}) {
  final clock = now ?? DateTime(2026, 10, 13, 9);
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      userDbProvider.overrideWithValue(db),
      referenceDbProvider.overrideWithValue(reference),
      clockProvider.overrideWithValue(() => clock),
      ...extra,
    ],
    child: MaterialApp(
      theme: buildTheme(AccentColor.phosphor),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    ),
  );
}
