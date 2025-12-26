import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../services/user_settings.dart';

/// Export progress info from the engine
class ExportProgressInfo {
  final int progress;
  final bool isRunning;
  final bool isCancelled;
  final String status;
  final String? error;

  ExportProgressInfo({
    required this.progress,
    required this.isRunning,
    required this.isCancelled,
    required this.status,
    this.error,
  });

  factory ExportProgressInfo.fromJson(Map<String, dynamic> json) {
    return ExportProgressInfo(
      progress: json['progress'] as int? ?? 0,
      isRunning: json['is_running'] as bool? ?? false,
      isCancelled: json['is_cancelled'] as bool? ?? false,
      status: json['status'] as String? ?? '',
      error: json['error'] as String?,
    );
  }
}

/// Progress dialog shown during export
class ExportProgressDialog extends StatefulWidget {
  final AudioEngine audioEngine;
  final Future<void> Function() exportTask;
  final VoidCallback onCancel;

  const ExportProgressDialog({
    super.key,
    required this.audioEngine,
    required this.exportTask,
    required this.onCancel,
  });

  @override
  State<ExportProgressDialog> createState() => _ExportProgressDialogState();
}

class _ExportProgressDialogState extends State<ExportProgressDialog> {
  Timer? _progressTimer;
  ExportProgressInfo? _progressInfo;
  bool _exportComplete = false;
  String? _exportError;

  @override
  void initState() {
    super.initState();
    _startExport();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  void _startExport() {
    // Reset progress state before starting
    widget.audioEngine.resetExportProgress();

    // Start polling progress
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _pollProgress();
    });

    // Run the export task
    widget.exportTask().then((_) {
      if (mounted) {
        setState(() => _exportComplete = true);
        _progressTimer?.cancel();
      }
    }).catchError((error) {
      if (mounted) {
        setState(() {
          _exportError = error.toString();
          _exportComplete = true;
        });
        _progressTimer?.cancel();
      }
    });
  }

  void _pollProgress() {
    if (!mounted) return;

    try {
      final progressJson = widget.audioEngine.getExportProgress();
      final parsed = jsonDecode(progressJson);
      final info = ExportProgressInfo.fromJson(parsed);

      setState(() {
        _progressInfo = info;
        if (info.error != null) {
          _exportError = info.error;
        }
      });

      // Stop polling if export is no longer running
      if (!info.isRunning && _progressInfo != null) {
        _progressTimer?.cancel();
      }
    } catch (e) {
      debugPrint('Failed to poll progress: $e');
    }
  }

  void _handleCancel() {
    widget.audioEngine.cancelExport();
    widget.onCancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progressInfo?.progress ?? 0;
    final status = _progressInfo?.status ?? 'Preparing export...';

    return AlertDialog(
      backgroundColor: const Color(0xFF2A2A2A),
      title: Row(
        children: [
          if (_exportError != null)
            const Icon(Icons.error_outline, color: Colors.red, size: 24)
          else if (_exportComplete)
            const Icon(Icons.check_circle, color: Colors.green, size: 24)
          else
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: 12),
          Text(
            _exportError != null
                ? 'Export Failed'
                : _exportComplete
                    ? 'Export Complete'
                    : 'Exporting...',
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_exportError != null) ...[
              Text(
                _exportError!,
                style: const TextStyle(color: Colors.red),
              ),
            ] else ...[
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress / 100.0,
                  backgroundColor: const Color(0xFF404040),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _exportComplete ? Colors.green : Colors.blue,
                  ),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 12),
              // Status text
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      status,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$progress%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_exportComplete && _exportError == null)
          TextButton(
            onPressed: _handleCancel,
            child: const Text('Cancel'),
          ),
        if (_exportComplete || _exportError != null)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
      ],
    );
  }
}

/// Track info for stem export
class StemTrackInfo {
  final int id;
  final String name;
  final String type;
  bool selected;

  StemTrackInfo({
    required this.id,
    required this.name,
    required this.type,
    this.selected = true,
  });

  factory StemTrackInfo.fromJson(Map<String, dynamic> json) {
    return StemTrackInfo(
      id: json['id'] as int,
      name: json['name'] as String,
      type: json['type'] as String,
    );
  }
}

