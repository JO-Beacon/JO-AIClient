import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/backup/streaming_zip_entry.dart';

/// 大备份解包时的内存占用就靠这两个函数控制：
/// 边解压边写出，而不是先把整块内容攒在内存里；
/// 取消时要在写出过程中就能停下来（不是等整块解完）。
final class _CountingOutput extends OutputMemoryStream {
  _CountingOutput(this.onWrite);
  final void Function(List<int>) onWrite;
  @override
  void writeBytes(List<int> bytes, {int? length}) =>
      onWrite(length == null ? bytes : bytes.sublist(0, length));
  @override
  void flush() {}
}

void main() {
  for (final compress in [false, true]) {
    test('压缩=$compress 时字节一个不少', () {
      final data = Uint8List.fromList(List.generate(65537, (i) => i % 251));
      final bytes = ZipEncoder().encode(
        Archive()..addFile(
          ArchiveFile('data', data.length, data)
            ..compression = compress
                ? CompressionType.deflate
                : CompressionType.none,
        ),
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final output = OutputMemoryStream();
      writeZipEntryStreaming(archive.single, output);
      expect(sha256.convert(output.getBytes()), sha256.convert(data));
      archive.clearSync();
    });
  }

  test('在压缩输入读完之前就已经写出，并且能中途停下', () {
    final data = Uint8List(16 * 1024 * 1024);
    final bytes = ZipEncoder().encode(
      Archive()..addFile(ArchiveFile('database/kelivo.db', data.length, data)),
    );
    final decoder = ZipDecoder();
    final archive = decoder.decodeBytes(bytes);
    final input = decoder.directory.fileHeaders.single.file!.getStream(
      decompress: false,
    );
    var written = 0;
    var sawOutputBeforeEnd = false;
    final output = _CountingOutput((chunk) {
      sawOutputBeforeEnd |= !input.isEOS;
      written += chunk.length;
    });
    expect(
      () => writeZipEntryStreaming(
        archive.single,
        output,
        checkCancelled: () {
          if (written >= 256 * 1024) throw StateError('cancelled');
        },
      ),
      throwsStateError,
    );
    expect(sawOutputBeforeEnd, isTrue);
    expect(written, lessThan(data.length));
    expect(input.position, 0, reason: '失败后要把 ZIP 游标放回去');
    final retry = OutputMemoryStream();
    writeZipEntryStreaming(archive.single, retry);
    expect(sha256.convert(retry.getBytes()), sha256.convert(data));
    archive.clearSync();
  });
}
