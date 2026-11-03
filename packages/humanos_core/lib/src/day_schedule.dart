/// The user's day: a weekly template of blocks plus one-tap adjustments for
/// a date ("hoy hago horas extra hasta las 20:00"), resolved into the day's
/// plan. Every time and every block is user data; nothing is preset here.
///
/// Minutes are minutes from the day's midnight and may pass 1440 for a
/// block that ends the next day (sleep).
library;

import 'work.dart' show weekdaysOf;

const _day = 24 * 60;

/// How a kind behaves when the day changes.
enum BlockRole {
  /// A meal: a short moment that may overlap work; never pushed by others.
  meal,

  /// Work, overtime and sleep keep their time unless the user moves them.
  fixed,

  /// Project, leisure, cooking, training…: pushed after a fixed block that
  /// now overlaps them, shortened up to the next fixed block, or moved to
  /// the next day when too little time is left.
  flexible,
}

enum BlockKind {
  desayuno('desayuno', 'Desayuno', BlockRole.meal),
  mediaManana('media_manana', 'Media mañana', BlockRole.meal),
  almuerzo('almuerzo', 'Almuerzo', BlockRole.meal),
  mediaTarde('media_tarde', 'Media tarde', BlockRole.meal),
  cena('cena', 'Cena', BlockRole.meal),
  trabajo('trabajo', 'Trabajo', BlockRole.fixed),
  horasExtra('horas_extra', 'Horas extra', BlockRole.fixed),
  dormir('dormir', 'Dormir', BlockRole.fixed),
  entreno('entreno', 'Entreno', BlockRole.flexible),
  cocinar('cocinar', 'Cocinar', BlockRole.flexible),
  proyecto('proyecto', 'Proyecto', BlockRole.flexible),
  ocio('ocio', 'Ocio', BlockRole.flexible),
  otro('otro', 'Otro', BlockRole.flexible);

  const BlockKind(this.code, this.labelEs, this.role);
  final String code;
  final String labelEs;
  final BlockRole role;

  static BlockKind parse(String? code) => BlockKind.values.firstWhere(
    (k) => k.code == code,
    orElse: () => BlockKind.otro,
  );
}

/// One block of the weekly template (a row the user created).
class BlockTemplate {
  const BlockTemplate({
    required this.id,
    required this.kind,
    required this.startMin,
    required this.daysMask,
    this.label,
    this.durationMin,
    this.alarm = false,
  });

  final int id;
  final BlockKind kind;

  /// The user's own name; the kind's name when null.
  final String? label;
  final int startMin;

  /// Null: the block lasts until the next block of the day starts (the last
  /// one, until the first block of the next day).
  final int? durationMin;

  /// Weekdays it applies to: bit 0 Monday … bit 6 Sunday.
  final int daysMask;
  final bool alarm;

  String get title => label ?? kind.labelEs;
}

enum AdjustAction {
  saltar('saltar'),
  mover('mover'),
  extender('extender'),
  agregar('agregar');

  const AdjustAction(this.code);
  final String code;

  static AdjustAction? parse(String? code) {
    for (final a in values) {
      if (a.code == code) return a;
    }
    return null;
  }
}

/// A change for one date only. [mover] keeps the duration and sets a new
/// start; [extender] sets a new end; [agregar] adds a block for that day.
class DayAdjustment {
  const DayAdjustment({
    required this.action,
    this.blockId,
    this.startMin,
    this.endMin,
    this.kind,
    this.label,
    this.alarm = false,
  });

  final AdjustAction action;
  final int? blockId;
  final int? startMin;
  final int? endMin;
  final BlockKind? kind;
  final String? label;
  final bool alarm;
}

enum BlockStatus {
  normal('normal', ''),
  movido('movido', 'movido'),
  acortado('acortado', 'acortado'),
  manana('manana', 'pasa a mañana'),
  saltado('saltado', 'saltado hoy');

  const BlockStatus(this.code, this.labelEs);
  final String code;
  final String labelEs;
}

/// A block placed in the day.
class PlannedBlock {
  const PlannedBlock({
    required this.id,
    required this.kind,
    required this.title,
    required this.startMin,
    required this.endMin,
    required this.alarm,
    required this.status,
    this.fromTemplate = true,
  });

