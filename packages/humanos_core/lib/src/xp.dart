/// Experience points, levels and the skill tree.
///
/// XP only comes from real logged actions, with a fixed amount per source
/// and a daily cap per source: no random rewards, no loot. The cumulative
/// XP needed for level n is `base × (n − 1)^exponent`, so each level costs
/// more than the previous one. Skills unlock knowledge and features when
/// their requirements (level, attributes, MENTE roots, counts) are met.
library;

import 'dart:math' as math;

import 'assumptions.dart';
import 'attributes.dart';

/// Every source of XP with its amount key, cap and the attribute it feeds.
enum XpSource {
  meal('meal', 'Comida registrada', A.xpMealLogged, AttributeKind.nutricion),
  weighIn('weigh_in', 'Pesaje', A.xpWeighIn, AttributeKind.nutricion),
  session('session', 'Sesión de Heavy Duty', A.xpSession, AttributeKind.fuerza),
  pr('pr', 'Récord', A.xpPr, AttributeKind.fuerza),
  minimumDay(
    'minimum_day',
    'Mínimo del día',
    A.xpMinimumDay,
    AttributeKind.disciplina,
  ),
  shiftLogged(
    'shift_logged',
    'Turno registrado',
    A.xpShiftLogged,
    AttributeKind.resistencia,
  ),
  hydrationAck(
    'hydration_ack',
    'Termo confirmado',
    A.xpHydrationAck,
    AttributeKind.resistencia,
  ),
  checkIn(
    'check_in',
    'Sensación matinal',
    A.xpCheckIn,
    AttributeKind.recuperacion,
  ),
  mindCorrect('mind_correct', 'Reto de MENTE acertado', A.xpMindCorrect, null),
  mindReflection(
    'mind_reflection',
    'Explicación en MENTE',
    A.xpMindReflection,
    null,
  ),
  quantExperiment(
    'quant_experiment',
    'Experimento CUANT',
    A.xpQuantExperiment,
    null,
  );

  const XpSource(this.code, this.labelEs, this.amountKey, this.attribute);

  /// Code stored in `xp_log.source`.
  final String code;
  final String labelEs;
  final String amountKey;
  final AttributeKind? attribute;

  static XpSource? parse(String? code) {
    for (final source in XpSource.values) {
      if (source.code == code) return source;
    }
    return null;
  }

  /// Fixed amount for one event.
  int amount(Assumptions a) => a.integer(amountKey);

  /// Maximum number of events that give XP in one day. Sources without a
  /// cap assumption happen once a day by nature (one weigh-in, one
  /// session, one minimum, one shift log, one check-in); the hydration
  /// reminder happens twice (before the shift and at lunch).
  int dailyCap(Assumptions a) => switch (this) {
    XpSource.meal => a.integer(A.xpMealCap),
    XpSource.pr => a.integer(A.xpPrCap),
    XpSource.mindCorrect => a.integer(A.xpMindCap),
    XpSource.mindReflection => a.integer(A.xpReflectionCap),
    XpSource.quantExperiment => a.integer(A.xpQuantCap),
    XpSource.hydrationAck => 2,
    XpSource.weighIn ||
    XpSource.session ||
    XpSource.minimumDay ||
    XpSource.shiftLogged ||
    XpSource.checkIn => 1,
  };
}

/// XP for one more event of [source] when [alreadyToday] events of the same
/// source already gave XP today. Zero once the daily cap is reached.
int xpForEvent(
  XpSource source, {
  required int alreadyToday,
  required Assumptions assumptions,
}) {
  if (alreadyToday < 0) return 0;
  if (alreadyToday >= source.dailyCap(assumptions)) return 0;
  final amount = source.amount(assumptions);
  return amount < 0 ? 0 : amount;
}

class LevelParams {
  const LevelParams({required this.baseXp, required this.exponent});

  factory LevelParams.fromAssumptions(Assumptions a) =>
      LevelParams(baseXp: a[A.levelBaseXp], exponent: a[A.levelExponent]);

  final double baseXp;
  final double exponent;
}

/// Cumulative XP needed to reach [level] (level 1 needs 0).
int cumulativeXpForLevel(int level, LevelParams params) {
  if (level <= 1) return 0;
  return (params.baseXp * math.pow(level - 1, params.exponent)).round();
}

class LevelInfo {
  const LevelInfo({
    required this.level,
    required this.totalXp,
    required this.levelStartXp,
    required this.nextLevelXp,
  });

