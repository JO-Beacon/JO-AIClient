import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

import '../../models/progress_update.dart';
import 'backup_cancel_token.dart';

/// 返回 null 表示用户取消。`retry` 表示上一次口令错误。
typedef JoaiclientPasswordPrompt =
    Future<String?> Function({required bool retry});

/// JO-AIClient 外部归档的容器。
///
/// v1 只做完整性校验（payload 长度 + SHA-256），不加密。
/// v2 在同样的头体系里加入 AES-256-GCM 保护；容器版本与内层 ZIP 的
/// 归档格式相互独立。v2 读取器必须继续接受 v1。
final class JoaiclientArchive {
  JoaiclientArchive._();

  static const magic = <int>[0x4a, 0x4f, 0x41, 0x49, 0x43, 0x4c, 0x4e, 0x54];
  static const formatVersion = 1;
  static const protectionNone = 0;
  static const payloadZip = 1;
  static const headerLength = 56;

  static const formatVersionV2 = 2;
  static const protectionAesGcm = 1;
  static const v2HeaderLength = 88;
  static const v2KdfIterations = 600000;
  static const v2ChunkSize = 1024 * 1024;
  static const maxPlaintextBytes = 16 * 1024 * 1024 * 1024;

  /// 密码为空表示 v1 明文；非空表示 v2 加密。
  static Future<File> wrapZipPayload({
    required File zipFile,
    required File outputFile,
    String? password,
    ProgressCallback? onProgress,
    BackupCancelToken? cancelToken,
  }) {
    if (password != null && password.isEmpty) {
      throw ArgumentError('joaiclient_password_empty');
    }
    if (password == null) {
      return _wrapV2Plain(
        zipFile: zipFile,
        outputFile: outputFile,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }
    return _wrapV2Encrypted(
      zipFile: zipFile,
      outputFile: outputFile,
      password: password,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  static Future<File> _wrapV1({
    required File zipFile,
    required File outputFile,
    ProgressCallback? onProgress,
    BackupCancelToken? cancelToken,
  }) async {
    if (zipFile.absolute.path == outputFile.absolute.path) {
      throw ArgumentError('zipFile and outputFile must differ');
    }
    onProgress?.call(const ProgressUpdate(value: 0));
    final payloadLength = await zipFile.length();
    var hashed = 0;
    final digest = await sha256
        .bind(
          zipFile.openRead().map((chunk) {
            cancelToken?.throwIfCancelled();
            hashed += chunk.length;
            onProgress?.call(
              ProgressUpdate(
                value: payloadLength == 0 ? 0.5 : hashed / payloadLength * 0.5,
              ),
            );
            return chunk;
          }),
        )
        .first;
    final header = _encodeHeader(payloadLength, digest.bytes);
    await outputFile.parent.create(recursive: true);
    final output = outputFile.openWrite(mode: FileMode.write);
    Object? writeError;
    try {
      output.add(header);
      var copied = 0;
      await for (final chunk in zipFile.openRead()) {
        cancelToken?.throwIfCancelled();
        output.add(chunk);
        copied += chunk.length;
        onProgress?.call(
          ProgressUpdate(
            value: payloadLength == 0 ? 1 : 0.5 + copied / payloadLength * 0.5,
          ),
        );
      }
      await output.flush();
    } catch (error) {
      writeError = error;
    } finally {
      await output.close();
    }
    if (writeError != null) {
      await _deleteQuietly(outputFile);
      Error.throwWithStackTrace(writeError, StackTrace.current);
    }
    onProgress?.call(const ProgressUpdate(value: 1));
    return outputFile;
  }

  static Future<File> wrapV1ForTesting({
    required File zipFile,
    required File outputFile,
    ProgressCallback? onProgress,
    BackupCancelToken? cancelToken,
  }) => _wrapV1(
    zipFile: zipFile,
    outputFile: outputFile,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );

  static Future<File> _wrapV2Plain({
    required File zipFile,
    required File outputFile,
    ProgressCallback? onProgress,
    BackupCancelToken? cancelToken,
  }) async {
    if (zipFile.absolute.path == outputFile.absolute.path) {
      throw ArgumentError('zipFile and outputFile must differ');
    }
    onProgress?.call(const ProgressUpdate(value: 0));
    final plaintextLength = await zipFile.length();
    if (plaintextLength > maxPlaintextBytes) {
      throw const FormatException('joaiclient_payload_size');
    }
    final digest = await _hashFile(
      zipFile,
      onProgress: onProgress,
      cancelToken: cancelToken,
      start: 0,
      span: 0.4,
    );
    final header = _encodeV2Header(
      protection: protectionNone,
      plaintextLength: plaintextLength,
      plaintextSha256: digest,
    );
    await outputFile.parent.create(recursive: true);
    final input = await zipFile.open();
    final output = await outputFile.open(mode: FileMode.write);
    var complete = false;
    try {
      await output.writeFrom(header);
      var processed = 0;
      while (processed < plaintextLength) {
        cancelToken?.throwIfCancelled();
        final count = min(v2ChunkSize, plaintextLength - processed);
        await output.writeFrom(await _readExactly(input, count));
        processed += count;
        onProgress?.call(
          ProgressUpdate(
            value: 0.4 + processed / plaintextLength * 0.6,
          ),
        );
      }
      if (await input.readByte() != -1) {
        throw const FormatException('joaiclient_payload_size');
      }
      await output.flush();
      complete = true;
    } finally {
      await input.close();
      await output.close();
      if (!complete) await _deleteQuietly(outputFile);
    }
    onProgress?.call(const ProgressUpdate(value: 1));
    return outputFile;
  }

  static Future<File> _wrapV2Encrypted({
    required File zipFile,
    required File outputFile,
    required String password,
    ProgressCallback? onProgress,
    BackupCancelToken? cancelToken,
  }) async {
    if (zipFile.absolute.path == outputFile.absolute.path) {
      throw ArgumentError('zipFile and outputFile must differ');
    }
    onProgress?.call(const ProgressUpdate(value: 0));
    final plaintextLength = await zipFile.length();
    if (plaintextLength > maxPlaintextBytes) {
      throw const FormatException('joaiclient_payload_size');
    }
    final digest = await _hashFile(
      zipFile,
      onProgress: onProgress,
      cancelToken: cancelToken,
      start: 0,
      span: 0.4,
    );
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );
    final noncePrefix = Uint8List.fromList(
      List<int>.generate(8, (_) => random.nextInt(256)),
    );
    final header = _encodeV2Header(
      protection: protectionAesGcm,
      plaintextLength: plaintextLength,
      plaintextSha256: digest,
      salt: salt,
      noncePrefix: noncePrefix,
    );
    final key = _deriveKey(password, salt, v2KdfIterations);
    final chunks = _chunkCount(plaintextLength);
    await outputFile.parent.create(recursive: true);
    final input = await zipFile.open();
    final output = await outputFile.open(mode: FileMode.write);
    var complete = false;
    try {
      await output.writeFrom(header);
      var processed = 0;
      for (var index = 0; index < chunks; index++) {
        cancelToken?.throwIfCancelled();
        final count = min(
          v2ChunkSize,
          plaintextLength - processed,
        );
        final plaintext = await _readExactly(input, count);
        final cipher = _cipher(
          encrypt: true,
          key: key,
          noncePrefix: noncePrefix,
          index: index,
          header: header,
        );
        await output.writeFrom(cipher.process(plaintext));
        processed += count;
        onProgress?.call(
          ProgressUpdate(
            value: plaintextLength == 0
                ? 0.9
                : 0.4 + processed / plaintextLength * 0.6,
          ),
        );
      }
      if (await input.readByte() != -1) {
        throw const FormatException('joaiclient_payload_size');
      }
      await output.flush();
      complete = true;
    } catch (error) {
      if (error is InvalidCipherTextException) {
        throw const FormatException('joaiclient_encryption_failed');
      }
      rethrow;
    } finally {
      key.fillRange(0, key.length, 0);
      await input.close();
      await output.close();
      if (!complete) await _deleteQuietly(outputFile);
    }
    onProgress?.call(const ProgressUpdate(value: 1));
    return outputFile;
  }

  static Future<bool> isJoaiclient(File file) async {
    final handle = await file.open();
    try {
      final bytes = await handle.read(magic.length);
      return _sameBytes(bytes, magic);
    } finally {
      await handle.close();
    }
  }

  /// 只用于 UI 判断是否弹密码框。
  static Future<bool> isEncrypted(File file) async {
    final handle = await file.open();
    try {
      final head = await handle.read(11);
      if (head.length < 11 || !_sameBytes(head.sublist(0, 8), magic)) {
        return false;
      }
      final data = ByteData.sublistView(Uint8List.fromList(head));
      return data.getUint16(8, Endian.little) == formatVersionV2 &&
          data.getUint8(10) == protectionAesGcm;
    } finally {
      await handle.close();
    }
  }

  static Future<File> unwrapToZip({
    required File sourceFile,
    required File zipFile,
    String? password,
    ProgressCallback? onProgress,
    BackupCancelToken? cancelToken,
  }) async {
    final version = await _readVersion(sourceFile);
    if (version == formatVersion) {
      if (password != null && password.isNotEmpty) {
        throw const FormatException('joaiclient_password_unexpected');
      }
      return _unwrapV1(
        sourceFile: sourceFile,
        zipFile: zipFile,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    }
    if (version == formatVersionV2) {
      final protection = await _readProtection(sourceFile);
      if (protection == protectionAesGcm) {
        if (password == null || password.isEmpty) {
          throw const FormatException('joaiclient_password_required');
        }
        return _unwrapV2Encrypted(
          sourceFile: sourceFile,
          zipFile: zipFile,
          password: password,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
      }
      if (protection == protectionNone) {
        if (password != null && password.isNotEmpty) {
          throw const FormatException('joaiclient_password_unexpected');
        }
        return _unwrapV2Plain(
          sourceFile: sourceFile,
          zipFile: zipFile,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
      }
      throw const FormatException('joaiclient_header_version');
    }
    throw const FormatException('joaiclient_header_version');
  }

  static Future<File> _unwrapV1({
    required File sourceFile,
    required File zipFile,
    ProgressCallback? onProgress,
    BackupCancelToken? cancelToken,
  }) async {
    if (sourceFile.absolute.path == zipFile.absolute.path) {
      throw ArgumentError('sourceFile and zipFile must differ');
    }
    onProgress?.call(const ProgressUpdate(value: 0));
    final handle = await sourceFile.open();
    late final _JoaiclientHeader parsed;
    try {
      final header = await handle.read(headerLength);
      parsed = _decodeHeader(header);
      final actualLength = await sourceFile.length();
      if (actualLength != headerLength + parsed.payloadLength) {
        throw const FormatException('joaiclient_payload_length');
      }
      await zipFile.parent.create(recursive: true);
      final output = await zipFile.open(mode: FileMode.write);
      try {
        await handle.setPosition(headerLength);
        var remaining = parsed.payloadLength;
        while (remaining > 0) {
          cancelToken?.throwIfCancelled();
          final chunk = await handle.read(remaining.clamp(1, 1024 * 1024));
          if (chunk.isEmpty) {
            throw const FormatException('joaiclient_payload_truncated');
          }
          await output.writeFrom(chunk);
          remaining -= chunk.length;
          onProgress?.call(
            ProgressUpdate(
              value: parsed.payloadLength == 0
                  ? 0.9
                  : (parsed.payloadLength - remaining) /
                        parsed.payloadLength *
                        0.9,
            ),
          );
        }
        await output.flush();
      } finally {
        await output.close();
      }
    } catch (_) {
      await _deleteQuietly(zipFile);
      rethrow;
    } finally {
      await handle.close();
    }
    var hashed = 0;
    final digest = await sha256
        .bind(
          zipFile.openRead().map((chunk) {
            cancelToken?.throwIfCancelled();
            hashed += chunk.length;
            onProgress?.call(
              ProgressUpdate(
                value: parsed.payloadLength == 0
                    ? 1
                    : 0.9 + hashed / parsed.payloadLength * 0.1,
              ),
            );
            return chunk;
          }),
        )
        .first;
    if (!_sameBytes(digest.bytes, parsed.payloadSha256)) {
      await _deleteQuietly(zipFile);
      throw const FormatException('joaiclient_payload_hash');
    }
    onProgress?.call(const ProgressUpdate(value: 1));
    return zipFile;
  }

  static Future<File> _unwrapV2Encrypted({
    required File sourceFile,
    required File zipFile,
    required String password,
    ProgressCallback? onProgress,
    BackupCancelToken? cancelToken,
  }) async {
    if (sourceFile.absolute.path == zipFile.absolute.path) {
      throw ArgumentError('sourceFile and zipFile must differ');
    }
    onProgress?.call(const ProgressUpdate(value: 0));
    final handle = await sourceFile.open();
    late final _JoaiclientV2Header parsed;
    try {
      final headerBytes = await _readExactly(handle, v2HeaderLength);
      parsed = _decodeV2Header(headerBytes);
      final expectedLength =
          v2HeaderLength +
          parsed.plaintextLength +
          _chunkCount(parsed.plaintextLength) * 16;
      if (await sourceFile.length() != expectedLength) {
        throw const FormatException('joaiclient_payload_length');
      }
      final key = _deriveKey(
        password,
        parsed.salt,
        parsed.kdfIterations,
      );
      await zipFile.parent.create(recursive: true);
      final output = await zipFile.open(mode: FileMode.write);
      var outputClosed = false;
      try {
        var processed = 0;
        for (var index = 0; index < _chunkCount(parsed.plaintextLength); index++) {
          cancelToken?.throwIfCancelled();
          final count = min(
            parsed.chunkSize,
            parsed.plaintextLength - processed,
          );
          final ciphertext = await _readExactly(handle, count + 16);
          final cipher = _cipher(
            encrypt: false,
            key: key,
            noncePrefix: parsed.noncePrefix,
            index: index,
            header: headerBytes,
          );
          await output.writeFrom(cipher.process(ciphertext));
          processed += count;
          onProgress?.call(
            ProgressUpdate(
              value: parsed.plaintextLength == 0
                  ? 0.9
                  : processed / parsed.plaintextLength * 0.9,
            ),
          );
        }
        if (await handle.readByte() != -1) {
          throw const FormatException('joaiclient_payload_size');
        }
        await output.flush();
      } catch (error) {
        await output.close();
        outputClosed = true;
        await _deleteQuietly(zipFile);
        if (error is InvalidCipherTextException) {
          throw const FormatException('joaiclient_decryption_failed');
        }
        rethrow;
      } finally {
        key.fillRange(0, key.length, 0);
        if (!outputClosed) await output.close();
      }
    } on FormatException {
      await _deleteQuietly(zipFile);
      rethrow;
    } finally {
      await handle.close();
    }
    late final Uint8List digest;
    try {
      digest = await _hashFile(
        zipFile,
        onProgress: onProgress,
        cancelToken: cancelToken,
        start: 0.9,
        span: 0.1,
      );
    } catch (_) {
      await _deleteQuietly(zipFile);
      rethrow;
    }
    if (!_sameBytes(digest, parsed.plaintextSha256)) {
      await _deleteQuietly(zipFile);
      throw const FormatException('joaiclient_payload_hash');
    }
    onProgress?.call(const ProgressUpdate(value: 1));
    return zipFile;
  }

  static Future<int> _readProtection(File file) async {
    final handle = await file.open();
    try {
      final head = await handle.read(11);
      if (head.length != 11 || !_sameBytes(head.sublist(0, 8), magic)) {
        throw const FormatException('joaiclient_header');
      }
      return head[10];
    } finally {
      await handle.close();
    }
  }

  static Future<File> _unwrapV2Plain({
    required File sourceFile,
    required File zipFile,
    ProgressCallback? onProgress,
    BackupCancelToken? cancelToken,
  }) async {
    if (sourceFile.absolute.path == zipFile.absolute.path) {
      throw ArgumentError('sourceFile and zipFile must differ');
    }
    onProgress?.call(const ProgressUpdate(value: 0));
    final handle = await sourceFile.open();
    late final _JoaiclientV2Header parsed;
    try {
      final headerBytes = await _readExactly(handle, v2HeaderLength);
      parsed = _decodeV2Header(headerBytes);
      if (parsed.protection != protectionNone) {
        throw const FormatException('joaiclient_header_version');
      }
      if (await sourceFile.length() !=
          v2HeaderLength + parsed.plaintextLength) {
        throw const FormatException('joaiclient_payload_length');
      }
      await zipFile.parent.create(recursive: true);
      final output = await zipFile.open(mode: FileMode.write);
      try {
        var remaining = parsed.plaintextLength;
        while (remaining > 0) {
          cancelToken?.throwIfCancelled();
          final chunk = await handle.read(remaining.clamp(1, v2ChunkSize));
          if (chunk.isEmpty) {
            throw const FormatException('joaiclient_payload_truncated');
          }
          await output.writeFrom(chunk);
          remaining -= chunk.length;
          onProgress?.call(
            ProgressUpdate(
              value: parsed.plaintextLength == 0
                  ? 0.9
                  : (parsed.plaintextLength - remaining) /
                        parsed.plaintextLength *
                        0.9,
            ),
          );
        }
        await output.flush();
      } finally {
        await output.close();
      }
    } catch (_) {
      await _deleteQuietly(zipFile);
      rethrow;
    } finally {
      await handle.close();
    }
    late final Uint8List digest;
    try {
      digest = await _hashFile(
        zipFile,
        onProgress: onProgress,
        cancelToken: cancelToken,
        start: 0.9,
        span: 0.1,
      );
    } catch (_) {
      await _deleteQuietly(zipFile);
      rethrow;
    }
    if (!_sameBytes(digest, parsed.plaintextSha256)) {
      await _deleteQuietly(zipFile);
      throw const FormatException('joaiclient_payload_hash');
    }
    onProgress?.call(const ProgressUpdate(value: 1));
    return zipFile;
  }

  static Future<int> _readVersion(File file) async {
    final handle = await file.open();
    try {
      await handle.setPosition(8);
      final bytes = await handle.read(2);
      if (bytes.length != 2) {
        throw const FormatException('joaiclient_header');
      }
      return bytes[0] | bytes[1] << 8;
    } finally {
      await handle.close();
    }
  }

  static int _chunkCount(int plaintextLength) =>
      max(1, (plaintextLength + v2ChunkSize - 1) ~/ v2ChunkSize);

  static Uint8List _deriveKey(
    String password,
    Uint8List salt,
    int iterations,
  ) {
    final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, 32));
    return kdf.process(Uint8List.fromList(utf8.encode(password)));
  }

  static GCMBlockCipher _cipher({
    required bool encrypt,
    required Uint8List key,
    required Uint8List noncePrefix,
    required int index,
    required List<int> header,
  }) {
    final nonce = Uint8List(12)
      ..setRange(0, 8, noncePrefix)
      ..setRange(12 - 4, 12, _uint32Big(index));
    final aad = Uint8List(header.length + 4)
      ..setRange(0, header.length, header)
      ..setRange(header.length, header.length + 4, _uint32Big(index));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        encrypt,
        AEADParameters(KeyParameter(key), 128, nonce, aad),
      );
    return cipher;
  }

  static Uint8List _uint32Big(int value) {
    final bytes = Uint8List(4);
    ByteData.sublistView(bytes).setUint32(0, value, Endian.big);
    return bytes;
  }

  static Future<Uint8List> _hashFile(
    File file, {
    ProgressCallback? onProgress,
    BackupCancelToken? cancelToken,
    required double start,
    required double span,
  }) async {
    final length = await file.length();
    var hashed = 0;
    final digest = await sha256
        .bind(
          file.openRead().map((chunk) {
            cancelToken?.throwIfCancelled();
            hashed += chunk.length;
            onProgress?.call(
              ProgressUpdate(
                value: length == 0
                    ? start + span
                    : start + (hashed / length) * span,
              ),
            );
            cancelToken?.throwIfCancelled();
            return chunk;
          }),
        )
        .first;
    return Uint8List.fromList(digest.bytes);
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
        throw const FormatException('joaiclient_payload_truncated');
      }
      offset += count;
    }
    return bytes;
  }

