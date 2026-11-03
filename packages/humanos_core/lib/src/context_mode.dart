/// Context from the user's own zones (geofence ENTER/EXIT transitions), the
/// clock and the user's state. Rule based, no model: without a zone, a
/// planned work window or quiet hours, the mode stays "desconocido".
///
/// Only transitions with a timestamp are kept; there is no position history.
library;

import 'dart:math' as math;

import 'assumptions.dart';

/// What the user is doing, as far as the rules can tell.
enum ContextMode {
  chamba('chamba', 'CHAMBA'),
  entreno('entreno', 'ENTRENO'),
  descanso('descanso', 'DESCANSO / OCIO'),
  otro('otro', 'OTRO'),
  desconocido('desconocido', 'DESCONOCIDO');

  const ContextMode(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static ContextMode parse(String? code) => ContextMode.values.firstWhere(
    (m) => m.code == code,
    orElse: () => ContextMode.desconocido,
  );

  /// Kinds a zone can have (the user may name "otro" freely).
  static const zoneKinds = [chamba, entreno, descanso, otro];

  /// Reminders are held back in these modes (see `contextRuleFor`).
  bool get silences => this == chamba || this == entreno;
}

class ContextParams {
  const ContextParams({
    required this.minRadiusM,
    required this.defaultRadiusM,
    required this.maxActiveZones,
    required this.responsivenessMin,
    required this.correctionHours,
    required this.staleHours,
    required this.lowStateMax,
  });

  factory ContextParams.fromAssumptions(Assumptions a) => ContextParams(
    minRadiusM: a.integer(A.zoneMinRadiusM),
    defaultRadiusM: a.integer(A.zoneDefaultRadiusM),
    maxActiveZones: a.integer(A.zoneMaxActive),
    responsivenessMin: a.integer(A.geofenceResponsivenessMin),
    correctionHours: a.integer(A.modeCorrectionH),
    staleHours: a.integer(A.contextStaleH),
    lowStateMax: a.integer(A.lowStateMax),
  );

  final int minRadiusM;
  final int defaultRadiusM;
  final int maxActiveZones;
  final int responsivenessMin;
  final int correctionHours;
  final int staleHours;
  final int lowStateMax;
}

/// A zone created by the user. Coordinates live only in the encrypted
/// database (and the encrypted copy the system needs to re-register it).
class ContextZone {
  const ContextZone({
    required this.id,
    required this.name,
    required this.kind,
    required this.latitude,
    required this.longitude,
    required this.radiusM,
    this.active = true,
  });

  final int id;
  final String name;
  final ContextMode kind;
  final double latitude;
  final double longitude;
  final int radiusM;
  final bool active;
}

enum ZoneIssue {
  nameMissing('Ponle un nombre neutro a la zona.'),
  kindInvalid('Elige el tipo de contexto de la zona.'),
  coordinatesInvalid('Las coordenadas no son válidas.'),
  radiusTooSmall('El radio es menor que el mínimo.'),
  tooManyActive('Ya tienes el máximo de zonas activas: pausa una antes.');

  const ZoneIssue(this.messageEs);
  final String messageEs;
}

bool validCoordinates(double? latitude, double? longitude) =>
    latitude != null &&
    longitude != null &&
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180;

/// Problems that keep a zone from being saved; empty when it can be.
/// [activeOthers] counts the other active zones.
List<ZoneIssue> validateZone({
  required String name,
  required ContextMode kind,
  required double? latitude,
  required double? longitude,
  required int radiusM,
  required bool active,
  required int activeOthers,
  required ContextParams params,
}) => [
  if (name.trim().isEmpty) ZoneIssue.nameMissing,
  if (!ContextMode.zoneKinds.contains(kind)) ZoneIssue.kindInvalid,
  if (!validCoordinates(latitude, longitude)) ZoneIssue.coordinatesInvalid,
  if (radiusM < params.minRadiusM) ZoneIssue.radiusTooSmall,
  if (active && activeOthers >= params.maxActiveZones) ZoneIssue.tooManyActive,
];

/// Great-circle distance in metres (haversine, mean Earth radius).
double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusM = 6371008.8;
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
}

/// Other zones whose circle touches the circle given (overlaps make the
/// current zone ambiguous; the user is warned, never blocked).
List<ContextZone> overlappingZones({
  required double latitude,
  required double longitude,
  required int radiusM,
  required List<ContextZone> zones,
  int? exceptId,
}) => [
  for (final z in zones)
    if (z.id != exceptId &&
        distanceMeters(latitude, longitude, z.latitude, z.longitude) <
            radiusM + z.radiusM)
      z,
];

