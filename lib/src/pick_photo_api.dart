import 'package:flutter/services.dart';

import 'exceptions/pick_photo_exception.dart';
import 'models/image_pick_options.dart';
import 'models/image_source.dart';
import 'models/picked_image.dart';
import 'platform/messages.g.dart';

/// Primary interface for picking and capturing photos with native OS pickers.
class PickPhoto {
  /// Creates a [PickPhoto] instance.
  ///
  /// Optionally accepts a custom [PickPhotoHostApi] for testing and mocking.
  PickPhoto({PickPhotoHostApi? hostApi})
    : _hostApi = hostApi ?? PickPhotoHostApi();

  /// The active singleton instance used by static convenience methods.
  static PickPhoto instance = PickPhoto();

  final PickPhotoHostApi _hostApi;
  bool _isBusy = false;

  /// Whether a picker or capture operation is currently in flight.
  bool get isBusy => _isBusy;

  // --- Static Convenience API ---

  /// Picks a single photo from the device photo gallery.
  ///
  /// Returns a [PickedImage] if an image was selected, or `null` if the user
  /// cancelled the picker without selecting an image.
  ///
  /// Throws [PickerBusyException] if another picker operation is already in flight.
  /// Throws [InvalidOptionsException] if [options] contains invalid values.
  /// Throws [PickPhotoException] subclasses on platform errors.
  static Future<PickedImage?> fromGallery({ImagePickOptions? options}) {
    return instance.pickFromGallery(options: options);
  }

  /// Captures a photo using the native device camera.
  ///
  /// Returns a [PickedImage] if a photo was captured, or `null` if the user
  /// cancelled capture.
  ///
  /// Throws [CameraUnavailableException] if the device has no camera available.
  /// Throws [PermissionDeniedException] if camera permission is denied.
  /// Throws [PickerBusyException] if another picker operation is already in flight.
  /// Throws [InvalidOptionsException] if [options] contains invalid values.
  /// Throws [PickPhotoException] subclasses on platform errors.
  static Future<PickedImage?> fromCamera({ImagePickOptions? options}) {
    return instance.pickFromCamera(options: options);
  }

  /// Picks multiple photos from the device photo gallery.
  ///
  /// [maxCount] optionally limits the maximum number of images the user can select.
  /// If [maxCount] is omitted or null, selection is unlimited.
  ///
  /// Returns a list of [PickedImage]s, or an empty list `[]` if the user cancelled.
  ///
  /// Throws [PickerBusyException] if another picker operation is already in flight.
  /// Throws [InvalidOptionsException] if [maxCount] <= 0 or [options] is invalid.
  /// Throws [PickPhotoException] subclasses on platform errors.
  static Future<List<PickedImage>> multiple({
    int? maxCount,
    ImagePickOptions? options,
  }) {
    return instance.pickMultiple(maxCount: maxCount, options: options);
  }

  /// Clears temporary cache files created by the plugin.
  ///
  /// Files currently in use by an active operation are preserved.
  static Future<void> clearCache() {
    return instance.clearPickerCache();
  }

  // --- Instance Methods ---

  /// Picks a single photo from the device gallery using this instance.
  Future<PickedImage?> pickFromGallery({ImagePickOptions? options}) async {
    final opts = options ?? ImagePickOptions();
    opts.validate();

    _acquireLock();
    try {
      final dto = ImagePickOptionsDto(
        maxWidth: opts.maxWidth,
        maxHeight: opts.maxHeight,
        maxSizeBytes: opts.maxSizeBytes,
        quality: opts.quality,
        preserveOriginal: opts.preserveOriginal,
      );

      final result = await _hostApi.pickImage(dto);
      if (result == null) return null;
      return _mapResult(result, ImageSource.gallery);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    } catch (e) {
      throw mapPlatformException(e);
    } finally {
      _releaseLock();
    }
  }

  /// Captures a photo using the native device camera using this instance.
  Future<PickedImage?> pickFromCamera({ImagePickOptions? options}) async {
    final opts = options ?? ImagePickOptions();
    opts.validate();

    _acquireLock();
    try {
      final dto = CameraPickOptionsDto(
        maxWidth: opts.maxWidth,
        maxHeight: opts.maxHeight,
        maxSizeBytes: opts.maxSizeBytes,
        quality: opts.quality,
        preserveOriginal: opts.preserveOriginal,
      );

      final result = await _hostApi.captureImage(dto);
      if (result == null) return null;
      return _mapResult(result, ImageSource.camera);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    } catch (e) {
      throw mapPlatformException(e);
    } finally {
      _releaseLock();
    }
  }

  /// Picks multiple photos from the gallery using this instance.
  Future<List<PickedImage>> pickMultiple({
    int? maxCount,
    ImagePickOptions? options,
  }) async {
    if (maxCount != null && maxCount <= 0) {
      throw const InvalidOptionsException('maxCount must be greater than 0.');
    }

    final opts = options ?? ImagePickOptions();
    opts.validate();

    _acquireLock();
    try {
      final dto = MultiImagePickOptionsDto(
        maxCount: maxCount,
        maxWidth: opts.maxWidth,
        maxHeight: opts.maxHeight,
        maxSizeBytes: opts.maxSizeBytes,
        quality: opts.quality,
        preserveOriginal: opts.preserveOriginal,
      );

      final results = await _hostApi.pickMultipleImages(dto);
      return results
          .map((res) => _mapResult(res, ImageSource.gallery))
          .toList(growable: false);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    } catch (e) {
      throw mapPlatformException(e);
    } finally {
      _releaseLock();
    }
  }

  /// Clears plugin temporary cache files using this instance.
  Future<void> clearPickerCache() async {
    try {
      await _hostApi.clearCache();
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    } catch (e) {
      throw mapPlatformException(e);
    }
  }

  // --- Internal Helpers ---

  void _acquireLock() {
    if (_isBusy) {
      throw const PickerBusyException();
    }
    _isBusy = true;
  }

  void _releaseLock() {
    _isBusy = false;
  }

  PickedImage _mapResult(PickedImageResult res, ImageSource source) {
    final fileExt = _extractExtension(res.name, res.path);
    return PickedImage(
      path: res.path,
      name: res.name,
      mimeType: res.mimeType,
      extension: fileExt,
      sizeBytes: res.sizeBytes,
      width: res.width,
      height: res.height,
      source: source,
    );
  }

  String _extractExtension(String name, String path) {
    final dotInName = name.lastIndexOf('.');
    if (dotInName != -1 && dotInName < name.length - 1) {
      return name.substring(dotInName + 1).toLowerCase();
    }
    final dotInPath = path.lastIndexOf('.');
    if (dotInPath != -1 && dotInPath < path.length - 1) {
      return path.substring(dotInPath + 1).toLowerCase();
    }
    return 'jpg';
  }
}