/// Export options model for the dialog
class ExportOptions {
  // Format
  bool exportMp3;
  bool exportWav;

  // MP3 settings
  int mp3Bitrate; // 128, 192, 320

  // WAV settings
  int wavBitDepth; // 16, 24, 32

  // Common settings
  int sampleRate; // 44100, 48000
  bool normalize;
  bool dither;
  bool mono;

  // Stem export
  bool exportStems;
  List<StemTrackInfo> stemTracks;

  // Metadata
  String? title;
  String? artist;
  String? album;
  int? year;
  String? genre;

  ExportOptions({
    this.exportMp3 = true,
    this.exportWav = false,
    this.mp3Bitrate = 320,
    this.wavBitDepth = 16,
    this.sampleRate = 44100,
    this.normalize = false,
    this.dither = false,
    this.mono = false,
    this.exportStems = false,
    this.stemTracks = const [],
    this.title,
    this.artist,
    this.album,
    this.year,
    this.genre,
  });

  /// Get metadata as JSON for FFI
  String get metadataJson => jsonEncode({
        if (title != null && title!.isNotEmpty) 'title': title,
        if (artist != null && artist!.isNotEmpty) 'artist': artist,
        if (album != null && album!.isNotEmpty) 'album': album,
        if (year != null) 'year': year,
        if (genre != null && genre!.isNotEmpty) 'genre': genre,
      });
}

/// Export result from FFI
class ExportResult {
  final String path;
  final int fileSize;
  final double duration;
  final int sampleRate;
  final String format;

  ExportResult({
    required this.path,
    required this.fileSize,
    required this.duration,
    required this.sampleRate,
    required this.format,
  });

  factory ExportResult.fromJson(Map<String, dynamic> json) {
    return ExportResult(
      path: json['path'] as String,
      fileSize: json['file_size'] as int,
      duration: (json['duration'] as num).toDouble(),
      sampleRate: json['sample_rate'] as int,
      format: json['format'] as String,
    );
  }

