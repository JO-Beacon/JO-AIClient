import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: prepare_appimage_icon.dart <input.png> <output.png>',
    );
    exitCode = 64;
    return;
  }

  final source = img.decodePng(File(args[0]).readAsBytesSync());
  if (source == null) {
    throw FormatException('Cannot decode PNG: ${args[0]}');
  }

  // linuxdeploy 只接受不超过 512 像素的方形图标。
  final icon = img.copyResize(
    source,
    width: 512,
    height: 512,
    maintainAspect: true,
    interpolation: img.Interpolation.average,
  );
  File(args[1]).writeAsBytesSync(img.encodePng(icon));
}
