package com.example.pick_photo

import android.app.Activity
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import android.os.Build
import android.os.ext.SdkExtensions
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import androidx.exifinterface.media.ExifInterface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.Continuation
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine
import kotlin.math.roundToInt

class PickPhotoPlugin : FlutterPlugin, ActivityAware, PluginRegistry.ActivityResultListener, PickPhotoHostApi {

    companion object {
        private const val REQUEST_CODE_SINGLE_GALLERY = 49101
        private const val REQUEST_CODE_MULTI_GALLERY = 49102
        private const val REQUEST_CODE_CAMERA = 49103

        private const val CACHE_DIR_NAME = "pick_photo"
        private const val CAMERA_CACHE_DIR_NAME = "pick_photo_camera"
    }

    private var context: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private val isBusy = AtomicBoolean(false)

    // Current pending operation continuation and state
    private var pendingSingleContinuation: Continuation<PickedImageResult?>? = null
    private var pendingMultiContinuation: Continuation<List<PickedImageResult>>? = null
    private var pendingCameraContinuation: Continuation<PickedImageResult?>? = null

    private var currentSingleOptions: ImagePickOptionsDto? = null
    private var currentMultiOptions: MultiImagePickOptionsDto? = null
    private var currentCameraOptions: CameraPickOptionsDto? = null
    private var pendingCameraFile: File? = null

    // Set of file paths currently being processed so clearCache() won't delete active files
    private val activeProcessingFiles = mutableSetOf<String>()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        PickPhotoHostApi.setUp(flutterPluginBinding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        PickPhotoHostApi.setUp(binding.binaryMessenger, null)
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        activity = null

        // If activity detaches with pending operations, fail safely
        if (isBusy.getAndSet(false)) {
            pendingSingleContinuation?.resumeWithException(
                FlutterError("platform_unavailable", "Activity was detached before operation completed", null)
            )
            pendingSingleContinuation = null

            pendingMultiContinuation?.resumeWithException(
                FlutterError("platform_unavailable", "Activity was detached before operation completed", null)
            )
            pendingMultiContinuation = null

            pendingCameraContinuation?.resumeWithException(
                FlutterError("platform_unavailable", "Activity was detached before operation completed", null)
            )
            pendingCameraContinuation = null

            pendingCameraFile?.let {
                if (it.exists()) it.delete()
            }
            pendingCameraFile = null
        }
    }

    // --- HostApi Implementations ---

    override suspend fun pickImage(options: ImagePickOptionsDto): PickedImageResult? {
        val currentActivity = activity ?: throw FlutterError(
            "platform_unavailable",
            "PickPhoto is not attached to an Activity",
            null
        )

        if (!isBusy.compareAndSet(false, true)) {
            throw FlutterError("picker_busy", "A picker operation is already in progress", null)
        }

        currentSingleOptions = options

        return try {
            val intent = createSinglePickerIntent()
            suspendCoroutine { cont ->
                pendingSingleContinuation = cont
                try {
                    currentActivity.startActivityForResult(intent, REQUEST_CODE_SINGLE_GALLERY)
                } catch (e: Exception) {
                    pendingSingleContinuation = null
                    isBusy.set(false)
                    cont.resumeWithException(
                        FlutterError("native_picker_failed", "Failed to launch native picker: ${e.message}", null)
                    )
                }
            }
        } finally {
            isBusy.set(false)
            currentSingleOptions = null
        }
    }

    override suspend fun pickMultipleImages(options: MultiImagePickOptionsDto): List<PickedImageResult> {
        val currentActivity = activity ?: throw FlutterError(
            "platform_unavailable",
            "PickPhoto is not attached to an Activity",
            null
        )

        if (!isBusy.compareAndSet(false, true)) {
            throw FlutterError("picker_busy", "A picker operation is already in progress", null)
        }

        currentMultiOptions = options

        return try {
            val maxCount = options.maxCount?.toInt() ?: Int.MAX_VALUE
            val intent = createMultiplePickerIntent(maxCount)
            suspendCoroutine { cont ->
                pendingMultiContinuation = cont
                try {
                    currentActivity.startActivityForResult(intent, REQUEST_CODE_MULTI_GALLERY)
                } catch (e: Exception) {
                    pendingMultiContinuation = null
                    isBusy.set(false)
                    cont.resumeWithException(
                        FlutterError("native_picker_failed", "Failed to launch native picker: ${e.message}", null)
                    )
                }
            }
        } finally {
            isBusy.set(false)
            currentMultiOptions = null
        }
    }

