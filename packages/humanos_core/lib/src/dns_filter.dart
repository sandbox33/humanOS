/// DNS filter (B3). Android does not let an app change the private DNS
/// without root or device-owner rights, so HumanOS keeps the user's lists,
/// exports them for the user's DNS profile and checks whether the filter
/// works. No domain is preset: both lists are the user's.
library;

enum DnsList {
  bloquear('bloquear', 'Bloqueados'),
  permitir('permitir', 'Permitidos');

  const DnsList(this.code, this.labelEs);
  final String code;
  final String labelEs;

  static DnsList parse(String? code) =>
      code == 'permitir' ? DnsList.permitir : DnsList.bloquear;
}

final _label = RegExp(r'^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$');

/// A typed site ("https://www.Ejemplo.com/ruta", "*.ejemplo.com.") as a
/// bare domain ("www.ejemplo.com", "ejemplo.com"); null when it is not a
/// valid domain name.
String? normalizeDomain(String input) {
  var t = input.trim().toLowerCase();
  t = t.replaceFirst(RegExp(r'^[a-z][a-z0-9+.-]*://'), '');
  t = t.split(RegExp(r'[/?#]')).first;
  t = t.split('@').last;
  t = t.replaceFirst(RegExp(r':\d+$'), '');
  if (t.startsWith('*.')) t = t.substring(2);
  if (t.startsWith('||')) t = t.substring(2);
  if (t.endsWith('^')) t = t.substring(0, t.length - 1);
  if (t.endsWith('.')) t = t.substring(0, t.length - 1);
  if (t.isEmpty || t.length > 253) return null;
  final labels = t.split('.');
  if (labels.length < 2) return null;
  if (!labels.every(_label.hasMatch)) return null;
  // A top-level part of only digits is an IP address, not a domain.
  if (RegExp(r'^\d+$').hasMatch(labels.last)) return null;
  return t;
}

enum ExportFormat {
  /// One domain per line (NextDNS denylist / allowlist).
  lineas('lineas', 'Un dominio por línea'),

  /// AdGuard user rules: `||dominio^` to block, `@@||dominio^` to allow.
  adguard('adguard', 'Reglas de AdGuard');

  const ExportFormat(this.code, this.labelEs);
  final String code;
  final String labelEs;
}

/// Text to paste into the user's DNS profile, sorted and without repeats.
String exportDomains(
  Iterable<String> domains, {
  required DnsList list,
  required ExportFormat format,
}) {
  final sorted = {...domains}.toList()..sort();
  return sorted
      .map(
        (d) => switch (format) {
          ExportFormat.lineas => d,
          ExportFormat.adguard =>
            list == DnsList.bloquear ? '||$d^' : '@@||$d^',
        },
      )
      .join('\n');
}

enum LookupResult {
  /// The resolver answered with a null address (how DNS filters block).
  blocked,

  /// A real address: the site would load.
  resolved,

  /// No answer (no network, or a filter that answers "does not exist").
  failed,
}

const _nullAddresses = {'0.0.0.0', '::', '0:0:0:0:0:0:0:0', '127.0.0.1', '::1'};

/// How a lookup of one domain came out, from the addresses returned.
LookupResult classifyLookup(List<String> addresses) {
  if (addresses.isEmpty) return LookupResult.failed;
  return addresses.every(_nullAddresses.contains)
      ? LookupResult.blocked
      : LookupResult.resolved;
}

enum FilterStatus {
  activo('FILTRO ACTIVO'),
  inactivo('FILTRO INACTIVO'),
  sinRed('SIN RED: NO SE PUDO COMPROBAR'),
  sinListas(
    'FILTRO SIN COMPROBAR: AGREGA UN DOMINIO BLOQUEADO Y UNO PERMITIDO',
  );

  const FilterStatus(this.labelEs);
  final String labelEs;

  static FilterStatus? parse(String? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// The filter works when a blocked domain does not resolve to a real
/// address while an allowed one does. A blocked domain that resolves means
/// the filter is off; an allowed one that fails means no verdict.
FilterStatus filterStatus({LookupResult? blocked, LookupResult? allowed}) {
  if (blocked == null || allowed == null) return FilterStatus.sinListas;
  if (blocked == LookupResult.resolved) return FilterStatus.inactivo;
  if (allowed != LookupResult.resolved) return FilterStatus.sinRed;
  return FilterStatus.activo;
}
