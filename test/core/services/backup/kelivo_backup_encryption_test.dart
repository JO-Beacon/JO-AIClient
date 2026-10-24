import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

import 'package:Kelivo/core/services/backup/kelivo_backup_encryption.dart';

Future<File> _encrypt(File plain, File output, String password) async {
  final bytes = await plain.readAsBytes();
  final random = Random.secure();
  final salt = Uint8List.fromList(
    List<int>.generate(16, (_) => random.nextInt(256)),
  );
  final noncePrefix = Uint8List.fromList(
    List<int>.generate(8, (_) => random.nextInt(256)),
  );
  final header = Uint8List(KelivoBackupEncryption.headerLength);
  header.setRange(0, 8, KelivoBackupEncryption.magic);
  header[8] = 2;
  header.setRange(9, 25, salt);
  header.setRange(25, 33, noncePrefix);
  ByteData.sublistView(header).setUint64(33, bytes.length, Endian.big);
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, 600000, 32));
  final key = kdf.process(Uint8List.fromList(utf8.encode(password)));
  final chunks = max(
    1,
    (bytes.length + KelivoBackupEncryption.chunkSize - 1) ~/
        KelivoBackupEncryption.chunkSize,
  );
  final outputHandle = await output.open(mode: FileMode.write);
  try {
    await outputHandle.writeFrom(header);
    for (var index = 0; index < chunks; index++) {
      final start = index * KelivoBackupEncryption.chunkSize;
      final end = min(start + KelivoBackupEncryption.chunkSize, bytes.length);
      final chunk = bytes.sublist(start, end);
      final nonce = Uint8List(12)
        ..setRange(0, 8, noncePrefix)
        ..setRange(8, 12, _u32(index));
      final aad = Uint8List(header.length + 4)
        ..setRange(0, header.length, header)
        ..setRange(header.length, header.length + 4, _u32(index));
      final cipher = GCMBlockCipher(AESEngine())
        ..init(true, AEADParameters(KeyParameter(key), 128, nonce, aad));
      await outputHandle.writeFrom(cipher.process(Uint8List.fromList(chunk)));
    }
  } finally {
    await outputHandle.close();
  }
  return output;
}

Uint8List _u32(int value) {
  final bytes = Uint8List(4);
  ByteData.sublistView(bytes).setUint32(0, value, Endian.big);
  return bytes;
}

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('kelivo_encryption_test_');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('decrypts a KELIVENC v2 payload', () async {
    final plain = File('${root.path}/plain.bin')
      ..writeAsBytesSync(List<int>.generate(2 * 1024 * 1024 + 17, (i) => i % 251));
    final encrypted = File('${root.path}/backup.kbackup');
    await _encrypt(plain, encrypted, 'secret');
    expect(await KelivoBackupEncryption.isEncrypted(encrypted), isTrue);
    final restored = File('${root.path}/restored.bin');
    await KelivoBackupEncryption.decryptFile(
      source: encrypted,
      destination: restored,
      password: 'secret',
    );
    expect(await restored.readAsBytes(), await plain.readAsBytes());
  });

  test('wrong password fails and removes partial output', () async {
    final plain = File('${root.path}/plain.bin')
      ..writeAsBytesSync(const [1, 2, 3, 4]);
    final encrypted = File('${root.path}/backup.kbackup');
    await _encrypt(plain, encrypted, 'secret');
    final restored = File('${root.path}/restored.bin');
    await expectLater(
      KelivoBackupEncryption.decryptFile(
        source: encrypted,
        destination: restored,
        password: 'wrong',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await restored.exists(), isFalse);
  });

  test('truncated payload is rejected', () async {
    final plain = File('${root.path}/plain.bin')
      ..writeAsBytesSync(const [1, 2, 3, 4]);
    final encrypted = File('${root.path}/backup.kbackup');
    await _encrypt(plain, encrypted, 'secret');
    final bytes = await encrypted.readAsBytes();
    await encrypted.writeAsBytes(bytes.sublist(0, bytes.length - 2));
    await expectLater(
      KelivoBackupEncryption.decryptFile(
        source: encrypted,
        destination: File('${root.path}/restored.bin'),
        password: 'secret',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
