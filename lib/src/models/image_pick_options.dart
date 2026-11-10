import 'package:flutter/foundation.dart';
import '../exceptions/pick_photo_exception.dart';

/// Configuration options for picking or capturing an image.
@immutable
class ImagePickOptions {
  /// Creates an [ImagePickOptions] instance.
  ///
  /// Throws [InvalidOptionsException] if:
  /// - [maxWidth] is non-null and <= 0
  /// - [maxHeight] is non-null and <= 0
  /// - [maxSizeBytes] is non-null and <= 0
  /// - [quality] is non-null and outside the range `[1, 100]`
  ImagePickOptions({
    this.maxWidth,
    this.maxHeight,
    this.maxSizeBytes,
    this.quality,
    this.preserveOriginal = true,
  }) {
    validate();
  }

  /// Maximum target width in pixels.
  ///
  /// If specified and [preserveOriginal] is false, the image will be resized
  /// to fit within this width while strictly preserving aspect ratio.
  final int? maxWidth;

  /// Maximum target height in pixels.
  ///
  /// If specified and [preserveOriginal] is false, the image will be resized
  /// to fit within this height while strictly preserving aspect ratio.
  final int? maxHeight;

  /// Maximum allowed file size in bytes.
  ///
  /// If the selected or processed image exceeds this limit, a
  /// [MaximumSizeExceededException] is thrown.
  final int? maxSizeBytes;

  /// Compression quality from 1 to 100 (where 100 is maximum quality).
  ///
  /// Only applied when [preserveOriginal] is false.
  final int? quality;

  /// Whether to preserve the original format, encoding, and metadata.
  ///
  /// Defaults to `true`. When true, the original image bytes are copied directly
  /// without re-encoding or bitmap decompression, preserving original formats
  /// (including HEIC, animated GIF, and PNG) and full fidelity.
  ///
  /// Set to `false` when explicit resizing ([maxWidth], [maxHeight]) or
  /// quality compression ([quality]) is desired.
  final bool preserveOriginal;

  /// Validates options and throws [InvalidOptionsException] on invalid values.
  void validate() {
    if (maxWidth != null && maxWidth! <= 0) {
      throw const InvalidOptionsException('maxWidth must be greater than 0.');
    }
    if (maxHeight != null && maxHeight! <= 0) {
      throw const InvalidOptionsException('maxHeight must be greater than 0.');
    }
    if (maxSizeBytes != null && maxSizeBytes! <= 0) {
      throw const InvalidOptionsException('maxSizeBytes must be greater than 0.');
    }
    if (quality != null && (quality! < 1 || quality! > 100)) {
      throw const InvalidOptionsException(
        'quality must be an integer between 1 and 100.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImagePickOptions &&
          runtimeType == other.runtimeType &&
          maxWidth == other.maxWidth &&
          maxHeight == other.maxHeight &&
          maxSizeBytes == other.maxSizeBytes &&
          quality == other.quality &&
          preserveOriginal == other.preserveOriginal;

  @override
  int get hashCode => Object.hash(
        maxWidth,
        maxHeight,
        maxSizeBytes,
        quality,
        preserveOriginal,
      );

  @override
  String toString() =>
      'ImagePickOptions(maxWidth: $maxWidth, maxHeight: $maxHeight, maxSizeBytes: $maxSizeBytes, quality: $quality, preserveOriginal: $preserveOriginal)';
}
