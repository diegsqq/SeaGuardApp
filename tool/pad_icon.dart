import 'dart:io';

import 'package:image/image.dart' as img;

/// Pads the input logo with transparent margin to avoid cropping in the launcher icon.
Future<void> main() async {
  final inputFile = File('assets/image.png');
  if (!await inputFile.exists()) {
    stderr.writeln('Input file assets/image.png not found.');
    exit(1);
  }

  final bytes = await inputFile.readAsBytes();
  final src = img.decodeImage(bytes);
  if (src == null) {
    stderr.writeln('Failed to decode assets/image.png');
    exit(1);
  }

  // Keep the logo centered with generous padding to avoid clipping in adaptive masks.
  // Final size 512x512 works well for launcher icons.
  const targetSize = 512;
  const marginRatio = 0.50; // ~50% padding per side

  final maxSide = src.width > src.height ? src.width : src.height;
  final scale = (targetSize * (1 - marginRatio * 2)) / maxSide;
  final resized = img.copyResize(
    src,
    width: (src.width * scale).round(),
    height: (src.height * scale).round(),
    interpolation: img.Interpolation.average,
  );

  final canvas = img.Image(
    width: targetSize,
    height: targetSize,
    numChannels: 4,
  );
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));

  final dx = ((targetSize - resized.width) / 2).round();
  final dy = ((targetSize - resized.height) / 2).round();
  img.compositeImage(
    canvas,
    resized,
    dstX: dx,
    dstY: dy,
  );

  final outputPath = 'assets/app_icon_foreground.png';
  final outputBytes = img.encodePng(canvas);
  await File(outputPath).writeAsBytes(outputBytes);
  stdout.writeln('Wrote padded icon to $outputPath (size: ${canvas.width}x${canvas.height}).');
}
