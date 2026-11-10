import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pick_photo/pick_photo.dart';
import 'package:pick_photo/src/platform/messages.g.dart';

class FakePickPhotoHostApi extends PickPhotoHostApi {
  FutureOr<PickedImageResult?> Function(ImagePickOptionsDto)? onPickImage;
  FutureOr<List<PickedImageResult>> Function(MultiImagePickOptionsDto)?
  onPickMultiple;
  FutureOr<PickedImageResult?> Function(CameraPickOptionsDto)? onCaptureImage;
  FutureOr<void> Function()? onClearCache;

  // Track called args
  ImagePickOptionsDto? lastSingleOptions;
  MultiImagePickOptionsDto? lastMultiOptions;
  CameraPickOptionsDto? lastCameraOptions;
  bool clearCacheCalled = false;

  @override
  Future<PickedImageResult?> pickImage(ImagePickOptionsDto options) async {
    lastSingleOptions = options;
    if (onPickImage != null) {
      return await onPickImage!(options);
    }
    return PickedImageResult(
      path: '/cache/pick_photo_1.jpg',
      name: 'pick_photo_1.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 1024,
      width: 800,
      height: 600,
    );
  }

  @override
  Future<List<PickedImageResult>> pickMultipleImages(
    MultiImagePickOptionsDto options,
  ) async {
    lastMultiOptions = options;
    if (onPickMultiple != null) {
      return await onPickMultiple!(options);
    }
    return [
      PickedImageResult(
        path: '/cache/multi_1.png',
        name: 'multi_1.png',
        mimeType: 'image/png',
        sizeBytes: 2048,
        width: 1024,
        height: 768,
      ),
      PickedImageResult(
        path: '/cache/multi_2.heic',
        name: 'multi_2.heic',
        mimeType: 'image/heic',
        sizeBytes: 4096,
        width: 4032,
        height: 3024,
      ),
    ];
  }

  @override
  Future<PickedImageResult?> captureImage(CameraPickOptionsDto options) async {
    lastCameraOptions = options;
    if (onCaptureImage != null) {
      return await onCaptureImage!(options);
    }
    return PickedImageResult(
      path: '/cache/camera_1.jpg',
      name: 'camera_1.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 3072,
      width: 1920,
      height: 1080,
    );
  }

  @override
  Future<void> clearCache() async {
    clearCacheCalled = true;
    if (onClearCache != null) {
      await onClearCache!();
    }
  }
}

