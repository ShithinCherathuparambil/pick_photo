import 'package:flutter/services.dart';

/// Base exception for all errors thrown by the `pick_photo` plugin.
abstract class PickPhotoException implements Exception {
  /// Creates a [PickPhotoException] with [code], [message], and optional [details].
  const PickPhotoException(this.code, this.message, [this.details]);

  /// Machine-readable error code.
  final String code;

  /// Human-readable error description.
  final String message;

  /// Optional underlying platform details.
  final dynamic details;

  @override
  String toString() => '$runtimeType($code: $message)';
}

/// Thrown when a picker operation is requested while another operation is in progress.
class PickerBusyException extends PickPhotoException {
  /// Creates a [PickerBusyException].
  const PickerBusyException([
    String message = 'A picker operation is already in progress.',
    dynamic details,
  ]) : super('picker_busy', message, details);
}

/// Thrown when user or system denies required permissions (e.g. camera permission).
class PermissionDeniedException extends PickPhotoException {
  /// Creates a [PermissionDeniedException].
  const PermissionDeniedException(String message, [dynamic details])
    : super('permission_denied', message, details);
}

/// Thrown when the device camera is unavailable or missing.
class CameraUnavailableException extends PickPhotoException {
  /// Creates a [CameraUnavailableException].
  const CameraUnavailableException(String message, [dynamic details])
    : super('camera_unavailable', message, details);
}

/// Thrown when a platform feature or activity is unavailable or detached.
class PlatformUnavailableException extends PickPhotoException {
  /// Creates a [PlatformUnavailableException].
  const PlatformUnavailableException(String message, [dynamic details])
    : super('platform_unavailable', message, details);
}

/// Thrown when invalid options (e.g. negative dimensions or quality outside 1-100) are supplied.
class InvalidOptionsException extends PickPhotoException {
  /// Creates an [InvalidOptionsException].
  const InvalidOptionsException(String message, [dynamic details])
    : super('invalid_options', message, details);
}

/// Thrown when an image format conversion is unsupported (e.g. resizing an animated GIF).
class UnsupportedFormatException extends PickPhotoException {
  /// Creates an [UnsupportedFormatException].
  const UnsupportedFormatException(String message, [dynamic details])
    : super('unsupported_format', message, details);
}

/// Thrown when selected or processed file size exceeds the configured maximum.
class MaximumSizeExceededException extends PickPhotoException {
  /// Creates a [MaximumSizeExceededException].
  const MaximumSizeExceededException(String message, [dynamic details])
    : super('maximum_size_exceeded', message, details);
}

/// Thrown when a specified file or source stream cannot be found or read.
class FileNotFoundException extends PickPhotoException {
  /// Creates a [FileNotFoundException].
  const FileNotFoundException(String message, [dynamic details])
    : super('file_not_found', message, details);
}

/// Thrown when image decoding, resizing, or compression fails.
class ImageProcessingFailedException extends PickPhotoException {
  /// Creates an [ImageProcessingFailedException].
  const ImageProcessingFailedException(String message, [dynamic details])
    : super('image_processing_failed', message, details);
}

/// Thrown when copying a picked file to the cache directory fails.
class FileCopyFailedException extends PickPhotoException {
  /// Creates a [FileCopyFailedException].
  const FileCopyFailedException(String message, [dynamic details])
    : super('file_copy_failed', message, details);
}

/// Thrown when local storage space is insufficient to complete the operation.
class InsufficientStorageException extends PickPhotoException {
  /// Creates an [InsufficientStorageException].
  const InsufficientStorageException(String message, [dynamic details])
    : super('insufficient_storage', message, details);
}

/// Thrown when the underlying native system picker fails unexpectedly.
class NativePickerFailedException extends PickPhotoException {
  /// Creates a [NativePickerFailedException].
  const NativePickerFailedException(String message, [dynamic details])
    : super('native_picker_failed', message, details);
}

/// Maps platform exceptions to strongly typed [PickPhotoException]s.
PickPhotoException mapPlatformException(Object error) {
  if (error is PickPhotoException) {
    return error;
  }

  if (error is PlatformException) {
    final code = error.code;
    final message = error.message ?? 'Platform operation failed.';
    final details = error.details;

    switch (code) {
      case 'picker_busy':
        return PickerBusyException(message, details);
      case 'permission_denied':
        return PermissionDeniedException(message, details);
      case 'camera_unavailable':
        return CameraUnavailableException(message, details);
      case 'platform_unavailable':
        return PlatformUnavailableException(message, details);
      case 'invalid_options':
        return InvalidOptionsException(message, details);
      case 'unsupported_format':
        return UnsupportedFormatException(message, details);
      case 'maximum_size_exceeded':
        return MaximumSizeExceededException(message, details);
      case 'file_not_found':
        return FileNotFoundException(message, details);
      case 'image_processing_failed':
        return ImageProcessingFailedException(message, details);
      case 'file_copy_failed':
        return FileCopyFailedException(message, details);
      case 'insufficient_storage':
        return InsufficientStorageException(message, details);
      case 'native_picker_failed':
      default:
        return NativePickerFailedException(message, details);
    }
  }

  return NativePickerFailedException(error.toString());
}
