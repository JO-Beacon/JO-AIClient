import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../../models/progress_update.dart';
import 'backup_cancel_token.dart';

/// 上游 Kelivo 的只读加密容器（`KELIVENC` v2）。
///
/// 我们从不写出这个格式；仅在“Kelivo 兼容导入”时解密，把得到的 ZIP
/// 交给上游 v3 归档读取器。
final class KelivoBackupEncryption {
  KelivoBackupEncryption._();

  static const magic = <int>[
    0x4b,
    0x45,
    0x4c,
    0x49,
    0x56,
    0x45,
    0x4e,
    0x43,
  ];
  static const version = 2;
  static const headerLength = 41;
  static const chunkSize = 1024 * 1024;
  static const maxPlaintextBytes = 16 * 1024 * 1024 * 1024;

  static Future<bool> isEncrypted(File file) async {
    final handle = await file.open();
    try {
      final bytes = await handle.read(magic.length);
      if (bytes.length != magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[i] != magic[i]) return false;
      }
      return true;
    } finally {
      await handle.close();
    }
  }

  static Future<File> decryptFile({
    required File source,
    required File destination,
    required String password,
    ProgressCallback? onProgress,
    BackupCancelToken? cancelToken,
  }) async {
    if (password.isEmpty) {
      throw ArgumentError('backup_password_empty');
    }
    if (source.absolute.path == destination.absolute.path) {
      throw ArgumentError('kelivo_backup_encryption_same_file');
    }
    onProgress?.call(const ProgressUpdate(value: 0));
    final handle = await source.open();
    Uint8List? key;
    var complete = false;
    try {
      final header = await _readExactly(handle, headerLength);
      for (var i = 0; i < magic.length; i++) {
        if (header[i] != magic[i]) {
          throw const FormatException('kelivo_backup_encryption_header');
        }
      }
      if (header[8] != version) {
        throw const FormatException('kelivo_backup_encryption_version');
      }
      final data = ByteData.sublistView(Uint8List.fromList(header));
      final plaintextLength = data.getUint64(33, Endian.big);
      if (plaintextLength < 0 || plaintextLength > maxPlaintextBytes) {
        throw const FormatException('kelivo_backup_encryption_size');
      }
      final chunks = max(1, (plaintextLength + chunkSize - 1) ~/ chunkSize);
      if (await source.length() !=
          headerLength + plaintextLength + chunks * 16) {
        throw const FormatException('kelivo_backup_encryption_size');
      }
      final salt = header.sublist(9, 25);
      final noncePrefix = header.sublist(25, 33);
      key = _deriveKey(password, salt);
      await destination.parent.create(recursive: true);
      final output = await destination.open(mode: FileMode.write);
      try {
        var processed = 0;
        for (var index = 0; index < chunks; index++) {
          cancelToken?.throwIfCancelled();
          final count = min(chunkSize, plaintextLength - processed);
          final ciphertext = await _readExactly(handle, count + 16);
          final nonce = Uint8List(12)
            ..setRange(0, 8, noncePrefix)
            ..setRange(8, 12, _uint32Big(index));
          final aad = Uint8List(headerLength + 4)
            ..setRange(0, headerLength, header)
            ..setRange(headerLength, headerLength + 4, _uint32Big(index));
          final cipher = GCMBlockCipher(AESEngine())
            ..init(
              false,
              AEADParameters(KeyParameter(key), 128, nonce, aad),
            );
          await output.writeFrom(cipher.process(ciphertext));
          processed += count;
          onProgress?.call(
            ProgressUpdate(
              value: plaintextLength == 0
                  ? 0.95
                  : processed / plaintextLength * 0.95,
            ),
          );
        }
        if (await handle.readByte() != -1) {
          throw const FormatException('kelivo_backup_encryption_size');
        }
        await output.flush();
        complete = true;
      } on InvalidCipherTextException {
        throw const FormatException('kelivo_backup_decryption_failed');
      } finally {
        await output.close();
      }
    } on FormatException {
      rethrow;
    } finally {
      key?.fillRange(0, key.length, 0);
      await handle.close();
      if (!complete) await _deleteQuietly(destination);
    }
    onProgress?.call(const ProgressUpdate(value: 1));
    return destination;
  }

  static Uint8List _deriveKey(String password, List<int> salt) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(Uint8List.fromList(salt), 600000, 32));
    final key = kdf.process(Uint8List.fromList(utf8.encode(password)));
    return key;
  }

  static Uint8List _uint32Big(int value) {
    final bytes = Uint8List(4);
    ByteData.sublistView(bytes).setUint32(0, value, Endian.big);
    return bytes;
  }

  static Future<Uint8List> _readExactly(
    RandomAccessFile input,
    int length,
  ) async {
    final bytes = Uint8List(length);
    var offset = 0;
    while (offset < length) {
      final count = await input.readInto(bytes, offset);
      if (count == 0) {
        throw const FormatException('kelivo_backup_encryption_size');
      }
      offset += count;
    }
    return bytes;
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
