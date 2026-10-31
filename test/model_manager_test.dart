import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humanos/features/asistente/data/model_manager.dart';

void main() {
  late Directory dir;
  // An invented tiny "model" for the tests.
  final bytes = utf8.encode('modelo de prueba');
  const spec = ModelSpec(
    id: 'prueba',
    labelEs: 'Prueba',
    repo: 'ejemplo/modelo',
    fileName: 'modelo.litertlm',
    sizeBytes: 16,
    noteEs: '',
  );
  late String sha;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('humanos-model');
    sha = (await Sha256().hash(bytes)).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ModelManager manager({String? oid, int size = 16, int treeStatus = 200, List<int>? body}) => ModelManager(
        directory: () async => dir,
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer token-de-prueba');
          if (request.url.path.contains('/api/models/')) {
            return http.Response(
              jsonEncode([
                {
                  'path': 'modelo.litertlm',
                  'size': size,
                  'lfs': {'oid': oid ?? sha, 'size': size},
                },
              ]),
              treeStatus,
            );
          }
          return http.Response.bytes(body ?? bytes, 200);
        }),
      );

  test('a download that matches the official size and SHA-256 is installed', () async {
    final m = manager();
    final states = <ModelState>[];
    final result = await m.download(spec, token: 'token-de-prueba', onProgress: (s) => states.add(s.state));
    expect(result.state, ModelState.ready, reason: result.messageEs);
    expect(await m.isInstalled(spec), isTrue);
    expect(states, containsAllInOrder([ModelState.checking, ModelState.downloading, ModelState.verifying]));
  });

  test('a file whose SHA-256 differs is deleted and never used', () async {
    final m = manager(body: utf8.encode('modelo alterado!'));
    final result = await m.download(spec, token: 'token-de-prueba', onProgress: (_) {});
    expect(result.state, ModelState.failed);
    expect(await m.isInstalled(spec), isFalse);
    expect(dir.listSync(recursive: true).whereType<File>(), isEmpty, reason: 'no partial file is left');
  });

  test('without an accepted license or with a changed file nothing is downloaded', () async {
    final denied = await manager(treeStatus: 401).download(spec, token: 'token-de-prueba', onProgress: (_) {});
    expect(denied.messageEs, contains('licencia'));
    final hidden = await manager(oid: '****').download(spec, token: 'token-de-prueba', onProgress: (_) {});
    expect(hidden.messageEs, contains('SHA-256'));
    final resized = await manager(size: 17).download(spec, token: 'token-de-prueba', onProgress: (_) {});
    expect(resized.messageEs, contains('tamaño'));
  });

  test('an imported copy is checked the same way', () async {
    final source = File('${dir.path}/descargado.litertlm')..writeAsBytesSync(bytes);
    final m = manager();
    final result = await m.importFile(spec, source, token: 'token-de-prueba', onProgress: (_) {});
    expect(result.state, ModelState.ready, reason: result.messageEs);
    final wrong = File('${dir.path}/otro.litertlm')..writeAsBytesSync(utf8.encode('corto'));
    final refused = await m.importFile(spec, wrong, token: 'token-de-prueba', onProgress: (_) {});
    expect(refused.state, ModelState.failed);
  });

  test('the official models are listed with their published sizes', () {
    expect(specById('gemma3-1b-int4')!.sizeBytes, 584417280);
    expect(specById('gemma3-270m-q8')!.sizeBytes, 304005120);
    expect(specById('otro'), isNull);
  });
}