    override suspend fun captureImage(options: CameraPickOptionsDto): PickedImageResult? {
        val currentActivity = activity ?: throw FlutterError(
            "platform_unavailable",
            "PickPhoto is not attached to an Activity",
            null
        )
        val ctx = context ?: throw FlutterError(
            "platform_unavailable",
            "Application context is null",
            null
        )

        if (!isCameraAvailable(currentActivity)) {
            throw FlutterError("camera_unavailable", "Device does not have an available camera", null)
        }

        if (!isBusy.compareAndSet(false, true)) {
            throw FlutterError("picker_busy", "A picker operation is already in progress", null)
        }

        currentCameraOptions = options

        val cameraDir = File(ctx.cacheDir, CAMERA_CACHE_DIR_NAME).apply { mkdirs() }
        val tempFile = File(cameraDir, "camera_${UUID.randomUUID()}.jpg")
        pendingCameraFile = tempFile

        val authority = "${ctx.packageName}.pick_photo.fileprovider"
        val photoUri: Uri = try {
            FileProvider.getUriForFile(ctx, authority, tempFile)
        } catch (e: Exception) {
            isBusy.set(false)
            tempFile.delete()
            pendingCameraFile = null
            throw FlutterError("file_copy_failed", "Failed to create FileProvider URI: ${e.message}", null)
        }

        val cameraIntent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
            putExtra(MediaStore.EXTRA_OUTPUT, photoUri)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        return try {
            suspendCoroutine { cont ->
                pendingCameraContinuation = cont
                try {
                    currentActivity.startActivityForResult(cameraIntent, REQUEST_CODE_CAMERA)
                } catch (e: Exception) {
                    pendingCameraContinuation = null
                    tempFile.delete()
                    pendingCameraFile = null
                    isBusy.set(false)
                    cont.resumeWithException(
                        FlutterError("native_picker_failed", "Failed to launch camera: ${e.message}", null)
                    )
                }
            }
        } finally {
            isBusy.set(false)
            currentCameraOptions = null
            pendingCameraFile = null
        }
    }

