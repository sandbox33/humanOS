import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

void main() {
  final params = ContextParams.fromAssumptions(Assumptions.defaults());
  // Invented coordinates in open ocean; test data only.
  const work = ContextZone(
    id: 1,
    name: 'Zona A',
    kind: ContextMode.chamba,
    latitude: 10.5,
    longitude: -20.25,
    radiusM: 200,
  );
  const gym = ContextZone(
    id: 2,
    name: 'Zona B',
    kind: ContextMode.entreno,
    latitude: 10.51,
    longitude: -20.25,
    radiusM: 150,
  );
  final t0 = DateTime(2026, 10, 30, 8);

  group('zone validation', () {
    List<ZoneIssue> check({
      String name = 'Zona',
      ContextMode kind = ContextMode.chamba,
      double? lat = 10.5,
      double? lon = -20.25,
      int radius = 200,
      bool active = true,
      int others = 0,
    }) => validateZone(
      name: name,
      kind: kind,
      latitude: lat,
      longitude: lon,
      radiusM: radius,
      active: active,
      activeOthers: others,
      params: params,
    );

    test('a complete zone passes', () => expect(check(), isEmpty));

    test('radius below the minimum is refused', () {
      expect(check(radius: 149), [ZoneIssue.radiusTooSmall]);
      expect(check(radius: 150), isEmpty);
    });

    test('the active-zone cap counts only active zones', () {
      expect(check(others: 5), [ZoneIssue.tooManyActive]);
      expect(check(others: 5, active: false), isEmpty);
      expect(check(others: 4), isEmpty);
    });

    test('name, kind and coordinates are required', () {
      expect(check(name: '  '), [ZoneIssue.nameMissing]);
      expect(check(kind: ContextMode.desconocido), [ZoneIssue.kindInvalid]);
      expect(check(lat: null), [ZoneIssue.coordinatesInvalid]);
      expect(check(lat: 91), [ZoneIssue.coordinatesInvalid]);
      expect(check(lon: -181), [ZoneIssue.coordinatesInvalid]);
    });
  });

  test('distance and overlaps', () {
    expect(distanceMeters(10.5, -20.25, 10.5, -20.25), 0);
    // 0.01° of latitude is about 1.11 km.
    expect(distanceMeters(10.5, -20.25, 10.51, -20.25), closeTo(1112, 5));
    expect(
      overlappingZones(
        latitude: 10.5,
        longitude: -20.25,
        radiusM: 200,
        zones: [work, gym],
      ),
      [work],
    );
    expect(
      overlappingZones(
        latitude: 10.5,
        longitude: -20.25,
        radiusM: 200,
        zones: [work],
        exceptId: 1,
      ),
      isEmpty,
    );
    expect(
      overlappingZones(
        latitude: 10.505,
        longitude: -20.25,
        radiusM: 600,
        zones: [work, gym],
      ),
      [work, gym],
    );
  });

  test('coordinates typed or pasted from a map link', () {
    expect(parseCoordinates('10.5, -20.25'), (
      latitude: 10.5,
      longitude: -20.25,
    ));
    expect(parseCoordinates('geo:10.5,-20.25?z=17'), (
      latitude: 10.5,
      longitude: -20.25,
    ));
    expect(parseCoordinates('https://maps.example/@10.5,-20.25,17z'), (
      latitude: 10.5,
      longitude: -20.25,
    ));
    expect(parseCoordinates('sin coordenadas'), isNull);
    expect(parseCoordinates('95.0, 10.0'), isNull);
  });

  group('current zone from ENTER/EXIT events', () {
    ZoneEvent e(int zone, ContextTransition t, int minutes) => ZoneEvent(
      zoneId: zone,
      transition: t,
      at: t0.add(Duration(minutes: minutes)),
    );

    test('the last event of each zone decides; the newest ENTER wins', () {
      final events = [
        e(1, ContextTransition.enter, 0),
        e(2, ContextTransition.enter, 30),
      ];
      final now = t0.add(const Duration(hours: 1));
      expect(
        currentZone(
          zones: [work, gym],
          events: events,
          now: now,
          params: params,
        )!.zone,
        gym,
      );
      final left = [...events, e(2, ContextTransition.exit, 45)];
      final inside = currentZone(
        zones: [work, gym],
        events: left,
        now: now,
        params: params,
      )!;
      expect(inside.zone, work);
      expect(inside.since, t0);
    });

    test('outside every zone, paused zones and stale entries mean no zone', () {
      final events = [
        e(1, ContextTransition.enter, 0),
        e(1, ContextTransition.exit, 60),
      ];
      expect(
        currentZone(
          zones: [work],
          events: events,
          now: t0.add(const Duration(hours: 2)),
          params: params,
        ),
        isNull,
      );
      const paused = ContextZone(
        id: 1,
        name: 'Zona A',
        kind: ContextMode.chamba,
        latitude: 10.5,
        longitude: -20.25,
        radiusM: 200,
        active: false,
      );
      final entered = [e(1, ContextTransition.enter, 0)];
      expect(
        currentZone(
          zones: [paused],
          events: entered,
          now: t0.add(const Duration(hours: 1)),
          params: params,
        ),
        isNull,
      );
      expect(
        currentZone(
          zones: [work],
          events: entered,
          now: t0.add(Duration(hours: params.staleHours + 1)),
          params: params,
        ),
        isNull,
      );
    });

    test('future events are ignored', () {
      final events = [e(1, ContextTransition.enter, 120)];
      expect(
        currentZone(zones: [work], events: events, now: t0, params: params),
        isNull,
      );
    });
  });

  group('mode inference: location + time + state', () {
    ModeDecision infer({
      ContextMode? location,
      bool planned = false,
      bool quiet = false,
      int? state,
      ModeCorrection? correction,
      DateTime? now,
    }) => inferMode(
      now: now ?? t0,
      locationMode: location,
      inPlannedWork: planned,
      inQuietHours: quiet,
      state: state,
      correction: correction,
      params: params,
    );

    test('a zone gives its kind', () {
      final d = infer(location: ContextMode.entreno);
      expect(d.mode, ContextMode.entreno);
      expect(d.source, ModeSource.ubicacion);
    });

    test('without a zone: planned work, then quiet hours, then unknown', () {
      expect(infer(planned: true).mode, ContextMode.chamba);
      expect(infer(quiet: true).mode, ContextMode.descanso);
      final unknown = infer();
      expect(unknown.mode, ContextMode.desconocido);
      expect(unknown.source, ModeSource.sinDato);
    });

    test('a low state turns an unknown mode into rest and is flagged', () {
      final low = infer(state: 2);
      expect(low.mode, ContextMode.descanso);
      expect(low.source, ModeSource.estado);
      expect(low.lowEnergy, isTrue);
      final gymLow = infer(location: ContextMode.entreno, state: 1);
      expect(gymLow.mode, ContextMode.entreno);
      expect(gymLow.lowEnergy, isTrue);
      expect(infer(state: 4).lowEnergy, isFalse);
    });

    test('a correction wins until it expires or the location changes', () {
      final c = ModeCorrection(
        mode: ContextMode.descanso,
        at: t0,
        locationMode: ContextMode.chamba,
      );
      expect(
        infer(location: ContextMode.chamba, correction: c).source,
        ModeSource.correccion,
      );
      expect(
        infer(location: ContextMode.chamba, correction: c).mode,
        ContextMode.descanso,
      );
      final later = t0.add(Duration(hours: params.correctionHours));
      expect(
        infer(location: ContextMode.chamba, correction: c, now: later).mode,
        ContextMode.chamba,
      );
      expect(
        infer(location: ContextMode.entreno, correction: c).mode,
        ContextMode.entreno,
      );
    });

    test('only chamba and entreno silence reminders', () {
      expect(ContextMode.values.where((m) => m.silences), [
        ContextMode.chamba,
        ContextMode.entreno,
      ]);
      expect(ContextMode.parse('entreno'), ContextMode.entreno);
      expect(ContextMode.parse(null), ContextMode.desconocido);
      expect(ContextTransition.parse('salir'), ContextTransition.exit);
    });
  });
}
