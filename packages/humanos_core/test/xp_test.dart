import 'package:humanos_core/src/assumptions.dart';
import 'package:humanos_core/src/attributes.dart';
import 'package:humanos_core/src/xp.dart';
import 'package:test/test.dart';

void main() {
  final a = Assumptions.defaults();
  final lp = LevelParams.fromAssumptions(a);

  test('fixed amounts until the daily cap, then zero', () {
    expect(xpForEvent(XpSource.meal, alreadyToday: 0, assumptions: a), 5);
    expect(xpForEvent(XpSource.meal, alreadyToday: 3, assumptions: a), 5);
    expect(xpForEvent(XpSource.meal, alreadyToday: 4, assumptions: a), 0);
    expect(xpForEvent(XpSource.session, alreadyToday: 0, assumptions: a), 60);
    expect(xpForEvent(XpSource.session, alreadyToday: 1, assumptions: a), 0);
    expect(
      xpForEvent(XpSource.hydrationAck, alreadyToday: 1, assumptions: a),
      5,
    );
    expect(
      xpForEvent(XpSource.hydrationAck, alreadyToday: 2, assumptions: a),
      0,
    );
    expect(xpForEvent(XpSource.pr, alreadyToday: 3, assumptions: a), 0);
    expect(xpForEvent(XpSource.meal, alreadyToday: -1, assumptions: a), 0);
  });

  test('every source has a code, label, amount and cap', () {
    for (final s in XpSource.values) {
      expect(XpSource.parse(s.code), s);
      expect(s.labelEs, isNotEmpty);
      expect(s.amount(a), greaterThanOrEqualTo(0));
      expect(s.dailyCap(a), greaterThan(0));
    }
    expect(XpSource.parse('loot'), isNull);
  });

  test('a diligent day is capped well below a level of the late game', () {
    var day = 0;
    for (final s in XpSource.values) {
      day += s.amount(a) * s.dailyCap(a);
    }
    // Even maxing every source every day, level 10 takes weeks.
    final level10 = cumulativeXpForLevel(10, lp);
    expect(level10 / day, greaterThan(20));
  });

  test('cumulative XP follows base × (n − 1)^exponent', () {
    expect(cumulativeXpForLevel(1, lp), 0);
    expect(cumulativeXpForLevel(2, lp), 120);
    expect(cumulativeXpForLevel(3, lp), 514); // 120 × 2^2.1 = 514.45
    expect(cumulativeXpForLevel(10, lp), closeTo(12110, 5));
    for (var n = 2; n < 40; n++) {
      final step =
          cumulativeXpForLevel(n + 1, lp) - cumulativeXpForLevel(n, lp);
      final prev =
          cumulativeXpForLevel(n, lp) - cumulativeXpForLevel(n - 1, lp);
      expect(step, greaterThan(prev), reason: 'nivel $n');
    }
  });

  test('levelForXp finds the level and progress', () {
    expect(levelForXp(0, lp).level, 1);
    expect(levelForXp(-50, lp).level, 1);
    expect(levelForXp(119, lp).level, 1);
    final l2 = levelForXp(120, lp);
    expect(l2.level, 2);
    expect(l2.xpIntoLevel, 0);
    expect(l2.xpToNext, 394);
    final mid = levelForXp(300, lp);
    expect(mid.level, 2);
    expect(mid.progress, closeTo(180 / 394, 1e-9));
    expect(levelForXp(12110, lp).level, 10);
  });

  test('rank titles by fixed milestones', () {
    expect(rankTitleEs(1), 'APRENDIZ');
    expect(rankTitleEs(4), 'AYUDANTE');
    expect(rankTitleEs(8), 'SOLDADOR CERTIFICADO');
    expect(rankTitleEs(25), 'LEYENDA DEL ARCO');
    expect(levelForXp(600, lp).titleEs, 'AYUDANTE');
  });

  test('skills stay locked until every requirement is met', () {
    final none = evaluateSkills(const SkillProgressInput(level: 1));
    expect(none.every((s) => !s.unlocked), isTrue);
    final analista = none.firstWhere((s) => s.skill.id == 'analista');
    expect(analista.missingEs, contains('nivel 3'));
    expect(analista.missingEs.join(' '), contains('NÚMEROS'));
    expect(analista.progress, closeTo((1 / 3 + 0) / 2, 1e-9));

    final some = evaluateSkills(
      const SkillProgressInput(
        level: 4,
        rootDepths: {MindRoot.numeros: 0.2, MindRoot.probabilidad: 0.25},
      ),
    );
    final byId = {for (final s in some) s.skill.id: s};
    expect(byId['analista']!.unlocked, isTrue);
    expect(byId['esceptico']!.unlocked, isTrue);
    expect(byId['programador']!.unlocked, isFalse);
    expect(byId['estratega']!.unlocked, isFalse);
    expect(
      byId['estratega']!.missingEs.join(' '),
      contains('habilidad PROGRAMADOR'),
    );
  });

  test('chained skills unlock in the same pass and never relock', () {
    final all = evaluateSkills(
      const SkillProgressInput(
        level: 6,
        rootDepths: {
          MindRoot.logica: 0.3,
          MindRoot.patrones: 0.3,
          MindRoot.probabilidad: 0.35,
          MindRoot.numeros: 0.2,
          MindRoot.lenguaje: 0.2,
          MindRoot.reflexion: 0.25,
        },
        attributes: {AttributeKind.disciplina: 70},
        counters: {
          SkillCounter.quantExperiments: 3,
          SkillCounter.mindReflections: 5,
          SkillCounter.completeDays: 14,
        },
      ),
    );
    expect(all.every((s) => s.unlocked), isTrue);

    final kept = evaluateSkills(
      const SkillProgressInput(
        level: 1,
        attributes: {AttributeKind.disciplina: null},
        unlocked: {'cronista'},
      ),
    );
    expect(kept.firstWhere((s) => s.skill.id == 'cronista').unlocked, isTrue);
  });

  test('unknown attribute reads as "sin dato", not zero', () {
    final s = evaluateSkills(
      const SkillProgressInput(level: 5),
    ).firstWhere((s) => s.skill.id == 'cronista');
    expect(s.missingEs.join(' '), contains('sin dato'));
  });

  test('skill ids are unique and resolvable', () {
    final ids = skillTree.map((s) => s.id).toSet();
    expect(ids.length, skillTree.length);
    for (final s in skillTree) {
      expect(skillById(s.id), same(s));
      for (final r in s.requiresSkills) {
        expect(ids, contains(r));
      }
    }
    expect(skillById('loot'), isNull);
    for (final root in MindRoot.values) {
      expect(MindRoot.parse(root.code), root);
    }
  });
}