    override suspend fun clearCache() {
        val ctx = context ?: return
        withContext(Dispatchers.IO) {
            val cacheDirs = listOf(
                File(ctx.cacheDir, CACHE_DIR_NAME),
                File(ctx.cacheDir, CAMERA_CACHE_DIR_NAME)
            )
            for (dir in cacheDirs) {
                if (dir.exists() && dir.isDirectory) {
                    dir.listFiles()?.forEach { file ->
                        synchronized(activeProcessingFiles) {
                            if (!activeProcessingFiles.contains(file.absolutePath)) {
                                file.delete()
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Activity Result Listener ---

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        when (requestCode) {
            REQUEST_CODE_SINGLE_GALLERY -> {
                val cont = pendingSingleContinuation ?: return false
                pendingSingleContinuation = null
                val options = currentSingleOptions

                if (resultCode != Activity.RESULT_OK || data == null) {
                    cont.resume(null)
                    return true
                }

                val uri = data.data
                if (uri == null) {
                    cont.resume(null)
                    return true
                }

                kotlinx.coroutines.CoroutineScope(Dispatchers.IO).launch {
                    try {
                        val result = processUri(
                            uri = uri,
                            maxWidth = options?.maxWidth?.toInt(),
                            maxHeight = options?.maxHeight?.toInt(),
                            maxSizeBytes = options?.maxSizeBytes,
                            quality = options?.quality?.toInt(),
                            preserveOriginal = options?.preserveOriginal ?: true
                        )
                        cont.resume(result)
                    } catch (e: Throwable) {
                        cont.resumeWithException(e)
                    }
                }
                return true
            }

            REQUEST_CODE_MULTI_GALLERY -> {
                val cont = pendingMultiContinuation ?: return false
                pendingMultiContinuation = null
                val options = currentMultiOptions

                if (resultCode != Activity.RESULT_OK || data == null) {
                    cont.resume(emptyList())
                    return true
                }

                val uris = extractUrisFromIntent(data)
                if (uris.isEmpty()) {
                    cont.resume(emptyList())
                    return true
                }

                val maxCount = options?.maxCount?.toInt() ?: Int.MAX_VALUE
                val limitedUris = if (uris.size > maxCount) uris.take(maxCount) else uris

                kotlinx.coroutines.CoroutineScope(Dispatchers.IO).launch {
                    try {
                        val results = mutableListOf<PickedImageResult>()
                        for (uri in limitedUris) {
                            val picked = processUri(
                                uri = uri,
                                maxWidth = options?.maxWidth?.toInt(),
                                maxHeight = options?.maxHeight?.toInt(),
                                maxSizeBytes = options?.maxSizeBytes,
                                quality = options?.quality?.toInt(),
                                preserveOriginal = options?.preserveOriginal ?: true
                            )
                            results.add(picked)
                        }
                        cont.resume(results)
                    } catch (e: Throwable) {
                        cont.resumeWithException(e)
                    }
                }
                return true
            }

            REQUEST_CODE_CAMERA -> {
                val cont = pendingCameraContinuation ?: return false
                pendingCameraContinuation = null
                val tempFile = pendingCameraFile
                val options = currentCameraOptions

                if (resultCode != Activity.RESULT_OK || tempFile == null || !tempFile.exists() || tempFile.length() == 0L) {
                    tempFile?.delete()
                    cont.resume(null)
                    return true
                }

                kotlinx.coroutines.CoroutineScope(Dispatchers.IO).launch {
                    try {
                        val result = processCameraFile(
                            file = tempFile,
                            maxWidth = options?.maxWidth?.toInt(),
                            maxHeight = options?.maxHeight?.toInt(),
                            maxSizeBytes = options?.maxSizeBytes,
                            quality = options?.quality?.toInt(),
                            preserveOriginal = options?.preserveOriginal ?: true
                        )
                        cont.resume(result)
                    } catch (e: Throwable) {
                        tempFile.delete()
                        cont.resumeWithException(e)
                    }
                }
                return true
            }
        }
        return false
    }

    // --- Helper Methods ---

    private fun isPhotoPickerAvailable(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            true
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+ with modular system extensions
            SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2
        } else {
            false
        }
    }

    private fun createSinglePickerIntent(): Intent {
        return if (isPhotoPickerAvailable()) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
            }
        } else {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
            }
        }
    }

    private fun createMultiplePickerIntent(maxCount: Int): Intent {
        return if (isPhotoPickerAvailable()) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
                if (maxCount != Int.MAX_VALUE && maxCount > 0) {
                    putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, maxCount)
                }
            }
        } else {
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "image/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            }
        }
    }

    private fun extractUrisFromIntent(data: Intent): List<Uri> {
        val uris = mutableListOf<Uri>()
        val clipData: ClipData? = data.clipData
        if (clipData != null) {
            for (i in 0 until clipData.itemCount) {
                clipData.getItemAt(i).uri?.let { uris.add(it) }
            }
        } else {
            data.data?.let { uris.add(it) }
        }
        return uris
    }

    private fun isCameraAvailable(act: Activity): Boolean {
        val pm = act.packageManager
        if (!pm.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)) {
            return false
        }
        val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE)
        return intent.resolveActivity(pm) != null
    }

    private fun processUri(
        uri: Uri,
        maxWidth: Int?,
        maxHeight: Int?,
        maxSizeBytes: Long?,
        quality: Int?,
        preserveOriginal: Boolean
    ): PickedImageResult {
        val ctx = context ?: throw FlutterError("platform_unavailable", "Context is null", null)
        val resolver = ctx.contentResolver

        val mimeType = resolver.getType(uri) ?: "image/jpeg"
        val displayName = getDisplayName(uri) ?: "image_${UUID.randomUUID()}"
        val extension = getExtension(displayName, mimeType)

        val targetDir = File(ctx.cacheDir, CACHE_DIR_NAME).apply { mkdirs() }
        val targetFile = File(targetDir, "pick_photo_${UUID.randomUUID()}.$extension")

        synchronized(activeProcessingFiles) {
            activeProcessingFiles.add(targetFile.absolutePath)
        }

        try {
            // Check if fast copy (preserve original and no resizing/quality requested)
            val shouldResizeOrCompress = (maxWidth != null || maxHeight != null || quality != null) && !preserveOriginal

            // If animated GIF and resize/quality was requested, throw unsupported_format
            if (mimeType == "image/gif" && shouldResizeOrCompress) {
                throw FlutterError(
                    "unsupported_format",
                    "Resizing or recompressing animated GIF is not supported without loss of animation",
                    null
                )
            }

            if (!shouldResizeOrCompress) {
                // Stream copy directly without loading into bitmap memory
                copyUriToFile(uri, targetFile, maxSizeBytes)

                val (width, height) = readImageDimensions(targetFile)
                val fileSize = targetFile.length()

                return PickedImageResult(
                    path = targetFile.absolutePath,
                    name = targetFile.name,
                    mimeType = mimeType,
                    sizeBytes = fileSize,
                    width = width?.toLong(),
                    height = height?.toLong()
                )
            } else {
                // Resize or compress requested
                val result = resizeAndCompress(
                    inputStreamProvider = { resolver.openInputStream(uri) },
                    targetFile = targetFile,
                    maxWidth = maxWidth,
                    maxHeight = maxHeight,
                    quality = quality ?: 90,
                    originalMimeType = mimeType,
                    maxSizeBytes = maxSizeBytes
                )
                return result
            }
        } finally {
            synchronized(activeProcessingFiles) {
                activeProcessingFiles.remove(targetFile.absolutePath)
            }
        }
    }

    private fun processCameraFile(
        file: File,
        maxWidth: Int?,
        maxHeight: Int?,
        maxSizeBytes: Long?,
        quality: Int?,
        preserveOriginal: Boolean
    ): PickedImageResult {
        val ctx = context ?: throw FlutterError("platform_unavailable", "Context is null", null)

        val targetDir = File(ctx.cacheDir, CACHE_DIR_NAME).apply { mkdirs() }
        val targetFile = File(targetDir, "pick_photo_${UUID.randomUUID()}.jpg")

        synchronized(activeProcessingFiles) {
            activeProcessingFiles.add(targetFile.absolutePath)
        }

        try {
            val shouldResizeOrCompress = (maxWidth != null || maxHeight != null || quality != null) && !preserveOriginal

            if (!shouldResizeOrCompress) {
                // Move or copy camera temp file to cache file
                if (!file.renameTo(targetFile)) {
                    file.inputStream().use { input ->
                        targetFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }
                    file.delete()
                }

                if (maxSizeBytes != null && targetFile.length() > maxSizeBytes) {
                    targetFile.delete()
                    throw FlutterError(
                        "maximum_size_exceeded",
                        "File size ${targetFile.length()} bytes exceeds maximum allowed $maxSizeBytes bytes",
                        null
                    )
                }

                val (width, height) = readImageDimensions(targetFile)
                return PickedImageResult(
                    path = targetFile.absolutePath,
                    name = targetFile.name,
                    mimeType = "image/jpeg",
                    sizeBytes = targetFile.length(),
                    width = width?.toLong(),
                    height = height?.toLong()
                )
            } else {
                val result = resizeAndCompress(
                    inputStreamProvider = { file.inputStream() },
                    targetFile = targetFile,
                    maxWidth = maxWidth,
                    maxHeight = maxHeight,
                    quality = quality ?: 90,
                    originalMimeType = "image/jpeg",
                    maxSizeBytes = maxSizeBytes
                )
                file.delete()
                return result
            }
        } finally {
            synchronized(activeProcessingFiles) {
                activeProcessingFiles.remove(targetFile.absolutePath)
            }
        }
    }

    private fun copyUriToFile(uri: Uri, destFile: File, maxSizeBytes: Long?) {
        val resolver = context?.contentResolver ?: throw FlutterError("platform_unavailable", "Context is null", null)
        val inputStream: InputStream = resolver.openInputStream(uri)
            ?: throw FlutterError("file_not_found", "Failed to open input stream for URI: $uri", null)

        try {
            FileOutputStream(destFile).use { outputStream ->
                val buffer = ByteArray(8192)
                var bytesRead: Int
                var totalBytes: Long = 0

                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                    totalBytes += bytesRead
                    if (maxSizeBytes != null && totalBytes > maxSizeBytes) {
                        destFile.delete()
                        throw FlutterError(
                            "maximum_size_exceeded",
                            "File size exceeds maximum allowed size of $maxSizeBytes bytes",
                            null
                        )
                    }
                    outputStream.write(buffer, 0, bytesRead)
                }
                outputStream.flush()
            }
        } catch (e: FlutterError) {
            destFile.delete()
            throw e
        } catch (e: Exception) {
            destFile.delete()
            throw FlutterError("file_copy_failed", "Failed to copy file from URI: ${e.message}", null)
        } finally {
            try {
                inputStream.close()
            } catch (_: Exception) {}
        }
    }

    private fun readImageDimensions(file: File): Pair<Int?, Int?> {
        return try {
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeFile(file.absolutePath, options)
            var w = options.outWidth
            var h = options.outHeight

            if (w <= 0 || h <= 0) {
                return Pair(null, null)
            }

            // Check EXIF orientation
            val exif = ExifInterface(file.absolutePath)
            val orientation = exif.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            )
            if (orientation == ExifInterface.ORIENTATION_ROTATE_90 ||
                orientation == ExifInterface.ORIENTATION_ROTATE_270
            ) {
                val temp = w
                w = h
                h = temp
            }

            Pair(w, h)
        } catch (_: Exception) {
            Pair(null, null)
        }
    }

    private fun resizeAndCompress(
        inputStreamProvider: () -> InputStream?,
        targetFile: File,
        maxWidth: Int?,
        maxHeight: Int?,
        quality: Int,
        originalMimeType: String,
        maxSizeBytes: Long?
    ): PickedImageResult {
        // First read dimensions
        val boundsOptions = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }

        inputStreamProvider()?.use { stream ->
            BitmapFactory.decodeStream(stream, null, boundsOptions)
        } ?: throw FlutterError("file_not_found", "Failed to open input stream to read image bounds", null)

        val origWidth = boundsOptions.outWidth
        val origHeight = boundsOptions.outHeight
        if (origWidth <= 0 || origHeight <= 0) {
            throw FlutterError("image_processing_failed", "Unable to decode image dimensions", null)
        }

        // Determine orientation
        val orientation = try {
            inputStreamProvider()?.use { stream ->
                val exif = ExifInterface(stream)
                exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            } ?: ExifInterface.ORIENTATION_NORMAL
        } catch (_: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }

        val isSwapped = orientation == ExifInterface.ORIENTATION_ROTATE_90 ||
                orientation == ExifInterface.ORIENTATION_ROTATE_270
        val effectiveWidth = if (isSwapped) origHeight else origWidth
        val effectiveHeight = if (isSwapped) origWidth else origHeight

        // Compute aspect ratio scaling
        val maxW = maxWidth ?: effectiveWidth
        val maxH = maxHeight ?: effectiveHeight

        val scale = minOf(
            maxW.toFloat() / effectiveWidth.toFloat(),
            maxH.toFloat() / effectiveHeight.toFloat(),
            1.0f
        )

        val targetWidth = (effectiveWidth * scale).roundToInt().coerceAtLeast(1)
        val targetHeight = (effectiveHeight * scale).roundToInt().coerceAtLeast(1)

        // Calculate sample size for memory-bounded decoding
        val sampleSize = calculateInSampleSize(
            origWidth,
            origHeight,
            if (isSwapped) targetHeight else targetWidth,
            if (isSwapped) targetWidth else targetHeight
        )

        val decodeOptions = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }

        val sampledBitmap = inputStreamProvider()?.use { stream ->
            BitmapFactory.decodeStream(stream, null, decodeOptions)
        } ?: throw FlutterError("image_processing_failed", "Failed to decode bitmap", null)

        // Handle rotation matrix
        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
        }

        val orientedBitmap = if (!matrix.isIdentity) {
            val rotated = Bitmap.createBitmap(
                sampledBitmap,
                0,
                0,
                sampledBitmap.width,
                sampledBitmap.height,
                matrix,
                true
            )
            if (rotated != sampledBitmap) {
                sampledBitmap.recycle()
            }
            rotated
        } else {
            sampledBitmap
        }

        // Final scale to exact target dimensions
        val finalBitmap = if (orientedBitmap.width != targetWidth || orientedBitmap.height != targetHeight) {
            val scaled = Bitmap.createScaledBitmap(orientedBitmap, targetWidth, targetHeight, true)
            if (scaled != orientedBitmap) {
                orientedBitmap.recycle()
            }
            scaled
        } else {
            orientedBitmap
        }

        // Compression format
        val compressFormat: Bitmap.CompressFormat
        val outMimeType: String
        when (originalMimeType) {
            "image/png" -> {
                compressFormat = Bitmap.CompressFormat.PNG
                outMimeType = "image/png"
            }
            "image/webp" -> {
                compressFormat = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    Bitmap.CompressFormat.WEBP_LOSSY
                } else {
                    @Suppress("DEPRECATION")
                    Bitmap.CompressFormat.WEBP
                }
                outMimeType = "image/webp"
            }
            else -> {
                compressFormat = Bitmap.CompressFormat.JPEG
                outMimeType = "image/jpeg"
            }
        }

        val validQuality = quality.coerceIn(1, 100)

        try {
            FileOutputStream(targetFile).use { outStream ->
                val success = finalBitmap.compress(compressFormat, validQuality, outStream)
                outStream.flush()
                if (!success) {
                    targetFile.delete()
                    throw FlutterError("image_processing_failed", "Failed to compress bitmap", null)
                }
            }
        } finally {
            finalBitmap.recycle()
        }

        val finalSize = targetFile.length()
        if (maxSizeBytes != null && finalSize > maxSizeBytes) {
            targetFile.delete()
            throw FlutterError(
                "maximum_size_exceeded",
                "Processed image size $finalSize bytes exceeds maximum allowed $maxSizeBytes bytes",
                null
            )
        }

        return PickedImageResult(
            path = targetFile.absolutePath,
            name = targetFile.name,
            mimeType = outMimeType,
            sizeBytes = finalSize,
            width = targetWidth.toLong(),
            height = targetHeight.toLong()
        )
    }

    private fun calculateInSampleSize(width: Int, height: Int, reqWidth: Int, reqHeight: Int): Int {
        var inSampleSize = 1
        if (height > reqHeight || width > reqWidth) {
            val halfHeight = height / 2
            val halfWidth = width / 2
            while ((halfHeight / inSampleSize) >= reqHeight && (halfWidth / inSampleSize) >= reqWidth) {
                inSampleSize *= 2
            }
        }
        return inSampleSize
    }

    private fun getDisplayName(uri: Uri): String? {
        val resolver = context?.contentResolver ?: return null
        return try {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index != -1 && cursor.moveToFirst()) {
                    cursor.getString(index)
                } else {
                    null
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun getExtension(displayName: String, mimeType: String): String {
        val dotIndex = displayName.lastIndexOf('.')
        if (dotIndex != -1 && dotIndex < displayName.length - 1) {
            val ext = displayName.substring(dotIndex + 1).lowercase()
            if (ext.length in 2..5) {
                return ext
            }
        }
        val fromMime = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
        return fromMime ?: "jpg"
    }
}