  /// The template id, or `-(index + 1)` for a block added for the day.
  final int id;
  final BlockKind kind;
  final String title;
  final int startMin;
  final int endMin;
  final bool alarm;
  final BlockStatus status;
  final bool fromTemplate;

  /// Takes up time today (not skipped nor moved to tomorrow).
  bool get active =>
      status != BlockStatus.saltado && status != BlockStatus.manana;
  int get minutes => endMin - startMin;

  PlannedBlock copyWith({int? startMin, int? endMin, BlockStatus? status}) =>
      PlannedBlock(
        id: id,
        kind: kind,
        title: title,
        startMin: startMin ?? this.startMin,
        endMin: endMin ?? this.endMin,
        alarm: alarm,
        status: status ?? this.status,
        fromTemplate: fromTemplate,
      );
}

/// Template blocks of [weekday] (1 = Monday … 7 = Sunday) in start order,
/// with their end filled in. A meal without a duration lasts [mealMin].
List<PlannedBlock> templateDay(
  List<BlockTemplate> templates,
  int weekday, {
  List<BlockTemplate>? nextDay,
  int mealMin = 30,
}) {
  final today =
      [
        for (final t in templates)
          if (weekdaysOf(t.daysMask).contains(weekday)) t,
      ]..sort(
        (a, b) => a.startMin != b.startMin
            ? a.startMin.compareTo(b.startMin)
            : a.id.compareTo(b.id),
      );
  final tomorrow = nextDay ?? today;
  final firstTomorrow = tomorrow.isEmpty
      ? null
      : tomorrow.map((t) => t.startMin).reduce((a, b) => a < b ? a : b);
  // Meals are moments: they do not end the block that contains them.
  final boundaries = [
    for (final t in today)
      if (t.kind.role != BlockRole.meal) t.startMin,
  ];
  return [
    for (final t in today)
      PlannedBlock(
        id: t.id,
        kind: t.kind,
        title: t.title,
        startMin: t.startMin,
        endMin:
            t.startMin +
            (t.durationMin ??
                (t.kind.role == BlockRole.meal
                    ? mealMin
                    : _untilNext(t, boundaries, firstTomorrow))),
        alarm: t.alarm,
        status: BlockStatus.normal,
      ),
  ];
}

int _untilNext(BlockTemplate t, List<int> boundaries, int? firstTomorrow) {
  for (final s in boundaries) {
    if (s > t.startMin) return s - t.startMin;
  }
  if (firstTomorrow != null) return firstTomorrow + _day - t.startMin;
  return _day - t.startMin;
}

