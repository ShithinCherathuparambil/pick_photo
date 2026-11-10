import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pick_photo/pick_photo.dart';

void main() {
  runApp(const PickPhotoExampleApp());
}

class PickPhotoExampleApp extends StatelessWidget {
  const PickPhotoExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PickPhoto Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          brightness: Brightness.dark,
        ),
      ),
      home: const PickPhotoHomePage(),
    );
  }
}

class PickPhotoHomePage extends StatefulWidget {
  const PickPhotoHomePage({super.key});

  @override
  State<PickPhotoHomePage> createState() => _PickPhotoHomePageState();
}

class _PickPhotoHomePageState extends State<PickPhotoHomePage> {
  final List<PickedImage> _images = [];
  bool _isLoading = false;
  String? _statusMessage;
  String? _errorMessage;

  // Configuration options
  bool _preserveOriginal = true;
  double _quality = 85;
  double _maxWidth = 1024;
  double _maxHeight = 1024;
  bool _applyDimensionConstraints = false;
  int? _maxSizeBytes;
  int _multiPickLimit = 5;

  ImagePickOptions _buildOptions() {
    return ImagePickOptions(
      preserveOriginal: _preserveOriginal,
      maxWidth: _applyDimensionConstraints ? _maxWidth.round() : null,
      maxHeight: _applyDimensionConstraints ? _maxHeight.round() : null,
      quality: !_preserveOriginal ? _quality.round() : null,
      maxSizeBytes: _maxSizeBytes,
    );
  }

