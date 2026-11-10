import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/platform/messages.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/src/main/kotlin/com/example/pick_photo/Messages.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.example.pick_photo'),
    swiftOut: 'ios/pick_photo/Sources/pick_photo/Messages.g.swift',
    swiftOptions: SwiftOptions(),
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
class PickedImageResult {
  PickedImageResult({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    this.width,
    this.height,
  });

  final String path;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final int? width;
  final int? height;
}

class ImagePickOptionsDto {
  ImagePickOptionsDto({
    this.maxWidth,
    this.maxHeight,
    this.maxSizeBytes,
    this.quality,
    this.preserveOriginal = true,
  });

  final int? maxWidth;
  final int? maxHeight;
  final int? maxSizeBytes;
  final int? quality;
  final bool preserveOriginal;
}

class MultiImagePickOptionsDto {
  MultiImagePickOptionsDto({
    this.maxCount,
    this.maxWidth,
    this.maxHeight,
    this.maxSizeBytes,
    this.quality,
    this.preserveOriginal = true,
  });

  final int? maxCount;
  final int? maxWidth;
  final int? maxHeight;
  final int? maxSizeBytes;
  final int? quality;
  final bool preserveOriginal;
}

class CameraPickOptionsDto {
  CameraPickOptionsDto({
    this.maxWidth,
    this.maxHeight,
    this.maxSizeBytes,
    this.quality,
    this.preserveOriginal = true,
  });

  final int? maxWidth;
  final int? maxHeight;
  final int? maxSizeBytes;
  final int? quality;
  final bool preserveOriginal;
}

@HostApi()
abstract class PickPhotoHostApi {
  @async
  PickedImageResult? pickImage(ImagePickOptionsDto options);

  @async
  List<PickedImageResult> pickMultipleImages(MultiImagePickOptionsDto options);

  @async
  PickedImageResult? captureImage(CameraPickOptionsDto options);

  @async
  void clearCache();
}
