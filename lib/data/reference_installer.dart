import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Result of preparing the bundled reference database.
class ReferenceInstall {
  const ReferenceInstall({required this.path, required this.updated});

  /// Path of the installed copy, or null when the APK has no database
  /// (development builds without the CI asset).
  final String? path;

  /// The copy was (re)written in this launch.
  final bool updated;
}

/// Copies `assets/db/reference.sqlite` to app storage on first launch and
/// whenever the bundled `.sha256` changes (a new ETL release, which also
/// covers a change of `PRAGMA user_version`).
class ReferenceInstaller {
  ReferenceInstaller({AssetBundle? bundle, Future<Directory> Function()? directory})
      : _bundle = bundle ?? rootBundle,
        _directory = directory ?? getApplicationSupportDirectory;

  static const assetDb = 'assets/db/reference.sqlite';
  static const assetSha = 'assets/db/reference.sqlite.sha256';

  final AssetBundle _bundle;
  final Future<Directory> Function() _directory;

  Future<ReferenceInstall> ensureInstalled() async {
    final String bundledSha;
    try {
      bundledSha = (await _bundle.loadString(assetSha, cache: false))
          .trim()
          .split(RegExp(r'\s+'))
          .first;
    } on Object {
      return const ReferenceInstall(path: null, updated: false);
    }
    final dir = await _directory();
    final target = File(p.join(dir.path, 'reference.sqlite'));
    final marker = File(p.join(dir.path, 'reference.sqlite.sha256'));
    final installedSha =
        await marker.exists() ? (await marker.readAsString()).trim() : '';
    if (installedSha == bundledSha && await target.exists()) {
      return ReferenceInstall(path: target.path, updated: false);
    }
    final data = await _bundle.load(assetDb);
    final temp = File('${target.path}.tmp');
    await temp.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    await temp.rename(target.path);
    await marker.writeAsString(bundledSha, flush: true);
    return ReferenceInstall(path: target.path, updated: true);
  }
}