  String get fileSizeFormatted {
    if (fileSize >= 1024 * 1024) {
      return '${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB';
    } else if (fileSize >= 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    return '$fileSize bytes';
  }

  String get durationFormatted {
    final minutes = (duration / 60).floor();
    final seconds = (duration % 60).floor();
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Export dialog for audio export with format/quality options
class ExportDialog extends StatefulWidget {
  final AudioEngine audioEngine;
  final String defaultName;

  const ExportDialog({
    super.key,
    required this.audioEngine,
    required this.defaultName,
  });

  static Future<void> show(
    BuildContext context, {
    required AudioEngine audioEngine,
    required String defaultName,
  }) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (context) => ExportDialog(
        audioEngine: audioEngine,
        defaultName: defaultName,
      ),
    );
  }

  @override
  State<ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<ExportDialog> {
  final _options = ExportOptions();
  bool _showMetadata = false;
  bool _showAdvanced = false;
  bool _showStems = false;
  bool _isExporting = false;
  bool _ffmpegAvailable = false;
  bool _loadingTracks = false;

  // Text controllers for metadata
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();
  final _albumController = TextEditingController();
  final _yearController = TextEditingController();
  final _genreController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleController.text = widget.defaultName;
    _options.title = widget.defaultName;
    _loadSettingsFromUserSettings();
    _checkFfmpeg();
  }

  void _loadSettingsFromUserSettings() {
    final settings = UserSettings();

    // Load format preference
    switch (settings.exportFormat) {
      case 'mp3':
        _options.exportMp3 = true;
        _options.exportWav = false;
        break;
      case 'wav':
        _options.exportMp3 = false;
        _options.exportWav = true;
        break;
      case 'both':
        _options.exportMp3 = true;
        _options.exportWav = true;
        break;
    }

    // Load quality settings
    _options.mp3Bitrate = settings.exportMp3Bitrate;
    _options.wavBitDepth = settings.exportWavBitDepth;
    _options.sampleRate = settings.exportSampleRate;
    _options.normalize = settings.exportNormalize;
    _options.dither = settings.exportDither;

    // Load remembered artist
    if (settings.rememberArtist && settings.exportArtist != null) {
      _options.artist = settings.exportArtist;
      _artistController.text = settings.exportArtist!;
    }
  }

  void _saveSettingsToUserSettings() {
    final settings = UserSettings();

    // Save format preference
    if (_options.exportMp3 && _options.exportWav) {
      settings.exportFormat = 'both';
    } else if (_options.exportWav) {
      settings.exportFormat = 'wav';
    } else {
      settings.exportFormat = 'mp3';
    }

    // Save quality settings
    settings.exportMp3Bitrate = _options.mp3Bitrate;
    settings.exportWavBitDepth = _options.wavBitDepth;
    settings.exportSampleRate = _options.sampleRate;
    settings.exportNormalize = _options.normalize;
    settings.exportDither = _options.dither;

    // Save artist if remember is enabled
    if (settings.rememberArtist) {
      settings.exportArtist = _options.artist;
    }
  }

  void _checkFfmpeg() {
    _ffmpegAvailable = widget.audioEngine.isFfmpegAvailable();
    if (!_ffmpegAvailable && _options.exportMp3) {
      // Fall back to WAV if ffmpeg not available
      setState(() {
        _options.exportMp3 = false;
        _options.exportWav = true;
      });
    }
  }

  Future<void> _loadTracksForStems() async {
    if (_options.stemTracks.isNotEmpty) return; // Already loaded

    setState(() => _loadingTracks = true);

    try {
      final tracksJson = widget.audioEngine.getTracksForStems();
      final List<dynamic> tracksList = jsonDecode(tracksJson);

      setState(() {
        _options.stemTracks = tracksList
            .map((t) => StemTrackInfo.fromJson(t as Map<String, dynamic>))
            .toList();
        _loadingTracks = false;
      });
    } catch (e) {
      debugPrint('Failed to load tracks: $e');
      setState(() => _loadingTracks = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _yearController.dispose();
    _genreController.dispose();
    super.dispose();
  }

  // Helper to convert bit depth int to Rust enum string
  String _wavBitDepthString(int bitDepth) {
    switch (bitDepth) {
      case 16:
        return 'Int16';
      case 24:
        return 'Int24';
      case 32:
        return 'Float32';
      default:
        return 'Int16';
    }
  }

  // Helper to convert bitrate int to Rust enum string
  String _mp3BitrateString(int bitrate) {
    switch (bitrate) {
      case 128:
        return 'Kbps128';
      case 192:
        return 'Kbps192';
      case 320:
        return 'Kbps320';
      default:
        return 'Kbps320';
    }
  }

  /// Show progress dialog and perform the actual export
  Future<List<ExportResult>> _performExportWithProgress({
    required String baseName,
    String? folderPath,
    String? filePath,
  }) async {
    final List<ExportResult> results = [];
    final completer = Completer<List<ExportResult>>();

    // Close the export options dialog first
    Navigator.of(context).pop();

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder: (dialogContext) => ExportProgressDialog(
        audioEngine: widget.audioEngine,
        exportTask: () async {
          try {
            // Stem export
            if (_options.exportStems && folderPath != null) {
              final selectedTrackIds = _options.stemTracks
                  .where((t) => t.selected)
                  .map((t) => t.id)
                  .toList();

              final stemOptionsJson = jsonEncode({
                'format': _options.exportWav
                    ? {'Wav': {'bit_depth': _wavBitDepthString(_options.wavBitDepth)}}
                    : {'Mp3': {'bitrate': _mp3BitrateString(_options.mp3Bitrate)}},
                'sample_rate': _options.sampleRate,
                'normalize': _options.normalize,
                'dither': _options.dither,
                'mono': _options.mono,
              });

              final stemResultJson = widget.audioEngine.exportStems(
                outputDir: folderPath,
                baseName: baseName,
                trackIdsJson: jsonEncode(selectedTrackIds),
                optionsJson: stemOptionsJson,
              );

              final stemResult = jsonDecode(stemResultJson);
              results.add(ExportResult(
                path: folderPath,
                fileSize: stemResult['total_size'] as int,
                duration: 0,
                sampleRate: _options.sampleRate,
                format: '${stemResult['count']} stems (${_options.exportWav ? 'WAV' : 'MP3'})',
              ));
            }

            // Regular file export
            if (filePath != null) {
              // Export MP3
              if (_options.exportMp3) {
                final mp3Path = filePath.endsWith('.mp3')
                    ? filePath
                    : '${filePath.replaceAll(RegExp(r'\.[^.]+$'), '')}.mp3';

                final resultJson = widget.audioEngine.exportMp3WithOptions(
                  outputPath: mp3Path,
                  bitrate: _options.mp3Bitrate,
                  sampleRate: _options.sampleRate,
                  normalize: _options.normalize,
                  mono: _options.mono,
                );

                final parsed = jsonDecode(resultJson);
                results.add(ExportResult.fromJson(parsed));

                // Write metadata if we have any
                if (_options.title != null || _options.artist != null || _options.album != null) {
                  try {
                    widget.audioEngine.writeMp3Metadata(mp3Path, _options.metadataJson);
                  } catch (e) {
                    debugPrint('Warning: Failed to write metadata: $e');
                  }
                }
              }

              // Export WAV
              if (_options.exportWav) {
                final wavPath = filePath.endsWith('.wav')
                    ? filePath
                    : '${filePath.replaceAll(RegExp(r'\.[^.]+$'), '')}.wav';

                final resultJson = widget.audioEngine.exportWavWithOptions(
                  outputPath: wavPath,
                  bitDepth: _options.wavBitDepth,
                  sampleRate: _options.sampleRate,
                  normalize: _options.normalize,
                  dither: _options.dither,
                  mono: _options.mono,
                );

                final parsed = jsonDecode(resultJson);
                results.add(ExportResult.fromJson(parsed));
              }
            }

            completer.complete(results);
          } catch (e) {
            completer.completeError(e);
          }
        },
        onCancel: () {
          if (!completer.isCompleted) {
            completer.completeError('Export cancelled');
          }
        },
      ),
    );

    return completer.future;
  }

  Future<void> _doExport() async {
    if (_isExporting) return;

    // Validate format selection
    final hasFormatSelected = _options.exportMp3 || _options.exportWav;
    final hasStemsSelected = _options.exportStems &&
        _options.stemTracks.any((t) => t.selected);

    if (!hasFormatSelected && !hasStemsSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one format or stems')),
      );
      return;
    }

    if (_options.exportStems && !_options.stemTracks.any((t) => t.selected)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one track for stem export')),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final baseName = _options.title ?? widget.defaultName;
      String? folderPath;
      String? filePath;

      // Handle stem export (choose folder)
      if (_options.exportStems) {
        final folderResult = await Process.run('osascript', [
          '-e',
          'POSIX path of (choose folder with prompt "Choose folder for stem export")'
        ]);

        if (folderResult.exitCode != 0) {
          setState(() => _isExporting = false);
          return; // User cancelled
        }

        folderPath = folderResult.stdout.toString().trim();
        if (folderPath.isEmpty) {
          setState(() => _isExporting = false);
          return;
        }
      }

      // Handle regular export (choose file)
      if (hasFormatSelected && !_options.exportStems) {
        final extension = _options.exportMp3 ? 'mp3' : 'wav';

        final result = await Process.run('osascript', [
          '-e',
          'POSIX path of (choose file name with prompt "Export as" default name "$baseName.$extension")'
        ]);

        if (result.exitCode != 0) {
          setState(() => _isExporting = false);
          return; // User cancelled
        }

        filePath = result.stdout.toString().trim();
        if (filePath.isEmpty) {
          setState(() => _isExporting = false);
          return;
        }

        // Ensure correct extension
        if (_options.exportMp3 && !filePath.endsWith('.mp3')) {
          filePath = '${filePath.replaceAll(RegExp(r'\.[^.]+$'), '')}.mp3';
        } else if (_options.exportWav && !filePath.endsWith('.wav')) {
          filePath = '${filePath.replaceAll(RegExp(r'\.[^.]+$'), '')}.wav';
        }
      }

      // Save settings before showing progress dialog (since we'll close this dialog)
      _saveSettingsToUserSettings();

      // Perform export with progress dialog
      final results = await _performExportWithProgress(
        baseName: baseName,
        folderPath: folderPath,
        filePath: filePath,
      );

      // Show success dialog after progress dialog closes
      if (mounted && results.isNotEmpty) {
        _showSuccessDialog(results);
      }
    } catch (e) {
      if (mounted && e.toString() != 'Export cancelled') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _showSuccessDialog(List<ExportResult> results) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 24),
            SizedBox(width: 8),
            Text('Export Complete', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final result in results) ...[
              Text(
                result.format,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Text(
                'Size: ${result.fileSizeFormatted}  Duration: ${result.durationFormatted}',
                style: const TextStyle(color: Colors.grey),
              ),
              Text(
                result.path,
                style: const TextStyle(color: Colors.grey, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Open folder containing the file
              final folder = File(results.first.path).parent.path;
              Process.run('open', [folder]);
              Navigator.of(context).pop();
            },
            child: const Text('Show in Finder'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 600),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF404040)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _buildHeader(),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFormatSection(),
                    const SizedBox(height: 16),
                    _buildQualitySection(),
                    const SizedBox(height: 16),
                    _buildStemExportSection(),
                    const SizedBox(height: 16),
                    _buildMetadataSection(),
                    const SizedBox(height: 16),
                    _buildAdvancedSection(),
                  ],
                ),
              ),
            ),
            // Footer
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF404040)),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.file_download,
            color: Color(0xFF00BCD4),
            size: 24,
          ),
          const SizedBox(width: 12),
          const Text(
            'Export Audio',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey),
            onPressed: () => Navigator.of(context).pop(),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildFormatSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Format',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        // MP3 checkbox
        _buildCheckboxTile(
          value: _options.exportMp3,
          enabled: _ffmpegAvailable,
          onChanged: (v) => setState(() => _options.exportMp3 = v ?? false),
          title: 'MP3',
          subtitle: _ffmpegAvailable
              ? 'Compressed, smaller file size'
              : 'ffmpeg required (install via: brew install ffmpeg)',
        ),
        const SizedBox(height: 8),
        // WAV checkbox
        _buildCheckboxTile(
          value: _options.exportWav,
          enabled: true,
          onChanged: (v) => setState(() => _options.exportWav = v ?? false),
          title: 'WAV',
          subtitle: 'Lossless, higher quality',
        ),
      ],
    );
  }

  Widget _buildQualitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quality',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        // MP3 bitrate
        if (_options.exportMp3) ...[
          _buildDropdownRow(
            label: 'MP3 Bitrate',
            value: _options.mp3Bitrate,
            items: const [
              DropdownMenuItem(value: 128, child: Text('128 kbps (Small)')),
              DropdownMenuItem(value: 192, child: Text('192 kbps (Medium)')),
              DropdownMenuItem(value: 320, child: Text('320 kbps (High)')),
            ],
            onChanged: (v) => setState(() => _options.mp3Bitrate = v ?? 320),
          ),
          const SizedBox(height: 8),
        ],
        // WAV bit depth
        if (_options.exportWav) ...[
          _buildDropdownRow(
            label: 'WAV Bit Depth',
            value: _options.wavBitDepth,
            items: const [
              DropdownMenuItem(value: 16, child: Text('16-bit (CD Quality)')),
              DropdownMenuItem(value: 24, child: Text('24-bit (Studio)')),
              DropdownMenuItem(value: 32, child: Text('32-bit Float (Master)')),
            ],
            onChanged: (v) => setState(() => _options.wavBitDepth = v ?? 16),
          ),
          const SizedBox(height: 8),
        ],
        // Sample rate (common)
        _buildDropdownRow(
          label: 'Sample Rate',
          value: _options.sampleRate,
          items: const [
            DropdownMenuItem(value: 44100, child: Text('44.1 kHz (CD)')),
            DropdownMenuItem(value: 48000, child: Text('48 kHz (Video)')),
          ],
          onChanged: (v) => setState(() => _options.sampleRate = v ?? 44100),
        ),
      ],
    );
  }

  Widget _buildStemExportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() => _showStems = !_showStems);
            if (_showStems && _options.stemTracks.isEmpty) {
              _loadTracksForStems();
            }
          },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  _showStems
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  color: Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Stem Export',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _options.exportStems
                      ? '(${_options.stemTracks.where((t) => t.selected).length} tracks)'
                      : '',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        if (_showStems) ...[
          const SizedBox(height: 12),
          _buildSwitchRow(
            label: 'Export Individual Tracks',
            subtitle: 'Export each track as a separate file',
            value: _options.exportStems,
            onChanged: (v) {
              setState(() => _options.exportStems = v);
              if (v && _options.stemTracks.isEmpty) {
                _loadTracksForStems();
              }
            },
          ),
          if (_options.exportStems) ...[
            const SizedBox(height: 12),
            // Select All / Deselect All buttons
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      for (var track in _options.stemTracks) {
                        track.selected = true;
                      }
                    });
                  },
                  icon: const Icon(Icons.select_all, size: 16),
                  label: const Text('Select All'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      for (var track in _options.stemTracks) {
                        track.selected = false;
                      }
                    });
                  },
                  icon: const Icon(Icons.deselect, size: 16),
                  label: const Text('Deselect All'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Track list
            if (_loadingTracks)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_options.stemTracks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No tracks available',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  color: const Color(0xFF333333),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _options.stemTracks.length,
                  itemBuilder: (context, index) {
                    final track = _options.stemTracks[index];
                    return CheckboxListTile(
                      value: track.selected,
                      onChanged: (v) {
                        setState(() => track.selected = v ?? false);
                      },
                      title: Text(
                        track.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        track.type,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                      activeColor: const Color(0xFF00BCD4),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    );
                  },
                ),
              ),
          ],
        ],
      ],
    );
  }

  Widget _buildMetadataSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _showMetadata = !_showMetadata),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  _showMetadata
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  color: Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Metadata',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _options.exportMp3 ? '(MP3 only)' : '',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        if (_showMetadata) ...[
          const SizedBox(height: 12),
          _buildTextFieldRow('Title', _titleController, (v) {
            _options.title = v;
          }),
          const SizedBox(height: 8),
          _buildTextFieldRow('Artist', _artistController, (v) {
            _options.artist = v;
          }),
          const SizedBox(height: 8),
          _buildTextFieldRow('Album', _albumController, (v) {
            _options.album = v;
          }),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTextFieldRow('Year', _yearController, (v) {
                  _options.year = int.tryParse(v);
                }, isNumber: true),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTextFieldRow('Genre', _genreController, (v) {
                  _options.genre = v;
                }),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAdvancedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Icon(
                  _showAdvanced
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  color: Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Advanced',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showAdvanced) ...[
          const SizedBox(height: 12),
          _buildSwitchRow(
            label: 'Normalize',
            subtitle: 'Maximize volume to -0.1 dBFS',
            value: _options.normalize,
            onChanged: (v) => setState(() => _options.normalize = v),
          ),
          const SizedBox(height: 8),
          if (_options.exportWav && _options.wavBitDepth < 32)
            _buildSwitchRow(
              label: 'Dither',
              subtitle: 'Add noise shaping for bit depth reduction',
              value: _options.dither,
              onChanged: (v) => setState(() => _options.dither = v),
            ),
          const SizedBox(height: 8),
          _buildSwitchRow(
            label: 'Mono',
            subtitle: 'Mix down to single channel',
            value: _options.mono,
            onChanged: (v) => setState(() => _options.mono = v),
          ),
        ],
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFF404040)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _isExporting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _isExporting ? null : _doExport,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BCD4),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Export'),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckboxTile({
    required bool value,
    required bool enabled,
    required ValueChanged<bool?> onChanged,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF333333),
        borderRadius: BorderRadius.circular(8),
        border: value
            ? Border.all(color: const Color(0xFF00BCD4), width: 1)
            : null,
      ),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeColor: const Color(0xFF00BCD4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: enabled ? Colors.white : Colors.grey,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: enabled ? Colors.grey : Colors.grey.shade700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownRow<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: BorderRadius.circular(6),
            ),
            child: DropdownButton<T>(
              value: value,
              items: items,
              onChanged: onChanged,
              isExpanded: true,
              underline: const SizedBox(),
              dropdownColor: const Color(0xFF333333),
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextFieldRow(
    String label,
    TextEditingController controller,
    ValueChanged<String> onChanged, {
    bool isNumber = false,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: const TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        Expanded(
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: BorderRadius.circular(6),
            ),
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              keyboardType:
                  isNumber ? TextInputType.number : TextInputType.text,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchRow({
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: const Color(0xFF00BCD4).withValues(alpha: 0.5),
          activeThumbColor: const Color(0xFF00BCD4),
        ),
      ],
    );
  }
}