/// Reads "lat, lon" typed or pasted from a map link ("geo:lat,lon",
/// "…@lat,lon,17z", "…?q=lat,lon"). Null when nothing valid is found.
({double latitude, double longitude})? parseCoordinates(String text) {
  final number = r'(-?\d{1,3}(?:\.\d+)?)';
  final match = RegExp('$number\\s*,\\s*$number').firstMatch(text);
  if (match == null) return null;
  final lat = double.tryParse(match.group(1)!);
  final lon = double.tryParse(match.group(2)!);
  if (!validCoordinates(lat, lon)) return null;
  return (latitude: lat!, longitude: lon!);
}

enum ContextTransition {
  enter('entrar'),
  exit('salir');

  const ContextTransition(this.code);
  final String code;

  static ContextTransition? parse(String? code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// One ENTER or EXIT of a zone.
class ZoneEvent {
  const ZoneEvent({
    required this.zoneId,
    required this.transition,
    required this.at,
  });

  final int zoneId;
  final ContextTransition transition;
  final DateTime at;
}

/// The zone the user is in: among active zones whose last event is an
/// ENTER newer than the stale limit, the most recent one wins. Null when
/// outside every zone or when nothing recent is known.
({ContextZone zone, DateTime since})? currentZone({
  required List<ContextZone> zones,
  required List<ZoneEvent> events,
  required DateTime now,
  required ContextParams params,
}) {
  final last = <int, ZoneEvent>{};
  for (final e in events) {
    if (e.at.isAfter(now)) continue;
    final previous = last[e.zoneId];
    if (previous == null || !e.at.isBefore(previous.at)) last[e.zoneId] = e;
  }
  final staleBefore = now.subtract(Duration(hours: params.staleHours));
  ({ContextZone zone, DateTime since})? best;
  for (final z in zones) {
    if (!z.active) continue;
    final e = last[z.id];
    if (e == null || e.transition != ContextTransition.enter) continue;
    if (e.at.isBefore(staleBefore)) continue;
    if (best == null || e.at.isAfter(best.since)) best = (zone: z, since: e.at);
  }
  return best;
}

/// A one-tap correction of the mode by the user.
class ModeCorrection {
  const ModeCorrection({
    required this.mode,
    required this.at,
    required this.locationMode,
  });

  final ContextMode mode;
  final DateTime at;

  /// What the location said when the user corrected it; a new location
  /// context ends the correction.
  final ContextMode? locationMode;
}

enum ModeSource { correccion, ubicacion, plan, horario, estado, sinDato }

class ModeDecision {
  const ModeDecision({
    required this.mode,
    required this.source,
    required this.reasonEs,
    required this.lowEnergy,
  });

  final ContextMode mode;
  final ModeSource source;
  final String reasonEs;

  /// The user's last state is at or below the low-energy limit.
  final bool lowEnergy;
}

/// Mode = location + time + state, in this order:
///
/// 1. a correction of the last [ContextParams.correctionHours] hours whose
///    location context has not changed since;
/// 2. the kind of the zone the user is in;
/// 3. a planned work window now → chamba; quiet hours → descanso;
/// 4. otherwise desconocido, or descanso when the state is low.
ModeDecision inferMode({
  required DateTime now,
  required ContextMode? locationMode,
  required bool inPlannedWork,
  required bool inQuietHours,
  required int? state,
  required ModeCorrection? correction,
  required ContextParams params,
}) {
  final lowEnergy = state != null && state <= params.lowStateMax;
  if (correction != null &&
      !correction.at.isAfter(now) &&
      now.difference(correction.at) < Duration(hours: params.correctionHours) &&
      correction.locationMode == locationMode) {
    return ModeDecision(
      mode: correction.mode,
      source: ModeSource.correccion,
      reasonEs: 'Lo marcaste tú.',
      lowEnergy: lowEnergy,
    );
  }
  if (locationMode != null && locationMode != ContextMode.desconocido) {
    return ModeDecision(
      mode: locationMode,
      source: ModeSource.ubicacion,
      reasonEs: 'Estás en una de tus zonas.',
      lowEnergy: lowEnergy,
    );
  }
  if (inPlannedWork) {
    return ModeDecision(
      mode: ContextMode.chamba,
      source: ModeSource.plan,
      reasonEs: 'Tu plantilla de trabajo marca esta hora.',
      lowEnergy: lowEnergy,
    );
  }
  if (inQuietHours) {
    return ModeDecision(
      mode: ContextMode.descanso,
      source: ModeSource.horario,
      reasonEs: 'Horas de silencio.',
      lowEnergy: lowEnergy,
    );
  }
  if (lowEnergy) {
    return const ModeDecision(
      mode: ContextMode.descanso,
      source: ModeSource.estado,
      reasonEs: 'Marcaste energía baja.',
      lowEnergy: true,
    );
  }
  return const ModeDecision(
    mode: ContextMode.desconocido,
    source: ModeSource.sinDato,
    reasonEs: 'Sin zona, sin trabajo planificado y sin estado reciente.',
    lowEnergy: false,
  );
}