  Future<void> _pickSingleImage() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = null;
    });

    try {
      final image = await PickPhoto.fromGallery(options: _buildOptions());
      if (!mounted) return;

      if (image == null) {
        setState(() {
          _statusMessage = 'Single pick cancelled by user.';
        });
      } else {
        setState(() {
          _images.insert(0, image);
          _statusMessage = 'Picked: ${image.name}';
        });
      }
    } on PickPhotoException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '[${e.code}] ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unexpected error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickMultipleImages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = null;
    });

    try {
      final images = await PickPhoto.multiple(
        maxCount: _multiPickLimit > 0 ? _multiPickLimit : null,
        options: _buildOptions(),
      );
      if (!mounted) return;

      if (images.isEmpty) {
        setState(() {
          _statusMessage = 'Multiple pick cancelled or no items selected.';
        });
      } else {
        setState(() {
          _images.insertAll(0, images);
          _statusMessage = 'Selected ${images.length} photos.';
        });
      }
    } on PickPhotoException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '[${e.code}] ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unexpected error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _captureFromCamera() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = null;
    });

    try {
      final image = await PickPhoto.fromCamera(options: _buildOptions());
      if (!mounted) return;

      if (image == null) {
        setState(() {
          _statusMessage = 'Camera capture cancelled.';
        });
      } else {
        setState(() {
          _images.insert(0, image);
          _statusMessage = 'Captured: ${image.name}';
        });
      }
    } on PickPhotoException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '[${e.code}] ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unexpected error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _clearCache() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await PickPhoto.clearCache();
      if (!mounted) return;
      setState(() {
        _images.clear();
        _statusMessage = 'Cache cleared successfully.';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Temporary cache cleared.')));
    } on PickPhotoException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '[${e.code}] ${e.message}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveImage(PickedImage image) async {
    try {
      final tempDir = Directory.systemTemp;
      final savedPath =
          '${tempDir.path}/saved_${DateTime.now().millisecondsSinceEpoch}_${image.name}';
      final savedFile = await image.saveTo(savedPath);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to: ${savedFile.path}'),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _testReadBytes(PickedImage image) async {
    try {
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Read ${bytes.lengthInBytes} bytes from file successfully.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to read bytes: $e')));
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PickPhoto Plugin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear Cache',
            onPressed: _isLoading ? null : _clearCache,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildConfigurationCard(theme),
          const SizedBox(height: 16),
          _buildActionButtons(theme),
          const SizedBox(height: 16),
          if (_statusMessage != null) _buildStatusBanner(theme),
          if (_errorMessage != null) _buildErrorBanner(theme),
          const SizedBox(height: 16),
          _buildResultsHeader(theme),
          const SizedBox(height: 8),
          _buildImageList(theme),
        ],
      ),
    );
  }

  Widget _buildConfigurationCard(ThemeData theme) {
    return Card(
      elevation: 1,
      child: ExpansionTile(
        initiallyExpanded: false,
        title: const Text(
          'Picker Options & Processing',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          _preserveOriginal
              ? 'Preserve original (no compression)'
              : 'Custom resize / quality applied',
          style: theme.textTheme.bodySmall,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Preserve Original Format'),
                  subtitle: const Text(
                    'Keep original HEIC, GIF, PNG & EXIF metadata without re-encoding.',
                  ),
                  value: _preserveOriginal,
                  onChanged: (val) => setState(() => _preserveOriginal = val),
                ),
                if (!_preserveOriginal) ...[
                  const Divider(),
                  Text(
                    'Quality: ${_quality.round()}%',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Slider(
                    value: _quality,
                    min: 1,
                    max: 100,
                    divisions: 99,
                    label: '${_quality.round()}%',
                    onChanged: (v) => setState(() => _quality = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Constrain Max Dimensions'),
                    subtitle: const Text(
                      'Resize while preserving aspect ratio',
                    ),
                    value: _applyDimensionConstraints,
                    onChanged: (v) =>
                        setState(() => _applyDimensionConstraints = v),
                  ),
                  if (_applyDimensionConstraints) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Max Width: ${_maxWidth.round()} px'),
                              Slider(
                                value: _maxWidth,
                                min: 200,
                                max: 4000,
                                divisions: 38,
                                onChanged: (v) => setState(() => _maxWidth = v),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Max Height: ${_maxHeight.round()} px'),
                              Slider(
                                value: _maxHeight,
                                min: 200,
                                max: 4000,
                                divisions: 38,
                                onChanged: (v) =>
                                    setState(() => _maxHeight = v),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
                const Divider(),
                Row(
                  children: [
                    const Text('Multi-pick limit: '),
                    DropdownButton<int>(
                      value: _multiPickLimit,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('1')),
                        DropdownMenuItem(value: 3, child: Text('3')),
                        DropdownMenuItem(value: 5, child: Text('5')),
                        DropdownMenuItem(value: 10, child: Text('10')),
                        DropdownMenuItem(value: 0, child: Text('Unlimited')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _multiPickLimit = v);
                      },
                    ),
                    const Spacer(),
                    const Text('Max Size: '),
                    DropdownButton<int?>(
                      value: _maxSizeBytes,
                      items: const [
                        DropdownMenuItem(value: null, child: Text('None')),
                        DropdownMenuItem(
                          value: 1024 * 1024,
                          child: Text('1 MB'),
                        ),
                        DropdownMenuItem(
                          value: 5 * 1024 * 1024,
                          child: Text('5 MB'),
                        ),
                        DropdownMenuItem(
                          value: 10 * 1024 * 1024,
                          child: Text('10 MB'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _maxSizeBytes = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme) {
    return Column(
      children: [
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.photo_outlined),
                label: const Text('Gallery'),
                onPressed: _isLoading ? null : _pickSingleImage,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Multi-Pick'),
                onPressed: _isLoading ? null : _pickMultipleImages,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Camera'),
                onPressed: _isLoading ? null : _captureFromCamera,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusBanner(ThemeData theme) {
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_statusMessage!, style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme) {
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              size: 20,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _errorMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsHeader(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Picked Images (${_images.length})',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        if (_images.isNotEmpty)
          TextButton(
            onPressed: () => setState(() => _images.clear()),
            child: const Text('Clear List'),
          ),
      ],
    );
  }

  Widget _buildImageList(ThemeData theme) {
    if (_images.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(
            children: [
              Icon(
                Icons.image_search,
                size: 64,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'No images picked yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Tap Gallery, Multi-Pick, or Camera above to pick photos.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _images.map((image) => _buildImageCard(image, theme)).toList(),
    );
  }

  Widget _buildImageCard(PickedImage image, ThemeData theme) {
    final dimensions = (image.width != null && image.height != null)
        ? '${image.width} × ${image.height} px'
        : 'Unknown dims';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 220,
            width: double.infinity,
            color: Colors.black12,
            child: Image.file(
              image.file,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.broken_image,
                        size: 48,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Preview unavailable: $error',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      image.source == ImageSource.camera
                          ? Icons.camera_alt
                          : Icons.photo_library,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        image.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Chip(
                      label: Text(
                        image.extension.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _buildMetaChip(Icons.aspect_ratio, dimensions),
                    _buildMetaChip(
                      Icons.data_usage,
                      _formatBytes(image.sizeBytes),
                    ),
                    _buildMetaChip(Icons.category, image.mimeType),
                    _buildMetaChip(Icons.source, image.source.name),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  image.path,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: theme.colorScheme.outline,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.storage, size: 16),
                      label: const Text('Read Bytes'),
                      onPressed: () => _testReadBytes(image),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.save_alt, size: 16),
                      label: const Text('Save to Temp'),
                      onPressed: () => _saveImage(image),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
