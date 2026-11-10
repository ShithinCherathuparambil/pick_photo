## 0.0.2

* Updated verified repository, homepage, and issue tracker URLs to GitHub.
* Added GitHub Actions CI workflow covering static analysis, unit tests, dry-run publishing, and Android/iOS build checks.
* Verified live device execution on Android (Photo Picker, Camera, Multi-pick).

## 0.0.1

* Initial release of `pick_photo`.
* Genuine native implementation using Android Photo Picker (`ActivityResultContracts.PickVisualMedia` / `PickMultipleVisualMedia`) and AndroidX `ACTION_OPEN_DOCUMENT` fallback.
* Genuine native implementation using iOS PhotosUI (`PHPickerViewController`) and `UIImagePickerController` for camera.
* Type-safe platform channel communication generated with Pigeon.
* Separate native device camera capture flow with automatic EXIF orientation preservation and isolated cache management.
* Configurable single and multiple gallery selection with selection count limit.
* Zero runtime dependency on `image_picker`, `file_picker`, `photo_manager`, or `permission_handler`.
* Memory-bounded image processing, thumbnail downsampling, and optional aspect-ratio-preserving resizing (`maxWidth`, `maxHeight`) and compression (`quality`).
* Preserves original image formats (JPEG, PNG, HEIC/HEIF, animated GIF, WebP) by default without unwanted transcoding.
* Strongly-typed exception model: `PickerBusyException`, `PermissionDeniedException`, `CameraUnavailableException`, `PlatformUnavailableException`, `InvalidOptionsException`, `UnsupportedFormatException`, `MaximumSizeExceededException`, `FileNotFoundException`, `ImageProcessingFailedException`, `FileCopyFailedException`, `InsufficientStorageException`, and `NativePickerFailedException`.
* Plugin cache management with `PickPhoto.clearCache()` preserving active in-flight files.
* Local persistent copy helper: `PickedImage.saveTo(destinationPath)`.
* Full Dart unit and widget test suite with mocked platform channel interfaces.
* Complete example application with live preview, metadata inspect, options customization, and cache operations.
