import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Encrypted backup container.
///
/// Layout: `HOS3` magic (4 bytes) · format version (1) · PBKDF2 iterations
/// (uint32, big endian) · salt (16) · nonce (12) · AES-256-GCM ciphertext ·
/// GCM tag (16). The plaintext is gzip-compressed JSON. The key comes from
/// the user's password with PBKDF2-HMAC-SHA256; nothing is sent anywhere.
class ExportCrypto {
  static const magic = [0x48, 0x4F, 0x53, 0x33];
  static const formatVersion = 1;
  static const defaultIterations = 310000;
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _macLength = 16;
  static const _headerLength = 4 + 1 + 4 + _saltLength + _nonceLength;

  static Future<SecretKey> _key(String password, List<int> salt, int iterations) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
          .deriveKeyFromPassword(password: password, nonce: salt);

  /// Encrypts [json] with [password].
  static Future<Uint8List> encryptJson(
    String json,
    String password, {
    int iterations = defaultIterations,
  }) async {
    if (password.length < 8) {
      throw const ExportException('La contraseña debe tener al menos 8 caracteres.');
    }
    final algorithm = AesGcm.with256bits();
    final salt = SecretKeyData.random(length: _saltLength).bytes;
    final nonce = algorithm.newNonce();
    final key = await _key(password, salt, iterations);
    final compressed = GZipCodec(level: 6).encode(utf8.encode(json));
    final box = await algorithm.encrypt(compressed, secretKey: key, nonce: nonce);
    final header = BytesBuilder()
      ..add(magic)
      ..addByte(formatVersion)
      ..add((ByteData(4)..setUint32(0, iterations)).buffer.asUint8List())
      ..add(salt)
      ..add(nonce);
    return (BytesBuilder()
          ..add(header.toBytes())
          ..add(box.cipherText)
          ..add(box.mac.bytes))
        .toBytes();
  }

  /// Decrypts a container produced by [encryptJson].
  static Future<String> decryptJson(Uint8List data, String password) async {
    if (data.length < _headerLength + _macLength ||
        !const ListEquality().equals(data.sublist(0, 4), magic)) {
      throw const ExportException('El archivo no es una copia de HumanOS.');
    }
    if (data[4] != formatVersion) {
      throw ExportException('Versión de copia no soportada (${data[4]}).');
    }
    final iterations = ByteData.sublistView(data, 5, 9).getUint32(0);
    final salt = data.sublist(9, 9 + _saltLength);
    final nonce = data.sublist(9 + _saltLength, _headerLength);
    final cipherText = data.sublist(_headerLength, data.length - _macLength);
    final mac = Mac(data.sublist(data.length - _macLength));
    final key = await _key(password, salt, iterations);
    final List<int> clear;
    try {
      clear = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: key,
      );
    } on SecretBoxAuthenticationError {
      throw const ExportException('Contraseña incorrecta o archivo dañado.');
    }
    return utf8.decode(GZipCodec().decode(clear));
  }
}

class ExportException implements Exception {
  const ExportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Minimal list equality (avoids a dependency for one comparison).
class ListEquality {
  const ListEquality();
  bool equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
