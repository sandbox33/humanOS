import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:humanos_core/humanos_core.dart';

import '../../../app/providers.dart';
import '../../../data/user_db.dart';
import '../../trabajo/data/work_repository.dart' show stampOf;
import '../data/dns_repository.dart';

abstract final class DnsKey {
  /// Last verdict (`FilterStatus.name`) and when it was checked.
  static const status = 'dns_status';
  static const checkedAt = 'dns_checked_at';
}

/// Looks a domain up through the phone's own resolver, so the answer is
/// the one the private DNS gives every app.
abstract class DnsResolver {
  Future<List<String>> lookup(String domain);
}

class SystemDnsResolver implements DnsResolver {
  const SystemDnsResolver();

  @override
  Future<List<String>> lookup(String domain) async {
    try {
      final found = await InternetAddress.lookup(domain).timeout(const Duration(seconds: 8));
      return [for (final a in found) a.address];
    } on Object {
      return const [];
    }
  }
}

final dnsResolverProvider = Provider<DnsResolver>((ref) => const SystemDnsResolver());

final dnsRepositoryProvider = Provider<DnsRepository>(
  (ref) => DnsRepository(ref.watch(userDbProvider), ref.watch(clockProvider)),
);

final dnsDomainsProvider = StreamProvider<List<DnsDomainRow>>((ref) => ref.watch(dnsRepositoryProvider).watchAll());

/// The last stored verdict, or null before the first check.
final filterStatusProvider = Provider<({FilterStatus status, String at})?>((ref) {
  final map = ref.watch(settingsMapProvider).value ?? const {};
  final status = FilterStatus.parse(map[DnsKey.status]);
  final at = map[DnsKey.checkedAt];
  return status == null || at == null ? null : (status: status, at: at);
});

/// Resolves the first blocked and the first allowed domain of the user's
/// lists and stores the verdict. Two lookups; nothing else leaves the
/// phone (no list, no usage data).
Future<FilterStatus> checkFilter(WidgetRef ref) async {
  final rows = await ref.read(dnsRepositoryProvider).all();
  final blocked = rows.where((r) => DnsList.parse(r.list) == DnsList.bloquear).firstOrNull;
  final allowed = rows.where((r) => DnsList.parse(r.list) == DnsList.permitir).firstOrNull;
  final resolver = ref.read(dnsResolverProvider);
  final status = filterStatus(
    blocked: blocked == null ? null : classifyLookup(await resolver.lookup(blocked.domain)),
    allowed: allowed == null ? null : classifyLookup(await resolver.lookup(allowed.domain)),
  );
  final settings = ref.read(settingsRepositoryProvider);
  await settings.set(DnsKey.status, status.name);
  await settings.set(DnsKey.checkedAt, stampOf(ref.read(clockProvider)()));
  return status;
}
