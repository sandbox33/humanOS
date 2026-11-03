import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// An official model file the assistant can use. The size is the one
/// published by the source (checked in CI); the SHA-256 is read from the
/// source's API with the user's own token, because a license-gated file
/// only shows it to accounts that accepted the license.
class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.labelEs,
    required this.repo,
    required this.fileName,
    required this.sizeBytes,
    required this.noteEs,
  });

  final String id;
  final String labelEs;
  final String repo;
  final String fileName;
  final int sizeBytes;
  final String noteEs;

  Uri get fileUrl => Uri.parse('https://huggingface.co/$repo/resolve/main/$fileName');
  Uri get treeUrl => Uri.parse('https://huggingface.co/api/models/$repo/tree/main');
  String get pageUrl => 'https://huggingface.co/$repo';
  String get sizeEs => '${(sizeBytes / (1024 * 1024)).round()} MB';
}

/// Gemma 3 270M has no official INT4 file for LiteRT-LM (only a web
/// `.task`); its official file is INT8. Gemma 3 1B INT4 is the brief's
/// alternative. The evaluation on the phone decides.
const modelSpecs = [
  ModelSpec(
    id: 'gemma3-1b-int4',
    labelEs: 'Gemma 3 1B (INT4)',
    repo: 'litert-community/Gemma3-1B-IT',
    fileName: 'gemma3-1b-it-int4.litertlm',
    sizeBytes: 584417280,
    noteEs: 'Más preciso; necesita más memoria y es más lento.',
  ),
  ModelSpec(
    id: 'gemma3-270m-q8',
    labelEs: 'Gemma 3 270M (INT8)',
    repo: 'litert-community/gemma-3-270m-it',
    fileName: 'gemma3-270m-it-q8.litertlm',
    sizeBytes: 304005120,
    noteEs: 'Más pequeño y rápido; puede acertar menos.',
  ),
];

ModelSpec? specById(String? id) {
  for (final s in modelSpecs) {
    if (s.id == id) return s;
  }
  return null;
}

enum ModelState { missing, checking, downloading, verifying, ready, failed }

class ModelStatus {
  const ModelStatus(this.state, {this.receivedBytes = 0, this.messageEs});

  final ModelState state;
  final int receivedBytes;
  final String? messageEs;
}

final _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// Downloads or imports a model into the app's own storage. The file is
/// hashed while it is copied and used only when its size and SHA-256 match
/// the official ones; otherwise it is deleted.
class ModelManager {
  ModelManager({Future<Directory> Function()? directory, http.Client? client})
      : _directory = directory ?? getApplicationSupportDirectory,
        _client = client ?? http.Client();

  final Future<Directory> Function() _directory;
  final http.Client _client;

  Future<File> fileFor(ModelSpec spec) async {
    final dir = Directory('${(await _directory()).path}/modelos');
    await dir.create(recursive: true);
    return File('${dir.path}/${spec.fileName}');
  }

  Future<bool> isInstalled(ModelSpec spec) async {
    final file = await fileFor(spec);
    return file.existsSync() && file.lengthSync() == spec.sizeBytes;
  }

  Future<void> remove(ModelSpec spec) async {
    final file = await fileFor(spec);
    if (file.existsSync()) await file.delete();
  }

  Map<String, String> _auth(String token) => {'Authorization': 'Bearer ${token.trim()}'};