  final int level;
  final int totalXp;
  final int levelStartXp;
  final int nextLevelXp;

  int get xpIntoLevel => totalXp - levelStartXp;
  int get xpToNext => nextLevelXp - totalXp;

  /// Progress inside the current level, 0..1.
  double get progress {
    final span = nextLevelXp - levelStartXp;
    if (span <= 0) return 0;
    return ((totalXp - levelStartXp) / span).clamp(0, 1).toDouble();
  }

  String get titleEs => rankTitleEs(level);
}

/// Level reached with [totalXp] (never below 1).
LevelInfo levelForXp(int totalXp, LevelParams params) {
  final xp = totalXp < 0 ? 0 : totalXp;
  var level = 1;
  while (cumulativeXpForLevel(level + 1, params) <= xp && level < 999) {
    level++;
  }
  return LevelInfo(
    level: level,
    totalXp: xp,
    levelStartXp: cumulativeXpForLevel(level, params),
    nextLevelXp: cumulativeXpForLevel(level + 1, params),
  );
}

/// Rank names by level band (fixed milestones).
const List<({int fromLevel, String titleEs})> rankTitles = [
  (fromLevel: 1, titleEs: 'APRENDIZ'),
  (fromLevel: 3, titleEs: 'AYUDANTE'),
  (fromLevel: 5, titleEs: 'SOLDADOR'),
  (fromLevel: 8, titleEs: 'SOLDADOR CERTIFICADO'),
  (fromLevel: 12, titleEs: 'MAESTRO DE TALLER'),
  (fromLevel: 16, titleEs: 'INSPECTOR'),
  (fromLevel: 20, titleEs: 'LEYENDA DEL ARCO'),
];

String rankTitleEs(int level) {
  var title = rankTitles.first.titleEs;
  for (final rank in rankTitles) {
    if (level >= rank.fromLevel) title = rank.titleEs;
  }
  return title;
}

/// MENTE domains that feed the skills (roots of the tree).
enum MindRoot {
  logica('logica', 'LÓGICA'),
  numeros('numeros', 'NÚMEROS'),
  patrones('patrones', 'PATRONES'),
  probabilidad('probabilidad', 'PROBABILIDAD'),
  reflexion('reflexion', 'REFLEXIÓN'),
  lenguaje('lenguaje', 'LENGUAJE');

  const MindRoot(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static MindRoot? parse(String? code) {
    for (final root in MindRoot.values) {
      if (root.code == code) return root;
    }
    return null;
  }
}

/// Counters used by skill requirements.
enum SkillCounter {
  quantExperiments('experimentos CUANT'),
  mindReflections('explicaciones en MENTE'),
  completeDays('días completos');

  const SkillCounter(this.labelEs);
  final String labelEs;
}

/// One node of the skill tree.
class SkillDef {
  const SkillDef({
    required this.id,
    required this.nameEs,
    required this.unlocksEs,
    required this.minLevel,
    this.roots = const {},
    this.attributes = const {},
    this.counters = const {},
    this.requiresSkills = const [],
  });

  /// Stored in `skills.id`.
  final String id;
  final String nameEs;

  /// What it opens, shown in the tree.
  final String unlocksEs;
  final int minLevel;

  /// Minimum root depth (0..1) per MENTE domain.
  final Map<MindRoot, double> roots;

