import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pick_photo/pick_photo.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pick_photo_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PickedImage model and methods', () {
    test('instantiates with all properties', () {
      const image = PickedImage(
        path: '/tmp/test.jpg',
        name: 'test.jpg',
        mimeType: 'image/jpeg',
        extension: 'jpg',
        sizeBytes: 12345,
        width: 1920,
        height: 1080,
        source: ImageSource.gallery,
      );

      expect(image.path, '/tmp/test.jpg');
      expect(image.name, 'test.jpg');
      expect(image.mimeType, 'image/jpeg');
      expect(image.extension, 'jpg');
      expect(image.sizeBytes, 12345);
      expect(image.width, 1920);
      expect(image.height, 1080);
      expect(image.source, ImageSource.gallery);
      expect(image.file.path, '/tmp/test.jpg');
    });

    test('readAsBytes reads raw bytes from file', () async {
      final sampleFile = File('${tempDir.path}/sample.png');
      await sampleFile.writeAsBytes([1, 2, 3, 4, 5]);

      final image = PickedImage(
        path: sampleFile.path,
        name: 'sample.png',
        mimeType: 'image/png',
        extension: 'png',
        sizeBytes: 5,
        source: ImageSource.camera,
      );

      final bytes = await image.readAsBytes();
      expect(bytes, equals([1, 2, 3, 4, 5]));
    });

    test('saveTo copies file to persistent destination creating parent dirs', () async {
      final sampleFile = File('${tempDir.path}/source.jpg');
      await sampleFile.writeAsString('fake image data');

      final image = PickedImage(
        path: sampleFile.path,
        name: 'source.jpg',
        mimeType: 'image/jpeg',
        extension: 'jpg',
        sizeBytes: 15,
        source: ImageSource.gallery,
      );

      final destPath = '${tempDir.path}/nested/folder/destination.jpg';
      final savedFile = await image.saveTo(destPath);

      expect(savedFile.existsSync(), isTrue);
      expect(savedFile.path, destPath);
      expect(await savedFile.readAsString(), 'fake image data');
    });

    test('equality and hashCode work as expected', () {
      const img1 = PickedImage(
        path: '/path/1.jpg',
        name: '1.jpg',
        mimeType: 'image/jpeg',
        extension: 'jpg',
        sizeBytes: 100,
        source: ImageSource.gallery,
      );
      const img2 = PickedImage(
        path: '/path/1.jpg',
        name: '1.jpg',
        mimeType: 'image/jpeg',
        extension: 'jpg',
        sizeBytes: 100,
        source: ImageSource.gallery,
      );
      const img3 = PickedImage(
        path: '/path/2.jpg',
        name: '2.jpg',
        mimeType: 'image/jpeg',
        extension: 'jpg',
        sizeBytes: 100,
        source: ImageSource.gallery,
      );

      expect(img1, equals(img2));
      expect(img1.hashCode, equals(img2.hashCode));
      expect(img1, isNot(equals(img3)));
      expect(img1.toString(), contains('PickedImage'));
    });
  });
}
