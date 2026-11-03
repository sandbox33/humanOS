import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanos/data/seed.dart';
import 'package:humanos/data/settings.dart';
import 'package:humanos/data/user_db.dart';
import 'package:humanos/features/filtro/domain/dns_model.dart';
import 'package:humanos/features/filtro/presentation/filtro_screen.dart';
import 'package:humanos_core/humanos_core.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'support/fixtures.dart';

/// Answers like a DNS filter would (reserved example domains only).
class FakeResolver implements DnsResolver {
  FakeResolver(this.answers);
  final Map<String, List<String>> answers;
  final asked = <String>[];

  @override
  Future<List<String>> lookup(String domain) async {
    asked.add(domain);
    return answers[domain] ?? const [];
  }
}

void main() {
  late UserDb db;
  String? clipboard;

  setUpAll(() => initializeDateFormatting('es'));
  setUp(() async {
    db = memoryUserDb();
    await seedIfNeeded(db);
    await insertTestProfile(db);
    clipboard = null;
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester, FakeResolver resolver) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(testApp(
      db: db,
      now: DateTime(2026, 11, 3, 9),
      extra: [dnsResolverProvider.overrideWithValue(resolver)],
      child: const FiltroScreen(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> add(WidgetTester tester, int panel, String text) async {
    await tester.tap(find.text('AGREGAR').at(panel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('AGREGAR')));
    await tester.pumpAndSettle();
  }

  testWidgets('no domain is preset; without both lists the filter is not judged', (tester) async {
    final resolver = FakeResolver(const {});
    await open(tester, resolver);
    expect(await db.select(db.dnsDomains).get(), isEmpty);
    await tester.tap(find.text('COMPROBAR AHORA'));
    await tester.pumpAndSettle();
    expect(resolver.asked, isEmpty);
    expect(await SettingsRepository(db).get(DnsKey.status), FilterStatus.sinListas.name);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('typed sites are stored as domains and exported for the DNS profile', (tester) async {
    await open(tester, FakeResolver(const {}));
    await add(tester, 0, 'https://www.Bloqueado.example.com/inicio');
    await add(tester, 0, 'otro.example.net');
    await add(tester, 1, 'permitido.example.org');
    await add(tester, 0, 'no es dominio');
    expect(find.textContaining('Eso no es un dominio'), findsOneWidget);

    final rows = {for (final r in await db.select(db.dnsDomains).get()) r.domain: r.list};
    expect(rows, {
      'www.bloqueado.example.com': 'bloquear',
      'otro.example.net': 'bloquear',
      'permitido.example.org': 'permitir',
    });

    await tester.tap(find.text('COPIAR REGLAS ADGUARD').first);
    await tester.pump();
    expect(clipboard, '||otro.example.net^\n||www.bloqueado.example.com^');
    await tester.tap(find.text('COPIAR LISTA').last);
    await tester.pump();
    expect(clipboard, 'permitido.example.org');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('active when the blocked domain is stopped and the allowed one loads; inactive otherwise', (tester) async {
    await db.into(db.dnsDomains).insert(DnsDomainsCompanion.insert(domain: 'b.example.com', list: 'bloquear', createdAt: '2026-11-03T08:00:00'));
    await db.into(db.dnsDomains).insert(DnsDomainsCompanion.insert(domain: 'p.example.com', list: 'permitir', createdAt: '2026-11-03T08:00:00'));

    final on = FakeResolver(const {'b.example.com': ['0.0.0.0'], 'p.example.com': ['192.0.2.10']});
    await open(tester, on);
    await tester.tap(find.text('COMPROBAR AHORA'));
    await tester.pumpAndSettle();
    expect(on.asked, ['b.example.com', 'p.example.com']);
    expect(find.text('FILTRO ACTIVO'), findsWidgets);
    expect(await SettingsRepository(db).get(DnsKey.checkedAt), '2026-11-03T09:00:00');
    await tester.pumpWidget(const SizedBox.shrink());

    final off = FakeResolver(const {'b.example.com': ['192.0.2.20'], 'p.example.com': ['192.0.2.10']});
    await open(tester, off);
    await tester.tap(find.text('COMPROBAR AHORA'));
    await tester.pumpAndSettle();
    expect(find.text('FILTRO INACTIVO'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
