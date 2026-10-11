import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tpms_libre/treel/model.dart';
import 'package:tpms_libre/treel/scanner.dart';
import 'package:tpms_libre/ui/home_page.dart';
import 'package:tpms_libre/ui/theme.dart';
import 'package:tpms_libre/ui/tyre.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner-supplied vehicle pictures: we cannot ship a drawing of every
/// vehicle ever made, so a vehicle can wear a photograph instead.

/// A real PNG of the requested size, so the store is exercised against
/// actual image bytes rather than a stub that never decodes.
Future<Uint8List> png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366AA),
  );
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

Directory tempDir() {
  final d = Directory.systemTemp.createTempSync('tpmslibre-photos');
  addTearDown(() {
    if (d.existsSync()) d.deleteSync(recursive: true);
  });
  return d;
}

Future<File> sourceImage(Directory dir, int w, int h) async {
  final f = File('${dir.path}/source-${w}x$h.png');
  await f.writeAsBytes(await png(w, h));
  return f;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('PhotoStore', () {
    test('a closed store draws nothing and does not throw', () {
      final store = PhotoStore();
      expect(store.ready, isFalse);
      expect(store.fileFor('anything.png'), isNull);
      expect(store.exists('anything.png'), isFalse);
    });

    test('saves a picture and reports its shape', () async {
      final dir = tempDir();
      final store = PhotoStore(directory: dir);
      final saved = await store.save('v1', await sourceImage(dir, 800, 400));

      expect(saved, isNotNull);
      expect(saved!.aspect, closeTo(2.0, 0.01));
      expect(store.exists(saved.name), isTrue);
      expect(saved.name, startsWith('v1-'));
    });

    test('a huge picture is scaled down before it is stored', () async {
      final dir = tempDir();
      final store = PhotoStore(directory: dir);
      final saved = await store.save('v1', await sourceImage(dir, 4000, 3000));

      expect(saved, isNotNull);
      // The aspect has to survive the scaling, or the layout is wrong.
      expect(saved!.aspect, closeTo(4000 / 3000, 0.01));

      final codec = await ui.instantiateImageCodec(
        await store.fileFor(saved.name)!.readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      final longest = frame.image.width > frame.image.height
          ? frame.image.width
          : frame.image.height;
      expect(longest, PhotoStore.maxEdge);
      frame.image.dispose();
      codec.dispose();
    });

    test('a file that is not an image is refused, not stored', () async {
      final dir = tempDir();
      final store = PhotoStore(directory: dir);
      final junk = File('${dir.path}/notes.txt')
        ..writeAsStringSync('this is not a picture');

      expect(await store.save('v1', junk), isNull);
      expect(dir.listSync().whereType<File>().length, 1, reason: 'just junk');
    });

    test('each save gets its own name', () async {
      // Reusing a name would leave Flutter's image cache serving the old
      // picture from that path, which looks exactly like a failed save.
      final dir = tempDir();
      final store = PhotoStore(directory: dir);
      final first = await store.save('v1', await sourceImage(dir, 400, 300));
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final second = await store.save('v1', await sourceImage(dir, 500, 300));
      expect(first!.name, isNot(second!.name));
    });
  });

  group('a vehicle wearing a photograph', () {
    test('the picture replaces the drawing and survives a save', () async {
      final dir = tempDir();
      final model = TreelModel(photos: PhotoStore(directory: dir));
      try {
        await model.load();
        expect(
          await model.setPhoto(
            model.vehicle.id,
            await sourceImage(dir, 900, 600),
          ),
          isTrue,
        );
        expect(model.vehicle.hasPhoto, isTrue);
        expect(model.vehicle.photoAspect, closeTo(1.5, 0.01));

        final back = Vehicle.fromJson(model.vehicle.toJson());
        expect(back.photo, model.vehicle.photo);
        expect(back.photoAspect, closeTo(1.5, 0.01));
      } finally {
        model.dispose();
      }
    });

    test('replacing a picture removes the one it replaced', () async {
      final dir = tempDir();
      final store = PhotoStore(directory: dir);
      final model = TreelModel(photos: store);
      try {
        await model.load();
        await model.setPhoto(
          model.vehicle.id,
          await sourceImage(dir, 900, 600),
        );
        final first = model.vehicle.photo;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        await model.setPhoto(
          model.vehicle.id,
          await sourceImage(dir, 600, 900),
        );

        expect(model.vehicle.photo, isNot(first));
        expect(store.exists(first), isFalse, reason: 'the old file is gone');
        expect(store.exists(model.vehicle.photo), isTrue);
      } finally {
        model.dispose();
      }
    });

    test('going back to the drawing deletes the file too', () async {
      final dir = tempDir();
      final store = PhotoStore(directory: dir);
      final model = TreelModel(photos: store);
      try {
        await model.load();
        await model.setPhoto(
          model.vehicle.id,
          await sourceImage(dir, 900, 600),
        );
        final name = model.vehicle.photo;

        await model.clearPhoto(model.vehicle.id);
        expect(model.vehicle.hasPhoto, isFalse);
        expect(store.exists(name), isFalse);
      } finally {
        model.dispose();
      }
    });

    test('a picture that has gone missing is forgotten', () async {
      // App data cleared, or a restore onto a new phone: the record points
      // at a file that is not there any more.
      final dir = tempDir();
      final store = PhotoStore(directory: dir);
      final model = TreelModel(photos: store);
      try {
        await model.load();
        await model.setPhoto(
          model.vehicle.id,
          await sourceImage(dir, 900, 600),
        );
        store.fileFor(model.vehicle.photo)!.deleteSync();

        await model.openPhotos();
        expect(model.vehicle.hasPhoto, isFalse);
      } finally {
        model.dispose();
      }
    });
  });

  group('on screen', () {
    // Saving a picture decodes it, which needs a real clock. A widget test
    // runs on a fake one, so every image call here goes through runAsync --
    // the same reason the golden tests wrap their asset loading.
    Future<void> pump(WidgetTester tester, TreelModel model) async {
      tester.view.physicalSize = const Size(411, 915) * 2.0;
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: HomePage(model: model, scanner: TreelScanner(model)),
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
    }

    testWidgets('a photograph replaces the prompt', (tester) async {
      final dir = tempDir();
      final model = TreelModel(photos: PhotoStore(directory: dir));
      try {
        await model.load();
        await model.setAnimations(false);
        await model.setLayout(model.vehicle.id, WheelLayout.motorcycle);

        await pump(tester, model);
        expect(find.text('Add a photo of your vehicle'), findsOneWidget);

        await tester.runAsync(
          () async => model.setPhoto(
            model.vehicle.id,
            await sourceImage(dir, 900, 600),
          ),
        );
        await pump(tester, model);

        final images = tester.widgetList<Image>(find.byType(Image)).toList();
        expect(images, hasLength(1));
        expect(images.single.image, isA<FileImage>());
        expect(find.text('Add a photo of your vehicle'), findsNothing);
        expect(find.byType(TyreCard), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      } finally {
        model.dispose();
      }
    });

    testWidgets('removing a photo is offered as removing, not going back', (
      tester,
    ) async {
      // There is no drawing to go back to, so the menu must not promise one.
      final dir = tempDir();
      final model = TreelModel(photos: PhotoStore(directory: dir));
      try {
        await model.load();
        await model.setAnimations(false);
        await tester.runAsync(
          () async => model.setPhoto(
            model.vehicle.id,
            await sourceImage(dir, 900, 600),
          ),
        );
        await pump(tester, model);

        await tester.tap(find.byType(Image));
        await tester.pumpAndSettle();
        expect(find.text('Remove photo'), findsOneWidget);
        expect(find.text('Back to the drawing'), findsNothing);

        await tester.runAsync(() async {
          await tester.tap(find.text('Remove photo'));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        expect(model.vehicle.hasPhoto, isFalse);
        expect(find.text('Add a photo of your vehicle'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        model.dispose();
      }
    });
  });
}
