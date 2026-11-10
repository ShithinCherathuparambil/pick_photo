import Flutter
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import ImageIO
import AVFoundation

public class PickPhotoPlugin: NSObject, FlutterPlugin, PickPhotoHostApi, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIAdaptivePresentationControllerDelegate {

    private static let cacheSubdir = "pick_photo"

    private var isBusy = false
    private let lock = NSLock()

    // Active operations tracking to prevent deleting active files in clearCache
    private var activeProcessingFiles = Set<String>()
    private let activeFilesLock = NSLock()

    // Continuations for active pickers
    private var singleContinuation: CheckedContinuation<PickedImageResult?, Error>?
    private var multiContinuation: CheckedContinuation<[PickedImageResult], Error>?
    private var cameraContinuation: CheckedContinuation<PickedImageResult?, Error>?

    // Current options
    private var currentSingleOptions: ImagePickOptionsDto?
    private var currentMultiOptions: MultiImagePickOptionsDto?
    private var currentCameraOptions: CameraPickOptionsDto?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = PickPhotoPlugin()
        PickPhotoHostApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    }

    // MARK: - PickPhotoHostApi

    func pickImage(options: ImagePickOptionsDto) async throws -> PickedImageResult? {
        try acquireLock()
        currentSingleOptions = options

        return try await withCheckedThrowingContinuation { continuation in
            singleContinuation = continuation
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: PigeonError(code: "platform_unavailable", message: "Plugin instance released", details: nil))
                    return
                }

                guard let rootViewController = self.topViewController() else {
                    self.releaseLock()
                    self.currentSingleOptions = nil
                    continuation.resume(throwing: PigeonError(code: "platform_unavailable", message: "No top view controller found", details: nil))
                    return
                }

                var configuration = PHPickerConfiguration(photoLibrary: .shared())
                configuration.selectionLimit = 1
                configuration.filter = .images
                configuration.preferredAssetRepresentationMode = .current

                let picker = PHPickerViewController(configuration: configuration)
                picker.delegate = self
                picker.presentationController?.delegate = self
                rootViewController.present(picker, animated: true)
            }
        }
    }

    func pickMultipleImages(options: MultiImagePickOptionsDto) async throws -> [PickedImageResult] {
        try acquireLock()
        currentMultiOptions = options

        return try await withCheckedThrowingContinuation { continuation in
            multiContinuation = continuation
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: PigeonError(code: "platform_unavailable", message: "Plugin instance released", details: nil))
                    return
                }

                guard let rootViewController = self.topViewController() else {
                    self.releaseLock()
                    self.currentMultiOptions = nil
                    continuation.resume(throwing: PigeonError(code: "platform_unavailable", message: "No top view controller found", details: nil))
                    return
                }

                var configuration = PHPickerConfiguration(photoLibrary: .shared())
                if let maxCount = options.maxCount, maxCount > 0 {
                    configuration.selectionLimit = Int(maxCount)
                } else {
                    configuration.selectionLimit = 0 // unlimited
                }
                configuration.filter = .images
                configuration.preferredAssetRepresentationMode = .current

                if #available(iOS 15.0, *) {
                    configuration.selection = .ordered
                }

                let picker = PHPickerViewController(configuration: configuration)
                picker.delegate = self
                picker.presentationController?.delegate = self
                rootViewController.present(picker, animated: true)
            }
        }
    }

    func captureImage(options: CameraPickOptionsDto) async throws -> PickedImageResult? {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            throw PigeonError(code: "camera_unavailable", message: "Camera is not available on this device", details: nil)
        }

        // Check camera permission
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus == .denied || authStatus == .restricted {
            throw PigeonError(code: "permission_denied", message: "Camera permission is denied", details: nil)
        }

        if authStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                throw PigeonError(code: "permission_denied", message: "Camera permission was not granted", details: nil)
            }
        }

        try acquireLock()
        currentCameraOptions = options

        return try await withCheckedThrowingContinuation { continuation in
            cameraContinuation = continuation
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: PigeonError(code: "platform_unavailable", message: "Plugin instance released", details: nil))
                    return
                }

                guard let rootViewController = self.topViewController() else {
                    self.releaseLock()
                    self.currentCameraOptions = nil
                    continuation.resume(throwing: PigeonError(code: "platform_unavailable", message: "No top view controller found", details: nil))
                    return
                }

                let picker = UIImagePickerController()
                picker.sourceType = .camera
                picker.delegate = self
                picker.presentationController?.delegate = self
                rootViewController.present(picker, animated: true)
            }
        }
    }

    func clearCache() async throws {
        let fileManager = FileManager.default
        let cacheDir = getCacheDirectory()

        guard fileManager.fileExists(atPath: cacheDir.path) else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            do {
                let fileUrls = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
                for fileUrl in fileUrls {
                    self.activeFilesLock.lock()
                    let isActive = self.activeProcessingFiles.contains(fileUrl.path)
                    self.activeFilesLock.unlock()

                    if !isActive {
                        try? fileManager.removeItem(at: fileUrl)
                    }
                }
            } catch {}
        }
    }

    // MARK: - PHPickerViewControllerDelegate

    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        let isSingle = singleContinuation != nil
        let singleCont = singleContinuation
        let multiCont = multiContinuation
        let singleOpts = currentSingleOptions
        let multiOpts = currentMultiOptions

        singleContinuation = nil
        multiContinuation = nil
        currentSingleOptions = nil
        currentMultiOptions = nil

        if results.isEmpty {
            releaseLock()
            if isSingle {
                singleCont?.resume(returning: nil)
            } else {
                multiCont?.resume(returning: [])
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                singleCont?.resume(throwing: PigeonError(code: "platform_unavailable", message: "Plugin released", details: nil))
                multiCont?.resume(throwing: PigeonError(code: "platform_unavailable", message: "Plugin released", details: nil))
                return
            }

            defer { self.releaseLock() }

            if isSingle {
                guard let firstResult = results.first else {
                    singleCont?.resume(returning: nil)
                    return
                }

                do {
                    let picked = try self.processPickerResult(
                        result: firstResult,
                        maxWidth: singleOpts?.maxWidth,
                        maxHeight: singleOpts?.maxHeight,
                        maxSizeBytes: singleOpts?.maxSizeBytes,
                        quality: singleOpts?.quality,
                        preserveOriginal: singleOpts?.preserveOriginal ?? true
                    )
                    singleCont?.resume(returning: picked)
                } catch {
                    singleCont?.resume(throwing: error)
                }
            } else {
                let maxCount = multiOpts?.maxCount.map(Int.init) ?? Int.max
                let limitedResults = results.count > maxCount ? Array(results.prefix(maxCount)) : results

                var pickedList: [PickedImageResult] = []
                var encounteredError: Error?

                for itemResult in limitedResults {
                    do {
                        let picked = try self.processPickerResult(
                            result: itemResult,
                            maxWidth: multiOpts?.maxWidth,
                            maxHeight: multiOpts?.maxHeight,
                            maxSizeBytes: multiOpts?.maxSizeBytes,
                            quality: multiOpts?.quality,
                            preserveOriginal: multiOpts?.preserveOriginal ?? true
                        )
                        pickedList.append(picked)
                    } catch {
                        encounteredError = error
                        break
                    }
                }

                if let err = encounteredError {
                    multiCont?.resume(throwing: err)
                } else {
                    multiCont?.resume(returning: pickedList)
                }
            }
        }
    }

    // MARK: - UIImagePickerControllerDelegate

    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)

        let cont = cameraContinuation
        let opts = currentCameraOptions
        cameraContinuation = nil
        currentCameraOptions = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                cont?.resume(throwing: PigeonError(code: "platform_unavailable", message: "Plugin released", details: nil))
                return
            }
            defer { self.releaseLock() }

            guard let image = (info[.originalImage] as? UIImage) ?? (info[.editedImage] as? UIImage) else {
                cont?.resume(returning: nil)
                return
            }

            do {
                let picked = try self.processCameraImage(
                    image: image,
                    maxWidth: opts?.maxWidth,
                    maxHeight: opts?.maxHeight,
                    maxSizeBytes: opts?.maxSizeBytes,
                    quality: opts?.quality,
                    preserveOriginal: opts?.preserveOriginal ?? true
                )
                cont?.resume(returning: picked)
            } catch {
                cont?.resume(throwing: error)
            }
        }
    }

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        let cont = cameraContinuation
        cameraContinuation = nil
        currentCameraOptions = nil
        releaseLock()
        cont?.resume(returning: nil)
    }

    // MARK: - UIAdaptivePresentationControllerDelegate

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if let singleCont = singleContinuation {
            singleContinuation = nil
            currentSingleOptions = nil
            releaseLock()
            singleCont.resume(returning: nil)
        }
        if let multiCont = multiContinuation {
            multiContinuation = nil
            currentMultiOptions = nil
            releaseLock()
            multiCont.resume(returning: [])
        }
        if let cameraCont = cameraContinuation {
            cameraContinuation = nil
            currentCameraOptions = nil
            releaseLock()
            cameraCont.resume(returning: nil)
        }
    }

    // MARK: - Image Processing & File Handling

    private func processPickerResult(
        result: PHPickerResult,
        maxWidth: Int64?,
        maxHeight: Int64?,
        maxSizeBytes: Int64?,
        quality: Int64?,
        preserveOriginal: BooleanLiteralType
    ) throws -> PickedImageResult {
        let itemProvider = result.itemProvider

        // Find matching image type identifier
        let imageTypeIdentifier = UTType.image.identifier

        var tempSourceUrl: URL?
        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        // Request file representation synchronously on background thread
        itemProvider.loadFileRepresentation(forTypeIdentifier: imageTypeIdentifier) { url, error in
            if let error = error {
                loadError = error
                semaphore.signal()
                return
            }

            guard let sourceUrl = url else {
                loadError = PigeonError(code: "file_not_found", message: "ItemProvider returned nil URL", details: nil)
                semaphore.signal()
                return
            }

            // Must copy file immediately before this block exits, as iOS deletes the temp file!
            let fileExt = sourceUrl.pathExtension.isEmpty ? "jpg" : sourceUrl.pathExtension
            let cacheDir = self.getCacheDirectory()
            let intermediateUrl = cacheDir.appendingPathComponent("raw_\(UUID().uuidString).\(fileExt)")

            do {
                try FileManager.default.copyItem(at: sourceUrl, to: intermediateUrl)
                tempSourceUrl = intermediateUrl
            } catch {
                loadError = PigeonError(code: "file_copy_failed", message: "Failed to copy picker file: \(error.localizedDescription)", details: nil)
            }

            semaphore.signal()
        }

        semaphore.wait()

        if let error = loadError {
            throw error
        }

        guard let sourceUrl = tempSourceUrl else {
            throw PigeonError(code: "file_not_found", message: "Failed to obtain source image URL", details: nil)
        }

        defer {
            try? FileManager.default.removeItem(at: sourceUrl)
        }

        let mimeType = getMimeType(for: sourceUrl)
        let fileExt = sourceUrl.pathExtension.isEmpty ? "jpg" : sourceUrl.pathExtension

        let shouldResizeOrCompress = (maxWidth != nil || maxHeight != nil || quality != nil) && !preserveOriginal

        if mimeType == "image/gif" && shouldResizeOrCompress {
            throw PigeonError(code: "unsupported_format", message: "Resizing or recompressing animated GIF is not supported without loss of animation", details: nil)
        }

        let targetDir = getCacheDirectory()
        let targetUrl = targetDir.appendingPathComponent("pick_photo_\(UUID().uuidString).\(fileExt)")

        trackActiveFile(targetUrl.path)
        defer { untrackActiveFile(targetUrl.path) }

        if !shouldResizeOrCompress {
            // Direct file move/copy without full bitmap decoding
            do {
                try FileManager.default.copyItem(at: sourceUrl, to: targetUrl)
            } catch {
                throw PigeonError(code: "file_copy_failed", message: "Failed to save image to cache: \(error.localizedDescription)", details: nil)
            }

            let fileSize = getFileSize(at: targetUrl)
            if let maxBytes = maxSizeBytes, fileSize > maxBytes {
                try? FileManager.default.removeItem(at: targetUrl)
                throw PigeonError(code: "maximum_size_exceeded", message: "File size \(fileSize) bytes exceeds limit of \(maxBytes) bytes", details: nil)
            }

            let (width, height) = readDimensions(from: targetUrl)

            return PickedImageResult(
                path: targetUrl.path,
                name: targetUrl.lastPathComponent,
                mimeType: mimeType,
                sizeBytes: fileSize,
                width: width,
                height: height
            )
        } else {
            // Resize and/or compress using CGImageSource thumbnailing for bounded memory
            return try resizeAndCompress(
                sourceUrl: sourceUrl,
                targetUrl: targetUrl,
                maxWidth: maxWidth.map(Int.init),
                maxHeight: maxHeight.map(Int.init),
                maxSizeBytes: maxSizeBytes,
                quality: quality.map(Int.init) ?? 90,
                originalMimeType: mimeType
            )
        }
    }

    private func processCameraImage(
        image: UIImage,
        maxWidth: Int64?,
        maxHeight: Int64?,
        maxSizeBytes: Int64?,
        quality: Int64?,
        preserveOriginal: BooleanLiteralType
    ) throws -> PickedImageResult {
        let targetDir = getCacheDirectory()
        let targetUrl = targetDir.appendingPathComponent("pick_photo_\(UUID().uuidString).jpg")

        trackActiveFile(targetUrl.path)
        defer { untrackActiveFile(targetUrl.path) }

        let shouldResizeOrCompress = (maxWidth != nil || maxHeight != nil || quality != nil) && !preserveOriginal

        let orientedImage = fixOrientation(image)
        let origWidth = Int(orientedImage.size.width)
        let origHeight = Int(orientedImage.size.height)

        let targetImage: UIImage
        if shouldResizeOrCompress {
            let maxW = maxWidth.map(Int.init) ?? origWidth
            let maxH = maxHeight.map(Int.init) ?? origHeight

            let scale = min(Double(maxW) / Double(origWidth), Double(maxH) / Double(origHeight), 1.0)
            let finalW = max(1, Int(Double(origWidth) * scale))
            let finalH = max(1, Int(Double(origHeight) * scale))

            if finalW != origWidth || finalH != origHeight {
                UIGraphicsBeginImageContextWithOptions(CGSize(width: finalW, height: finalH), false, 1.0)
                orientedImage.draw(in: CGRect(x: 0, y: 0, width: finalW, height: finalH))
                targetImage = UIGraphicsGetImageFromCurrentImageContext() ?? orientedImage
                UIGraphicsEndImageContext()
            } else {
                targetImage = orientedImage
            }
        } else {
            targetImage = orientedImage
        }

        let compressQuality = shouldResizeOrCompress ? (CGFloat(quality ?? 90) / 100.0) : 0.95
        guard let data = targetImage.jpegData(compressionQuality: compressQuality) else {
            throw PigeonError(code: "image_processing_failed", message: "Failed to encode camera image to JPEG", details: nil)
        }

        if let maxBytes = maxSizeBytes, Int64(data.count) > maxBytes {
            throw PigeonError(code: "maximum_size_exceeded", message: "Camera image size \(data.count) bytes exceeds limit of \(maxBytes) bytes", details: nil)
        }

        do {
            try data.write(to: targetUrl)
        } catch {
            throw PigeonError(code: "file_copy_failed", message: "Failed to write camera file: \(error.localizedDescription)", details: nil)
        }

        return PickedImageResult(
            path: targetUrl.path,
            name: targetUrl.lastPathComponent,
            mimeType: "image/jpeg",
            sizeBytes: Int64(data.count),
            width: Int64(targetImage.size.width),
            height: Int64(targetImage.size.height)
        )
    }

    private func resizeAndCompress(
        sourceUrl: URL,
        targetUrl: URL,
        maxWidth: Int?,
        maxHeight: Int?,
        maxSizeBytes: Int64?,
        quality: Int,
        originalMimeType: String
    ) throws -> PickedImageResult {
        guard let imageSource = CGImageSourceCreateWithURL(sourceUrl as CFURL, nil) else {
            throw PigeonError(code: "image_processing_failed", message: "Failed to create image source from URL", details: nil)
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            throw PigeonError(code: "image_processing_failed", message: "Failed to read image properties", details: nil)
        }

        let rawWidth = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let rawHeight = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1

        let isSwapped = orientation >= 5 && orientation <= 8
        let origWidth = isSwapped ? rawHeight : rawWidth
        let origHeight = isSwapped ? rawWidth : rawHeight

        guard origWidth > 0 && origHeight > 0 else {
            throw PigeonError(code: "image_processing_failed", message: "Invalid image dimensions", details: nil)
        }

        let maxW = maxWidth ?? origWidth
        let maxH = maxHeight ?? origHeight
        let scale = min(Double(maxW) / Double(origWidth), Double(maxH) / Double(origHeight), 1.0)
        let finalWidth = max(1, Int(Double(origWidth) * scale))
        let finalHeight = max(1, Int(Double(origHeight) * scale))
        let maxPixelSize = max(finalWidth, finalHeight)

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgThumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions as CFDictionary) else {
            throw PigeonError(code: "image_processing_failed", message: "Failed to generate thumbnail image", details: nil)
        }

        let uiImage = UIImage(cgImage: cgThumbnail)
        let compressQuality = CGFloat(quality.clamped(to: 1...100)) / 100.0

        let outputData: Data
        let outMimeType: String
        let destinationUrl: URL

        if originalMimeType == "image/png" && quality >= 100 {
            guard let pngData = uiImage.pngData() else {
                throw PigeonError(code: "image_processing_failed", message: "Failed to encode PNG image", details: nil)
            }
            outputData = pngData
            outMimeType = "image/png"
            destinationUrl = targetUrl.deletingPathExtension().appendingPathExtension("png")
        } else {
            guard let jpegData = uiImage.jpegData(compressionQuality: compressQuality) else {
                throw PigeonError(code: "image_processing_failed", message: "Failed to encode JPEG image", details: nil)
            }
            outputData = jpegData
            outMimeType = "image/jpeg"
            destinationUrl = targetUrl.deletingPathExtension().appendingPathExtension("jpg")
        }

        if let maxBytes = maxSizeBytes, Int64(outputData.count) > maxBytes {
            throw PigeonError(code: "maximum_size_exceeded", message: "Processed image size \(outputData.count) bytes exceeds limit of \(maxBytes) bytes", details: nil)
        }

        do {
            try outputData.write(to: destinationUrl)
        } catch {
            throw PigeonError(code: "file_copy_failed", message: "Failed to write processed image: \(error.localizedDescription)", details: nil)
        }

        return PickedImageResult(
            path: destinationUrl.path,
            name: destinationUrl.lastPathComponent,
            mimeType: outMimeType,
            sizeBytes: Int64(outputData.count),
            width: Int64(finalWidth),
            height: Int64(finalHeight)
        )
    }

    private func readDimensions(from url: URL) -> (Int64?, Int64?) {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] else {
            return (nil, nil)
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1

        guard let w = width, let h = height else { return (nil, nil) }

        if orientation >= 5 && orientation <= 8 {
            return (Int64(h), Int64(w))
        } else {
            return (Int64(w), Int64(h))
        }
    }

    private func getMimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if let utType = UTType(filenameExtension: ext), let mime = utType.preferredMIMEType {
            return mime
        }
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "heif": return "image/heif"
        case "webp": return "image/webp"
        default: return "image/jpeg"
        }
    }

    private func getFileSize(at url: URL) -> Int64 {
        let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attr?[.size] as? Int64) ?? 0
    }

    private func fixOrientation(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up {
            return image
        }
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return normalizedImage
    }

    private func getCacheDirectory() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let cacheDir = tempDir.appendingPathComponent(Self.cacheSubdir)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
        return cacheDir
    }

    private func trackActiveFile(_ path: String) {
        activeFilesLock.lock()
        activeProcessingFiles.insert(path)
        activeFilesLock.unlock()
    }

    private func untrackActiveFile(_ path: String) {
        activeFilesLock.lock()
        activeProcessingFiles.remove(path)
        activeFilesLock.unlock()
    }

    private func acquireLock() throws {
        lock.lock()
        defer { lock.unlock() }
        if isBusy {
            throw PigeonError(code: "picker_busy", message: "A picker operation is already in progress", details: nil)
        }
        isBusy = true
    }

    private func releaseLock() {
        lock.lock()
        defer { lock.unlock() }
        isBusy = false
    }

    private func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }),
              let rootVC = keyWindow.rootViewController else {
            return nil
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }

}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
