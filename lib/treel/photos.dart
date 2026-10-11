import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Where owner-supplied vehicle pictures live, and how they get there.
///
/// Kept apart from the model so the model stays testable without a real
/// filesystem, and so the one piece that has to touch `dart:io` is small
/// enough to read in one go.
class PhotoStore {
  PhotoStore({this.directory});

  /// Null until [open] has run, or in a test that never opens it.
  Directory? directory;

  bool get ready => directory != null;

  /// Finds the directory, or leaves the store closed.
  ///
  /// Closed is a working state, not a failure: [fileFor] returns null, no
  /// picture is drawn, and the drawings are used instead. That is what a
  /// widget test gets, where there is no platform channel to answer, and it
  /// is better than every test in the suite hanging on a reply that never
  /// comes.
  Future<void> open() async {
    if (directory != null) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/vehicles');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      directory = dir;
    } on Object {
      directory = null;
    }
  }

  File? fileFor(String? name) {
    final dir = directory;
    if (dir == null || name == null) return null;
    return File('${dir.path}/$name');
  }

  bool exists(String? name) => fileFor(name)?.existsSync() ?? false;

  /// The longest edge a stored picture is allowed to be.
  ///
  /// A phone camera hands over something like 4000px wide; the drawing is
  /// rendered around 360 logical pixels, so anything past this is storage
  /// and decode time spent on detail that is never visible.
  static const maxEdge = 1600;

  /// Copies [source] into the store, downscaled, as PNG.
  ///
  /// Returns the stored filename and the aspect actually saved, or null if
  /// the file could not be read as an image — which is worth handling rather
  /// than asserting, since the picker can hand back something unreadable.
  Future<({String name, double aspect})?> save(
    String vehicleId,
    File source,
  ) async {
    final dir = directory;
    if (dir == null) return null;

    final bytes = await source.readAsBytes();
    final decoded = await _decodeScaled(bytes);
    if (decoded == null) return null;
    final (data, width, height) = decoded;

    // A fresh name every time. Reusing one would leave Flutter's image cache
    // serving the previous picture from the same path until the app
    // restarts, which looks exactly like the save having failed.
    final name = '$vehicleId-${DateTime.now().millisecondsSinceEpoch}.png';
    await File('${dir.path}/$name').writeAsBytes(data, flush: true);
    return (name: name, aspect: width / height);
  }

  Future<(Uint8List, int, int)?> _decodeScaled(Uint8List bytes) async {
    ui.Image? image;
    try {
      final probe = await ui.instantiateImageCodec(bytes);
      final frame = await probe.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      probe.dispose();
      if (w == 0 || h == 0) return null;

      final longest = w > h ? w : h;
      final codec = longest <= maxEdge
          ? await ui.instantiateImageCodec(bytes)
          : await ui.instantiateImageCodec(
              bytes,
              targetWidth: w >= h ? maxEdge : (w * maxEdge / h).round(),
              targetHeight: h > w ? maxEdge : (h * maxEdge / w).round(),
            );
      final scaled = await codec.getNextFrame();
      codec.dispose();
      image = scaled.image;

      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return null;
      return (png.buffer.asUint8List(), image.width, image.height);
    } on Object {
      // Anything unreadable — a HEIC the platform cannot decode, a truncated
      // download, a file that is not an image at all.
      return null;
    } finally {
      image?.dispose();
    }
  }

  Future<void> delete(String? name) async {
    final f = fileFor(name);
    if (f != null && f.existsSync()) {
      try {
        await f.delete();
      } on FileSystemException {
        // A picture we cannot remove is not worth failing a save over.
      }
    }
  }
}