  /// Minimum attribute value (0–100).
  final Map<AttributeKind, double> attributes;
  final Map<SkillCounter, int> counters;
  final List<String> requiresSkills;
}

/// The skill tree. Requirements are fixed milestones, not random rewards.
const List<SkillDef> skillTree = [
  SkillDef(
    id: 'analista',
    nameEs: 'ANALISTA',
    unlocksEs:
        'Gráficos avanzados: tendencia del 1RM estimado y gasto adaptativo '
        'día a día.',
    minLevel: 3,
    roots: {MindRoot.numeros: 0.15},
  ),
  SkillDef(
    id: 'esceptico',
    nameEs: 'ESCÉPTICO',
    unlocksEs: 'CUANT: prueba de permutación contra el azar.',
    minLevel: 4,
    roots: {MindRoot.probabilidad: 0.2},
  ),
  SkillDef(
    id: 'programador',
    nameEs: 'PROGRAMADOR',
    unlocksEs: 'CUANT: exportar cada experimento a un script de Python.',
    minLevel: 4,
    roots: {MindRoot.logica: 0.2},
    counters: {SkillCounter.quantExperiments: 3},
  ),
  SkillDef(
    id: 'orador',
    nameEs: 'ORADOR',
    unlocksEs: 'MENTE: análisis de tu forma de explicar y de hablar.',
    minLevel: 3,
    roots: {MindRoot.lenguaje: 0.15},
    counters: {SkillCounter.mindReflections: 5},
  ),
  SkillDef(
    id: 'cronista',
    nameEs: 'CRONISTA',
    unlocksEs: 'Resumen semanal de tus tendencias en el BUZÓN.',
    minLevel: 5,
    roots: {MindRoot.reflexion: 0.2},
    attributes: {AttributeKind.disciplina: 50},
    counters: {SkillCounter.completeDays: 14},
  ),
  SkillDef(
    id: 'estratega',
    nameEs: 'ESTRATEGA',
    unlocksEs: 'CUANT: rangos de parámetros personalizados.',
    minLevel: 6,
    roots: {MindRoot.patrones: 0.25, MindRoot.probabilidad: 0.3},
    requiresSkills: ['esceptico', 'programador'],
  ),
];

SkillDef? skillById(String id) {
  for (final skill in skillTree) {
    if (skill.id == id) return skill;
  }
  return null;
}

/// Everything a skill requirement can look at.
class SkillProgressInput {
  const SkillProgressInput({
    required this.level,
    this.rootDepths = const {},
    this.attributes = const {},
    this.counters = const {},
    this.unlocked = const {},
  });

  final int level;
  final Map<MindRoot, double> rootDepths;
  final Map<AttributeKind, double?> attributes;
  final Map<SkillCounter, int> counters;

  /// Skills already unlocked (they never lock again).
  final Set<String> unlocked;
}

class SkillStatus {
  const SkillStatus({
    required this.skill,
    required this.unlocked,
    required this.progress,
    required this.missingEs,
  });

  final SkillDef skill;
  final bool unlocked;

  /// Mean fulfilment of the requirements, 0..1.
  final double progress;

  /// Requirements still missing, in Spanish.
  final List<String> missingEs;
}

/// Evaluates every skill. A skill already in [SkillProgressInput.unlocked]
/// stays unlocked even if an attribute later drops.
List<SkillStatus> evaluateSkills(SkillProgressInput input) {
  final unlocked = {...input.unlocked};
  final result = <SkillStatus>[];
  for (final skill in skillTree) {
    final parts = <double>[];
    final missing = <String>[];
    parts.add((input.level / skill.minLevel).clamp(0, 1).toDouble());
    if (input.level < skill.minLevel) missing.add('nivel ${skill.minLevel}');
    skill.roots.forEach((root, need) {
      final have = input.rootDepths[root] ?? 0;
      parts.add((have / need).clamp(0, 1).toDouble());
      if (have < need) {
        missing.add(
          'raíz ${root.labelEs} al ${(need * 100).round()} % '
          '(tienes ${(have * 100).floor()} %)',
        );
      }
    });
    skill.attributes.forEach((kind, need) {
      final have = input.attributes[kind];
      parts.add(have == null ? 0 : (have / need).clamp(0, 1).toDouble());
      if (have == null || have < need) {
        missing.add(
          have == null
              ? '${kind.labelEs} ${need.round()} (sin dato aún)'
              : '${kind.labelEs} ${need.round()} (tienes ${have.floor()})',
        );
      }
    });
    skill.counters.forEach((counter, need) {
      final have = input.counters[counter] ?? 0;
      parts.add((have / need).clamp(0, 1).toDouble());
      if (have < need) missing.add('$need ${counter.labelEs} (llevas $have)');
    });
    for (final required in skill.requiresSkills) {
      final ok = unlocked.contains(required);
      parts.add(ok ? 1 : 0);
      if (!ok) {
        missing.add('habilidad ${skillById(required)?.nameEs ?? required}');
      }
    }
    final already = input.unlocked.contains(skill.id);
    final isUnlocked = already || missing.isEmpty;
    if (isUnlocked) unlocked.add(skill.id);
    result.add(
      SkillStatus(
        skill: skill,
        unlocked: isUnlocked,
        progress: isUnlocked ? 1 : parts.reduce((a, b) => a + b) / parts.length,
        missingEs: isUnlocked ? const [] : List.unmodifiable(missing),
      ),
    );
  }
  return result;
}
