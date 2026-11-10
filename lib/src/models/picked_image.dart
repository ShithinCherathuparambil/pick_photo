import 'dart:io';

import 'package:flutter/foundation.dart';

import 'image_source.dart';

/// Represents an image picked from the gallery or captured with the device camera.
@immutable
class PickedImage {
  /// Creates a [PickedImage] instance.
  const PickedImage({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.extension,
    required this.sizeBytes,
    required this.source,
    this.width,
    this.height,
  });

  /// Absolute file system path to the local picked image file.
  final String path;

  /// File name of the image including extension (e.g. `image_1234.jpg`).
  final String name;

  /// MIME type of the image (e.g. `image/jpeg`, `image/png`, `image/heic`).
  final String mimeType;

  /// File extension without the leading dot (e.g. `jpg`, `png`, `heic`).
  final String extension;

  /// File size in bytes.
  final int sizeBytes;

  /// Width in pixels, if available from image metadata.
  final int? width;

  /// Height in pixels, if available from image metadata.
  final int? height;

  /// The source from which this image was picked (gallery or camera).
  final ImageSource source;

  /// Returns a [File] handle to the local image file.
  File get file => File(path);

  /// Asynchronously reads the image file contents as raw bytes.
  Future<Uint8List> readAsBytes() => file.readAsBytes();

  /// Copies this image to a persistent [destinationPath].
  ///
  /// Any non-existent parent directories are created automatically.
  /// Returns the persistent [File] at [destinationPath].
  Future<File> saveTo(String destinationPath) async {
    final destFile = File(destinationPath);
    final parentDir = destFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }
    return file.copy(destinationPath);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PickedImage &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          name == other.name &&
          mimeType == other.mimeType &&
          extension == other.extension &&
          sizeBytes == other.sizeBytes &&
          width == other.width &&
          height == other.height &&
          source == other.source;

  @override
  int get hashCode => Object.hash(
    path,
    name,
    mimeType,
    extension,
    sizeBytes,
    width,
    height,
    source,
  );

  @override
  String toString() =>
      'PickedImage(path: $path, name: $name, mimeType: $mimeType, extension: $extension, sizeBytes: $sizeBytes, width: $width, height: $height, source: $source)';
}
