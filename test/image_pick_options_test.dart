import 'package:flutter_test/flutter_test.dart';
import 'package:pick_photo/pick_photo.dart';

void main() {
  group('ImagePickOptions validation', () {
    test('default options are valid with preserveOriginal = true', () {
      final options = ImagePickOptions();
      expect(options.preserveOriginal, isTrue);
      expect(options.maxWidth, isNull);
      expect(options.maxHeight, isNull);
      expect(options.quality, isNull);
      expect(options.maxSizeBytes, isNull);
    });

    test('valid custom options do not throw', () {
      expect(
        () => ImagePickOptions(
          maxWidth: 1920,
          maxHeight: 1080,
          quality: 85,
          maxSizeBytes: 5 * 1024 * 1024,
          preserveOriginal: false,
        ),
        returnsNormally,
      );
    });

    test('throws InvalidOptionsException when maxWidth <= 0', () {
      expect(
        () => ImagePickOptions(maxWidth: 0),
        throwsA(
          isA<InvalidOptionsException>().having(
            (e) => e.message,
            'message',
            contains('maxWidth'),
          ),
        ),
      );
      expect(
        () => ImagePickOptions(maxWidth: -10),
        throwsA(isA<InvalidOptionsException>()),
      );
    });

    test('throws InvalidOptionsException when maxHeight <= 0', () {
      expect(
        () => ImagePickOptions(maxHeight: 0),
        throwsA(
          isA<InvalidOptionsException>().having(
            (e) => e.message,
            'message',
            contains('maxHeight'),
          ),
        ),
      );
      expect(
        () => ImagePickOptions(maxHeight: -5),
        throwsA(isA<InvalidOptionsException>()),
      );
    });

    test('throws InvalidOptionsException when maxSizeBytes <= 0', () {
      expect(
        () => ImagePickOptions(maxSizeBytes: 0),
        throwsA(
          isA<InvalidOptionsException>().having(
            (e) => e.message,
            'message',
            contains('maxSizeBytes'),
          ),
        ),
      );
      expect(
        () => ImagePickOptions(maxSizeBytes: -1),
        throwsA(isA<InvalidOptionsException>()),
      );
    });

    test('throws InvalidOptionsException when quality is outside 1..100', () {
      expect(
        () => ImagePickOptions(quality: 0),
        throwsA(
          isA<InvalidOptionsException>().having(
            (e) => e.message,
            'message',
            contains('quality'),
          ),
        ),
      );
      expect(
        () => ImagePickOptions(quality: 101),
        throwsA(isA<InvalidOptionsException>()),
      );
      expect(
        () => ImagePickOptions(quality: -50),
        throwsA(isA<InvalidOptionsException>()),
      );
    });

    test('equality and hashCode work as expected', () {
      final opt1 = ImagePickOptions(maxWidth: 500, quality: 80);
      final opt2 = ImagePickOptions(maxWidth: 500, quality: 80);
      final opt3 = ImagePickOptions(maxWidth: 600, quality: 80);

      expect(opt1, equals(opt2));
      expect(opt1.hashCode, equals(opt2.hashCode));
      expect(opt1, isNot(equals(opt3)));
    });
  });
}
