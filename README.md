# pick_photo

[![pub package](https://img.shields.io/pub/v/pick_photo.svg)](https://pub.dev/packages/pick_photo)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/shithin/pick_photo/blob/main/LICENSE)

A modern, fast, privacy-friendly, production-ready Flutter photo picker plugin. Built from scratch with native Android Kotlin (AndroidX Photo Picker & Activity Result APIs) and iOS Swift (PhotosUI `PHPickerViewController` & `UIImagePickerController`), communicating over Pigeon-generated type-safe platform channels.

Zero runtime dependency on `image_picker`, `file_picker`, `photo_manager`, or `permission_handler`.

---

## Features

- **Genuine Native Pickers**: Android Photo Picker (`PickVisualMedia` / `PickMultipleVisualMedia`) and iOS PhotosUI (`PHPickerViewController`).
- **Privacy-First**: No broad storage or media library permission prompts required for gallery access on Android or iOS.
- **Type-Safe Channels**: Built on Pigeon code generation for robust, compiler-verified communication without loose string channels.
- **Independent Native Camera**: Dedicated camera capture using Android `TakePicture` contract with `FileProvider` and iOS `UIImagePickerController`.
- **Single & Multiple Selection**: Pick single or multiple images with optional selection count limits (`maxCount`).
- **Original Format Preservation**: Preserves original formats (JPEG, PNG, HEIC/HEIF, animated GIF, WebP) and EXIF metadata by default without unsolicited transcoding.
- **Memory-Bounded Processing**: Avoids full-resolution bitmap decompression when reading dimensions and copying files. Uses `ImageIO` thumbnailing on iOS and sample-size downsampling on Android when resizing.
- **Aspect-Ratio Resizing**: Optional target dimensions (`maxWidth`, `maxHeight`) and compression quality (`quality: 1..100`).
- **Maximum File Size Validation**: Bounded streaming validation aborts early when images exceed `maxSizeBytes`.
- **Concurrency Guard**: Rejects conflicting overlapping requests with `PickerBusyException`.
- **Cache Management**: Safe temporary file storage with `PickPhoto.clearCache()`, protecting files active in ongoing operations.
- **Direct Save Helper**: Convenient `PickedImage.saveTo(destinationPath)` to store images in permanent application directories.

---

## Platform Support

| Platform | Minimum Version | Native Implementation | Permissions Required |
|:---|:---|:---|:---|
| **Android** | API 23 (Android 6.0+) | Kotlin, Photo Picker (`MediaStore.ACTION_PICK_IMAGES`), fallback `ACTION_OPEN_DOCUMENT`, FileProvider | None for gallery. None for camera intent |
| **iOS** | iOS 14.0+ | Swift, `PHPickerViewController`, `UIImagePickerController` | None for gallery. `NSCameraUsageDescription` for camera |

---

## Installation

Add `pick_photo` to your `pubspec.yaml`:

```yaml
dependencies:
  pick_photo: ^0.0.1
```

Or run:

```bash
flutter pub add pick_photo
```

---

## Platform Setup

### Android

No extra manifest changes are required for gallery picking.

For camera capture, `pick_photo` includes an integrated `FileProvider` configuration that merges automatically into your app's manifest.

If your application targets Android 11 (API 30) or above, camera intent resolution is pre-configured.

### iOS

In your iOS project's `ios/Runner/Info.plist`, declare the camera usage description if using `PickPhoto.fromCamera()`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app requires camera access to capture photos.</string>
```

> **Note:** Gallery picking with `PHPickerViewController` runs out-of-process and does not require `NSPhotoLibraryUsageDescription` or broad photo library access.

---

## Usage Guide

### 1. Pick a Single Image

```dart
import 'package:pick_photo/pick_photo.dart';

final PickedImage? image = await PickPhoto.fromGallery();
if (image != null) {
  print('Picked image path: ${image.path}');
  print('Name: ${image.name}');
  print('Size: ${image.sizeBytes} bytes');
  print('Dimensions: ${image.width} x ${image.height}');
  print('MIME type: ${image.mimeType}');
} else {
  print('User cancelled selection.');
}
```

### 2. Pick Multiple Images with a Limit

```dart
final List<PickedImage> images = await PickPhoto.multiple(
  maxCount: 5,
);

for (final image in images) {
  print('Image: ${image.name} (${image.extension})');
}
```

### 3. Capture Photo from Device Camera

```dart
final PickedImage? photo = await PickPhoto.fromCamera();
if (photo != null) {
  print('Captured photo: ${photo.path}');
  print('Source: ${photo.source}'); // ImageSource.camera
}
```

### 4. Advanced Options (Resizing, Quality, Max File Size)

By default, `preserveOriginal: true` is enabled, copying the native file directly without re-compression:

```dart
final image = await PickPhoto.fromGallery(
  options: ImagePickOptions(
    preserveOriginal: false, // Enable processing
    maxWidth: 1920,
    maxHeight: 1080,
    quality: 85, // 1 to 100
    maxSizeBytes: 5 * 1024 * 1024, // 5 MB limit
  ),
);
```

### 5. Accessing File Bytes & Saving Permanently

Picked images reside in the plugin's temporary cache directory, which may be purged by the OS when space is needed. To retain an image permanently:

```dart
// Read raw bytes directly:
final Uint8List bytes = await image.readAsBytes();

// Save to permanent application documents:
final File permanentFile = await image.saveTo('/path/to/documents/my_photo.jpg');
```

### 6. Clear Temporary Cache

```dart
// Safely deletes temporary picked files without affecting in-flight operations:
await PickPhoto.clearCache();
```

---

## PickedImage Model

| Property | Type | Description |
|:---|:---|:---|
| `path` | `String` | Absolute local file system path to the image |
| `name` | `String` | File name including extension (e.g. `pick_photo_123.jpg`) |
| `mimeType` | `String` | MIME type (e.g. `image/jpeg`, `image/png`, `image/heic`) |
| `extension` | `String` | Lowercase file extension without dot (`jpg`, `png`, `heic`) |
| `sizeBytes` | `int` | File size in bytes |
| `width` | `int?` | Pixel width from image metadata (orientation-adjusted) |
| `height` | `int?` | Pixel height from image metadata (orientation-adjusted) |
| `source` | `ImageSource` | `ImageSource.gallery` or `ImageSource.camera` |
| `file` | `File` | Convenience getter returning a Dart `File` handle |
| `readAsBytes()` | `Future<Uint8List>` | Reads the image file bytes |
| `saveTo(dest)` | `Future<File>` | Copies file to a destination path, creating directories |

---

## Typed Exceptions

All plugin errors inherit from `PickPhotoException`:

```dart
try {
  final image = await PickPhoto.fromGallery();
} on PickerBusyException {
  // A picker operation is already in progress.
} on MaximumSizeExceededException catch (e) {
  // Selected image exceeded the configured maxSizeBytes.
} on CameraUnavailableException {
  // Device has no camera or camera hardware cannot be accessed.
} on PermissionDeniedException {
  // Camera permission was denied.
} on UnsupportedFormatException catch (e) {
  // Attempted to resize/recompress an unsupported format (e.g. animated GIF).
} on InvalidOptionsException catch (e) {
  // Invalid options passed (e.g. negative dimensions or quality outside 1..100).
} on PickPhotoException catch (e) {
  // General plugin error: code, message, and details available.
  print('[${e.code}] ${e.message}');
}
```

---

## Memory & Performance Design

1. **No Platform Channel Byte Transfers**: Images are streamed directly on native file systems. Platform channels only transfer lightweight metadata, preventing memory spikes and garbage collection pauses.
2. **Header-Only Dimension Extraction**: Image dimensions are read without decompressing full bitmaps into RAM using `BitmapFactory.Options.inJustDecodeBounds` on Android and `CGImageSourceCopyPropertiesAtIndex` on iOS.
3. **Hardware-Accelerated Downsampling**: When resizing, iOS uses `CGImageSourceCreateThumbnailAtIndex` and Android computes optimal `inSampleSize` to bound peak memory usage.
4. **Orientation Correction**: Normalizes EXIF orientation on camera images so photos display right-side-up across all platforms.
5. **Isolated Cache**: Files created during failed or cancelled camera operations are deleted immediately.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