  /// The official SHA-256 of [spec], or a Spanish explanation of why it is
  /// not available.
  Future<({String? sha256, String? problemEs})> officialSha256(ModelSpec spec, String token) async {
    final http.Response response;
    try {
      response = await _client.get(spec.treeUrl, headers: _auth(token));
    } on Object catch (e) {
      return (sha256: null, problemEs: 'Sin conexión con la fuente del modelo: $e');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      return (sha256: null, problemEs: 'El token no sirve o no aceptaste la licencia de Gemma en ${spec.pageUrl}.');
    }
    if (response.statusCode != 200) {
      return (sha256: null, problemEs: 'La fuente respondió ${response.statusCode}.');
    }
    try {
      for (final entry in jsonDecode(response.body) as List<dynamic>) {
        final map = entry as Map<String, dynamic>;
        if (map['path'] != spec.fileName) continue;
        final lfs = map['lfs'] as Map<String, dynamic>?;
        final oid = (lfs?['oid'] as String?)?.toLowerCase();
        final size = (lfs?['size'] ?? map['size']) as int?;
        if (size != spec.sizeBytes) {
          return (sha256: null, problemEs: 'El archivo oficial cambió de tamaño: hace falta actualizar la app.');
        }
        if (oid == null || !_hex64.hasMatch(oid)) {
          return (sha256: null, problemEs: 'La fuente no mostró el SHA-256: revisa que aceptaste la licencia.');
        }
        return (sha256: oid, problemEs: null);
      }
    } on Object {
      return (sha256: null, problemEs: 'La respuesta de la fuente no se pudo leer.');
    }
    return (sha256: null, problemEs: 'La fuente ya no tiene ${spec.fileName}.');
  }

  Future<ModelStatus> _install(
    ModelSpec spec,
    String expectedSha256,
    Stream<List<int>> chunks,
    void Function(ModelStatus) onProgress,
  ) async {
    final target = await fileFor(spec);
    final temp = File('${target.path}.parcial');
    final sink = temp.openWrite();
    final hash = Sha256().newHashSink();
    var received = 0;
    try {
      await for (final chunk in chunks) {
        received += chunk.length;
        if (received > spec.sizeBytes) throw const FormatException('más grande de lo esperado');
        sink.add(chunk);
        hash.add(chunk);
        onProgress(ModelStatus(ModelState.downloading, receivedBytes: received));
      }
      await sink.close();
    } on Object catch (e) {
      await sink.close();
      if (temp.existsSync()) await temp.delete();
      return ModelStatus(ModelState.failed, messageEs: 'Se interrumpió ($e): no quedó nada a medias.');
    }
    onProgress(ModelStatus(ModelState.verifying, receivedBytes: received));
    hash.close();
    final digest = (await hash.hash()).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (received != spec.sizeBytes || digest != expectedSha256) {
      await temp.delete();
      return const ModelStatus(
        ModelState.failed,
        messageEs: 'El archivo no coincide con el oficial (tamaño o SHA-256): se borró.',
      );
    }
    if (target.existsSync()) await target.delete();
    await temp.rename(target.path);
    return ModelStatus(ModelState.ready, receivedBytes: received);
  }

  /// Downloads [spec] from its official source with the user's [token].
  /// The caller checks first that the network is Wi-Fi.
  Future<ModelStatus> download(ModelSpec spec, {required String token, required void Function(ModelStatus) onProgress}) async {
    onProgress(const ModelStatus(ModelState.checking));
    final official = await officialSha256(spec, token);
    if (official.sha256 == null) return ModelStatus(ModelState.failed, messageEs: official.problemEs);
    final request = http.Request('GET', spec.fileUrl)..headers.addAll(_auth(token));
    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } on Object catch (e) {
      return ModelStatus(ModelState.failed, messageEs: 'Sin conexión con la fuente del modelo: $e');
    }
    if (response.statusCode != 200) {
      return ModelStatus(ModelState.failed, messageEs: 'La descarga respondió ${response.statusCode}.');
    }
    return _install(spec, official.sha256!, response.stream, onProgress);
  }

  /// Imports a copy the user downloaded; it must match the official file.
  Future<ModelStatus> importFile(
    ModelSpec spec,
    File source, {
    required String token,
    required void Function(ModelStatus) onProgress,
  }) async {
    onProgress(const ModelStatus(ModelState.checking));
    if (source.lengthSync() != spec.sizeBytes) {
      return const ModelStatus(ModelState.failed, messageEs: 'Ese archivo no tiene el tamaño del oficial.');
    }
    final official = await officialSha256(spec, token);
    if (official.sha256 == null) return ModelStatus(ModelState.failed, messageEs: official.problemEs);
    return _install(spec, official.sha256!, source.openRead(), onProgress);
  }
}