void main() {
  late FakePickPhotoHostApi fakeApi;
  late PickPhoto pickPhoto;

  setUp(() {
    fakeApi = FakePickPhotoHostApi();
    pickPhoto = PickPhoto(hostApi: fakeApi);
    PickPhoto.instance = pickPhoto;
  });

  group('PickPhoto Gallery Selection', () {
    test('pick single photo successfully maps result', () async {
      final image = await pickPhoto.pickFromGallery(
        options: ImagePickOptions(
          maxWidth: 1200,
          quality: 90,
          preserveOriginal: false,
        ),
      );

      expect(image, isNotNull);
      expect(image!.path, '/cache/pick_photo_1.jpg');
      expect(image.name, 'pick_photo_1.jpg');
      expect(image.mimeType, 'image/jpeg');
      expect(image.extension, 'jpg');
      expect(image.sizeBytes, 1024);
      expect(image.width, 800);
      expect(image.height, 600);
      expect(image.source, ImageSource.gallery);

      expect(fakeApi.lastSingleOptions?.maxWidth, 1200);
      expect(fakeApi.lastSingleOptions?.quality, 90);
      expect(fakeApi.lastSingleOptions?.preserveOriginal, isFalse);
    });

    test(
      'pick single photo returns null on cancellation without error',
      () async {
        fakeApi.onPickImage = (_) => null;

        final image = await pickPhoto.pickFromGallery();
        expect(image, isNull);
      },
    );

    test('static PickPhoto.fromGallery delegates to instance', () async {
      final image = await PickPhoto.fromGallery();
      expect(image, isNotNull);
      expect(image!.name, 'pick_photo_1.jpg');
    });

    test('pick multiple images successfully maps list', () async {
      final images = await pickPhoto.pickMultiple(
        maxCount: 5,
        options: ImagePickOptions(preserveOriginal: true),
      );

      expect(images.length, 2);
      expect(images[0].name, 'multi_1.png');
      expect(images[0].extension, 'png');
      expect(images[0].mimeType, 'image/png');
      expect(images[0].source, ImageSource.gallery);

      expect(images[1].name, 'multi_2.heic');
      expect(images[1].extension, 'heic');
      expect(images[1].mimeType, 'image/heic');
      expect(images[1].source, ImageSource.gallery);

      expect(fakeApi.lastMultiOptions?.maxCount, 5);
      expect(fakeApi.lastMultiOptions?.preserveOriginal, isTrue);
    });

    test(
      'pick multiple returns empty list on cancellation without error',
      () async {
        fakeApi.onPickMultiple = (_) => [];

        final images = await pickPhoto.pickMultiple();
        expect(images, isEmpty);
      },
    );

    test(
      'pick multiple throws InvalidOptionsException if maxCount <= 0',
      () async {
        expect(
          () => pickPhoto.pickMultiple(maxCount: 0),
          throwsA(
            isA<InvalidOptionsException>().having(
              (e) => e.message,
              'message',
              contains('maxCount'),
            ),
          ),
        );

        expect(
          () => pickPhoto.pickMultiple(maxCount: -1),
          throwsA(isA<InvalidOptionsException>()),
        );
      },
    );

    test('static PickPhoto.multiple delegates to instance', () async {
      final images = await PickPhoto.multiple(maxCount: 3);
      expect(images.length, 2);
      expect(fakeApi.lastMultiOptions?.maxCount, 3);
    });
  });

  group('PickPhoto Camera Capture', () {
    test('captures photo successfully with source camera', () async {
      final image = await pickPhoto.pickFromCamera();

      expect(image, isNotNull);
      expect(image!.path, '/cache/camera_1.jpg');
      expect(image.source, ImageSource.camera);
      expect(image.extension, 'jpg');
    });

    test('camera cancellation returns null without error', () async {
      fakeApi.onCaptureImage = (_) => null;

      final image = await pickPhoto.pickFromCamera();
      expect(image, isNull);
    });

    test('static PickPhoto.fromCamera delegates to instance', () async {
      final image = await PickPhoto.fromCamera();
      expect(image, isNotNull);
      expect(image!.source, ImageSource.camera);
    });
  });

  group('PickPhoto Cache Clearing', () {
    test('clearCache calls hostApi successfully', () async {
      await pickPhoto.clearPickerCache();
      expect(fakeApi.clearCacheCalled, isTrue);
    });

    test('static PickPhoto.clearCache delegates to instance', () async {
      await PickPhoto.clearCache();
      expect(fakeApi.clearCacheCalled, isTrue);
    });
  });

  group('Concurrency and In-flight Guard', () {
    test(
      'throws PickerBusyException when a simultaneous request is made',
      () async {
        final completer = Completer<PickedImageResult?>();
        fakeApi.onPickImage = (_) => completer.future;

        // Start first operation (will not complete immediately)
        final firstFuture = pickPhoto.pickFromGallery();
        expect(pickPhoto.isBusy, isTrue);

        // Attempt second operation simultaneously
        expect(
          () => pickPhoto.pickFromGallery(),
          throwsA(
            isA<PickerBusyException>().having(
              (e) => e.code,
              'code',
              'picker_busy',
            ),
          ),
        );

        // Attempt camera simultaneously
        expect(
          () => pickPhoto.pickFromCamera(),
          throwsA(isA<PickerBusyException>()),
        );

        // Attempt multiple simultaneously
        expect(
          () => pickPhoto.pickMultiple(),
          throwsA(isA<PickerBusyException>()),
        );

        // Complete first operation
        completer.complete(null);
        await firstFuture;

        expect(pickPhoto.isBusy, isFalse);

        // Reset handler and verify next operation succeeds
        fakeApi.onPickImage = null;
        final nextPick = await pickPhoto.pickFromGallery();
        expect(nextPick, isNotNull);
      },
    );
  });

  group('Error Mapping', () {
    void setupError(String code, String message) {
      fakeApi.onPickImage = (_) =>
          throw PlatformException(code: code, message: message);
    }

    test('maps picker_busy to PickerBusyException', () async {
      setupError('picker_busy', 'Busy');
      expect(
        () => pickPhoto.pickFromGallery(),
        throwsA(
          isA<PickerBusyException>().having(
            (e) => e.code,
            'code',
            'picker_busy',
          ),
        ),
      );
    });

    test('maps permission_denied to PermissionDeniedException', () async {
      setupError('permission_denied', 'No permission');
      expect(
        () => pickPhoto.pickFromGallery(),
        throwsA(
          isA<PermissionDeniedException>().having(
            (e) => e.code,
            'code',
            'permission_denied',
          ),
        ),
      );
    });

    test('maps camera_unavailable to CameraUnavailableException', () async {
      setupError('camera_unavailable', 'No camera hardware');
      expect(
        () => pickPhoto.pickFromGallery(),
        throwsA(
          isA<CameraUnavailableException>().having(
            (e) => e.code,
            'code',
            'camera_unavailable',
          ),
        ),
      );
    });

    test('maps platform_unavailable to PlatformUnavailableException', () async {
      setupError('platform_unavailable', 'Detached activity');
      expect(
        () => pickPhoto.pickFromGallery(),
        throwsA(
          isA<PlatformUnavailableException>().having(
            (e) => e.code,
            'code',
            'platform_unavailable',
          ),
        ),
      );
    });

    test('maps invalid_options to InvalidOptionsException', () async {
      setupError('invalid_options', 'Invalid dimensions');
      expect(
        () => pickPhoto.pickFromGallery(),
        throwsA(
          isA<InvalidOptionsException>().having(
            (e) => e.code,
            'code',
            'invalid_options',
          ),
        ),
      );
    });

    test('maps unsupported_format to UnsupportedFormatException', () async {
      setupError('unsupported_format', 'Cannot recompress animated GIF');
      expect(
        () => pickPhoto.pickFromGallery(),
        throwsA(
          isA<UnsupportedFormatException>().having(
            (e) => e.code,
            'code',
            'unsupported_format',
          ),
        ),
      );
    });

    test(
      'maps maximum_size_exceeded to MaximumSizeExceededException',
      () async {
        setupError('maximum_size_exceeded', 'Size exceeded limit');
        expect(
          () => pickPhoto.pickFromGallery(),
          throwsA(
            isA<MaximumSizeExceededException>().having(
              (e) => e.code,
              'code',
              'maximum_size_exceeded',
            ),
          ),
        );
      },
    );

    test('maps file_not_found to FileNotFoundException', () async {
      setupError('file_not_found', 'Missing file');
      expect(
        () => pickPhoto.pickFromGallery(),
        throwsA(
          isA<FileNotFoundException>().having(
            (e) => e.code,
            'code',
            'file_not_found',
          ),
        ),
      );
    });

    test(
      'maps image_processing_failed to ImageProcessingFailedException',
      () async {
        setupError('image_processing_failed', 'Bitmap decode error');
        expect(
          () => pickPhoto.pickFromGallery(),
          throwsA(
            isA<ImageProcessingFailedException>().having(
              (e) => e.code,
              'code',
              'image_processing_failed',
            ),
          ),
        );
      },
    );

    test('maps file_copy_failed to FileCopyFailedException', () async {
      setupError('file_copy_failed', 'IO Error');
      expect(
        () => pickPhoto.pickFromGallery(),
        throwsA(
          isA<FileCopyFailedException>().having(
            (e) => e.code,
            'code',
            'file_copy_failed',
          ),
        ),
      );
    });

    test('maps insufficient_storage to InsufficientStorageException', () async {
      setupError('insufficient_storage', 'Disk full');
      expect(
        () => pickPhoto.pickFromGallery(),
        throwsA(
          isA<InsufficientStorageException>().having(
            (e) => e.code,
            'code',
            'insufficient_storage',
          ),
        ),
      );
    });

    test('maps unknown code to NativePickerFailedException', () async {
      setupError('unknown_native_error', 'Something crashed');
      expect(
        () => pickPhoto.pickFromGallery(),
        throwsA(
          isA<NativePickerFailedException>().having(
            (e) => e.code,
            'code',
            'native_picker_failed',
          ),
        ),
      );
    });
  });
}