  static List<int> _encodeHeader(int payloadLength, List<int> digest) {
    if (digest.length != 32) {
      throw ArgumentError.value(digest.length, 'digest.length');
    }
    final bytes = Uint8List(headerLength);
    bytes.setRange(0, magic.length, magic);
    final data = ByteData.sublistView(bytes);
    data.setUint16(8, formatVersion, Endian.little);
    data.setUint8(10, protectionNone);
    data.setUint8(11, payloadZip);
    data.setUint32(12, headerLength, Endian.little);
    data.setUint64(16, payloadLength, Endian.little);
    bytes.setRange(24, headerLength, digest);
    return bytes;
  }

  static List<int> _encodeV2Header({
    required int protection,
    required int plaintextLength,
    required List<int> plaintextSha256,
    Uint8List? salt,
    Uint8List? noncePrefix,
    int kdfIterations = v2KdfIterations,
    int chunkSize = v2ChunkSize,
  }) {
    if (plaintextSha256.length != 32 ||
        (protection == protectionAesGcm &&
            (salt == null ||
                salt.length != 16 ||
                noncePrefix == null ||
                noncePrefix.length != 8))) {
      throw ArgumentError('joaiclient_v2_header');
    }
    final bytes = Uint8List(v2HeaderLength);
    bytes.setRange(0, magic.length, magic);
    final data = ByteData.sublistView(bytes);
    data.setUint16(8, formatVersionV2, Endian.little);
    data.setUint8(10, protection);
    data.setUint8(11, payloadZip);
    data.setUint32(12, v2HeaderLength, Endian.little);
    data.setUint64(16, plaintextLength, Endian.little);
    if (protection == protectionAesGcm) {
      data.setUint32(24, kdfIterations, Endian.little);
      data.setUint32(28, chunkSize, Endian.little);
      bytes.setRange(32, 48, salt!);
      bytes.setRange(48, 56, noncePrefix!);
    }
    bytes.setRange(56, 88, plaintextSha256);
    return bytes;
  }