/// The day's plan: the template of [weekday] with [adjustments] applied.
/// Fixed blocks (work, overtime, sleep) and anything the user moved keep
/// their time; flexible blocks are pushed after them, shortened up to the
/// next fixed block, or moved to tomorrow when less than [minFlexibleMin]
/// minutes are left. Sleep never moves unless the user moves it.
List<PlannedBlock> planDay({
  required List<BlockTemplate> templates,
  required int weekday,
  List<DayAdjustment> adjustments = const [],
  int minFlexibleMin = 15,
  int mealMin = 30,
  List<BlockTemplate>? nextDayTemplates,
}) {
  final blocks = templateDay(
    templates,
    weekday,
    nextDay: nextDayTemplates,
    mealMin: mealMin,
  );
  final pinned = <int>{};
  var added = 0;
  for (final a in adjustments) {
    final i = a.blockId == null
        ? -1
        : blocks.indexWhere((b) => b.id == a.blockId);
    switch (a.action) {
      case AdjustAction.saltar:
        if (i >= 0) blocks[i] = blocks[i].copyWith(status: BlockStatus.saltado);
      case AdjustAction.mover:
        if (i >= 0 && a.startMin != null) {
          final b = blocks[i];
          blocks[i] = b.copyWith(
            startMin: a.startMin,
            endMin: a.startMin! + b.minutes,
            status: BlockStatus.movido,
          );
          pinned.add(b.id);
        }
      case AdjustAction.extender:
        if (i >= 0 && a.endMin != null) {
          final b = blocks[i];
          var end = a.endMin!;
          while (end <= b.startMin) {
            end += _day;
          }
          blocks[i] = b.copyWith(endMin: end, status: BlockStatus.movido);
          pinned.add(b.id);
        }
      case AdjustAction.agregar:
        if (a.startMin != null && a.endMin != null && a.kind != null) {
          added++;
          var end = a.endMin!;
          while (end <= a.startMin!) {
            end += _day;
          }
          final id = -added;
          blocks.add(
            PlannedBlock(
              id: id,
              kind: a.kind!,
              title: a.label ?? a.kind!.labelEs,
              startMin: a.startMin!,
              endMin: end,
              alarm: a.alarm,
              status: BlockStatus.movido,
              fromTemplate: false,
            ),
          );
          pinned.add(id);
        }
    }
  }

  bool isFixed(PlannedBlock b) =>
      b.kind.role == BlockRole.fixed || pinned.contains(b.id);
  final fixed = [
    for (final b in blocks)
      if (b.active && b.kind.role != BlockRole.meal && isFixed(b)) b,
  ]..sort((a, b) => a.startMin.compareTo(b.startMin));

  final result = <PlannedBlock>[];
  var cursor = -1;
  final flexible = [
    for (final b in blocks)
      if (b.active &&
          b.kind.role == BlockRole.flexible &&
          !pinned.contains(b.id))
        b,
  ]..sort((a, b) => a.startMin.compareTo(b.startMin));
  for (final b in flexible) {
    var start = b.startMin > cursor ? b.startMin : cursor;
    // Leave any fixed block that now covers the start.
    var moved = true;
    while (moved) {
      moved = false;
      for (final f in fixed) {
        if (f.startMin <= start && start < f.endMin) {
          start = f.endMin;
          moved = true;
        }
      }
    }
    final limit = fixed
        .where((f) => f.startMin > start)
        .fold<int?>(
          null,
          (m, f) => m == null || f.startMin < m ? f.startMin : m,
        );
    var end = start + b.minutes;
    var status = start == b.startMin ? BlockStatus.normal : BlockStatus.movido;
    if (limit != null && end > limit) {
      end = limit;
      status = BlockStatus.acortado;
    }
    if (end - start < minFlexibleMin || start >= _day) {
      result.add(b.copyWith(status: BlockStatus.manana));
      continue;
    }
    result.add(b.copyWith(startMin: start, endMin: end, status: status));
    cursor = end;
  }

  final placed = {for (final b in result) b.id};
  return [
    for (final b in blocks)
      if (!placed.contains(b.id)) b,
    ...result,
  ]..sort((a, b) {
    final byStart = a.startMin.compareTo(b.startMin);
    return byStart != 0 ? byStart : a.id.compareTo(b.id);
  });
}

/// What is happening at [nowMin] (minutes from today's midnight) and what
/// comes next. [yesterday]'s blocks that run past midnight count, shifted.
({
  PlannedBlock? current,
  PlannedBlock? next,
  int? minutesLeft,
  int? minutesToNext,
})
blockAt({
  required List<PlannedBlock> today,
  required int nowMin,
  List<PlannedBlock> yesterday = const [],
  List<PlannedBlock> tomorrow = const [],
}) {
  final candidates = [
    for (final b in yesterday)
      if (b.active && b.endMin > _day)
        b.copyWith(startMin: b.startMin - _day, endMin: b.endMin - _day),
    for (final b in today)
      if (b.active) b,
  ];
  final containing = [
    for (final b in candidates)
      if (b.startMin <= nowMin && nowMin < b.endMin) b,
  ];
  // A meal inside work is the more specific moment; otherwise the block
  // that started last.
  final meals = [
    for (final b in containing)
      if (b.kind.role == BlockRole.meal) b,
  ];
  final pool = meals.isNotEmpty ? meals : containing;
  final current = pool.isEmpty
      ? null
      : pool.reduce((a, b) => b.startMin >= a.startMin ? b : a);
  final upcoming = [
    for (final b in today)
      if (b.active && b.startMin > nowMin) b,
    for (final b in tomorrow)
      if (b.active)
        b.copyWith(startMin: b.startMin + _day, endMin: b.endMin + _day),
  ]..sort((a, b) => a.startMin.compareTo(b.startMin));
  final next = upcoming.isEmpty ? null : upcoming.first;
  return (
    current: current,
    next: next,
    minutesLeft: current == null ? null : current.endMin - nowMin,
    minutesToNext: next == null ? null : next.startMin - nowMin,
  );
}

/// "1 h 05 min", "12 min" for a countdown.
String countdownEs(int minutes) {
  if (minutes < 1) return 'menos de 1 min';
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return '$h h ${m.toString().padLeft(2, '0')} min';
}
