import 'package:humanos_core/humanos_core.dart';
import 'package:test/test.dart';

// Invented and reserved example domains only (RFC 2606).
void main() {
  group('domains', () {
    test('typed sites become bare domains', () {
      expect(
        normalizeDomain('https://www.Ejemplo.com/ruta?x=1'),
        'www.ejemplo.com',
      );
      expect(normalizeDomain('*.ejemplo.org.'), 'ejemplo.org');
      expect(normalizeDomain('||ejemplo.net^'), 'ejemplo.net');
      expect(normalizeDomain(' sub.ejemplo.com:443 '), 'sub.ejemplo.com');
    });

    test('anything that is not a domain is refused', () {
      for (final bad in [
        '',
        'ejemplo',
        '192.168.1.1',
        'eje mplo.com',
        '-mal.com',
        'mal-.com',
        'a..b.com',
      ]) {
        expect(normalizeDomain(bad), isNull, reason: bad);
      }
    });

    test(
      'export for the DNS profile: one per line or AdGuard rules, sorted, no repeats',
      () {
        final domains = ['b.example.com', 'a.example.com', 'b.example.com'];
        expect(
          exportDomains(
            domains,
            list: DnsList.bloquear,
            format: ExportFormat.lineas,
          ),
          'a.example.com\nb.example.com',
        );
        expect(
          exportDomains(
            domains,
            list: DnsList.bloquear,
            format: ExportFormat.adguard,
          ),
          '||a.example.com^\n||b.example.com^',
        );
        expect(
          exportDomains(
            ['ok.example.com'],
            list: DnsList.permitir,
            format: ExportFormat.adguard,
          ),
          '@@||ok.example.com^',
        );
        expect(DnsList.parse('permitir'), DnsList.permitir);
        expect(DnsList.parse('x'), DnsList.bloquear);
      },
    );
  });

  group('verification', () {
    test('null addresses mean blocked, real ones resolved, none failed', () {
      expect(classifyLookup(['0.0.0.0']), LookupResult.blocked);
      expect(classifyLookup(['0.0.0.0', '::']), LookupResult.blocked);
      expect(classifyLookup(['93.184.216.34']), LookupResult.resolved);
      expect(
        classifyLookup(['0.0.0.0', '93.184.216.34']),
        LookupResult.resolved,
      );
      expect(classifyLookup(const []), LookupResult.failed);
    });

    test(
      'active only when the blocked domain is stopped and the allowed one resolves',
      () {
        expect(
          filterStatus(
            blocked: LookupResult.blocked,
            allowed: LookupResult.resolved,
          ),
          FilterStatus.activo,
        );
        expect(
          filterStatus(
            blocked: LookupResult.failed,
            allowed: LookupResult.resolved,
          ),
          FilterStatus.activo,
        );
        expect(
          filterStatus(
            blocked: LookupResult.resolved,
            allowed: LookupResult.resolved,
          ),
          FilterStatus.inactivo,
        );
        expect(
          filterStatus(
            blocked: LookupResult.resolved,
            allowed: LookupResult.failed,
          ),
          FilterStatus.inactivo,
        );
        expect(
          filterStatus(
            blocked: LookupResult.failed,
            allowed: LookupResult.failed,
          ),
          FilterStatus.sinRed,
        );
        expect(
          filterStatus(blocked: LookupResult.blocked),
          FilterStatus.sinListas,
        );
        expect(filterStatus(), FilterStatus.sinListas);
        for (final s in FilterStatus.values) {
          expect(FilterStatus.parse(s.name), s);
        }
      },
    );
  });
}