  static _JoaiclientHeader _decodeHeader(List<int> bytes) {
    if (bytes.length != headerLength) {
      throw const FormatException('joaiclient_header');
    }
    for (var index = 0; index < magic.length; index++) {
      if (bytes[index] != magic[index]) {
        throw const FormatException('joaiclient_magic');
      }
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    if (data.getUint16(8, Endian.little) != formatVersion ||
        data.getUint8(10) != protectionNone ||
        data.getUint8(11) != payloadZip ||
        data.getUint32(12, Endian.little) != headerLength) {
      throw const FormatException('joaiclient_header_version');
    }
    final payloadLength = data.getUint64(16, Endian.little);
    if (payloadLength > maxPlaintextBytes) {
      throw const FormatException('joaiclient_payload_size');
    }
    return _JoaiclientHeader(
      payloadLength: payloadLength,
      payloadSha256: bytes.sublist(24),
    );
  }

  static _JoaiclientV2Header _decodeV2Header(List<int> bytes) {
    if (bytes.length != v2HeaderLength) {
      throw const FormatException('joaiclient_header');
    }
    for (var index = 0; index < magic.length; index++) {
      if (bytes[index] != magic[index]) {
        throw const FormatException('joaiclient_magic');
      }
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final protection = data.getUint8(10);
    if (data.getUint16(8, Endian.little) != formatVersionV2 ||
        (protection != protectionNone &&
            protection != protectionAesGcm) ||
        data.getUint8(11) != payloadZip ||
        data.getUint32(12, Endian.little) != v2HeaderLength) {
      throw const FormatException('joaiclient_header_version');
    }
    final plaintextLength = data.getUint64(16, Endian.little);
    final kdfIterations = data.getUint32(24, Endian.little);
    final chunkSize = data.getUint32(28, Endian.little);
    if (plaintextLength > maxPlaintextBytes ||
        (protection == protectionAesGcm &&
            (kdfIterations < 100000 ||
                kdfIterations > 10000000 ||
                chunkSize < 64 * 1024 ||
                chunkSize > 8 * 1024 * 1024))) {
      throw const FormatException('joaiclient_header_version');
    }
    return _JoaiclientV2Header(
      protection: protection,
      plaintextLength: plaintextLength,
      kdfIterations: kdfIterations,
      chunkSize: chunkSize,
      salt: Uint8List.fromList(bytes.sublist(32, 48)),
      noncePrefix: Uint8List.fromList(bytes.sublist(48, 56)),
      plaintextSha256: Uint8List.fromList(bytes.sublist(56, 88)),
    );
  }

  static bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static Future<void> _deleteQuietly(File file) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (await file.exists()) await file.delete();
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  }
}

final class _JoaiclientHeader {
  const _JoaiclientHeader({
    required this.payloadLength,
    required this.payloadSha256,
  });

  final int payloadLength;
  final List<int> payloadSha256;
}

final class _JoaiclientV2Header {
  const _JoaiclientV2Header({
    required this.protection,
    required this.plaintextLength,
    required this.kdfIterations,
    required this.chunkSize,
    required this.salt,
    required this.noncePrefix,
    required this.plaintextSha256,
  });

  final int protection;
  final int plaintextLength;
  final int kdfIterations;
  final int chunkSize;
  final Uint8List salt;
  final Uint8List noncePrefix;
  final Uint8List plaintextSha256;
}
