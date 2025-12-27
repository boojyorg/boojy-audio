import 'package:flutter/material.dart';
import 'dart:async';
import '../audio_engine.dart';

/// Track data model
class TrackData {
  final int id;
  final String name;
  final String type;
  double volumeDb;
  double pan;
  bool mute;
  bool solo;
  bool armed;

  TrackData({
    required this.id,
    required this.name,
    required this.type,
    required this.volumeDb,
    required this.pan,
    required this.mute,
    required this.solo,
    required this.armed,
  });

  /// Parse track info from CSV format: "track_id,name,type,volume_db,pan,mute,solo,armed"
  static TrackData? fromCSV(String csv) {
    try {
      final parts = csv.split(',');
      if (parts.length < 8) return null;

      return TrackData(
        id: int.parse(parts[0]),
        name: parts[1],
        type: parts[2],
        volumeDb: double.parse(parts[3]),
        pan: double.parse(parts[4]),
        mute: parts[5] == 'true' || parts[5] == '1',
        solo: parts[6] == 'true' || parts[6] == '1',
        armed: parts[7] == 'true' || parts[7] == '1',
      );
    } catch (e) {
      return null;
    }
  }
}

/// Mixer panel widget - slide-in from right
class MixerPanel extends StatefulWidget {
  final AudioEngine? audioEngine;
  final VoidCallback onClose;
  final Function(int?)? onFXButtonClicked;
  final Function(int)? onTrackDeleted;

  const MixerPanel({
    super.key,
    required this.audioEngine,
    required this.onClose,
    this.onFXButtonClicked,
    this.onTrackDeleted,
  });

  @override
  State<MixerPanel> createState() => _MixerPanelState();
}

class _MixerPanelState extends State<MixerPanel> {
  List<TrackData> _tracks = [];
  Timer? _refreshTimer;
  int? _selectedTrackForFX;

  @override
  void initState() {
    super.initState();
    _loadTracksAsync(); // Load asynchronously on init

    // Refresh tracks every 2 seconds (reduced frequency to avoid UI blocking)
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _loadTracksAsync();
    });
  }

  @override
  void didUpdateWidget(MixerPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload tracks when audio engine becomes available
    if (widget.audioEngine != null && oldWidget.audioEngine == null) {
      _loadTracksAsync();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Load tracks asynchronously to avoid blocking UI thread
  Future<void> _loadTracksAsync() async {
    if (widget.audioEngine == null) return;

    // Run FFI calls in a future to avoid blocking UI
    try {
      // These FFI calls can block if audio thread holds locks,
      // so we yield to the event loop between calls
      final trackIds = await Future.microtask(() {
        return widget.audioEngine!.getAllTrackIds();
      });

      final tracks = <TrackData>[];

      for (int trackId in trackIds) {
        // Yield to event loop between each track query
        final info = await Future.microtask(() {
          return widget.audioEngine!.getTrackInfo(trackId);
        });

        final track = TrackData.fromCSV(info);
        if (track != null) {
          tracks.add(track);
        }
      }

      if (mounted) {
        setState(() {
          _tracks = tracks;
        });
      }
    } catch (e) {
    }
  }

  void _createTrack(String type) {
    if (widget.audioEngine == null) return;

    final name = '${type.toUpperCase()} ${_tracks.length + 1}';
    final trackId = widget.audioEngine!.createTrack(type, name);

    if (trackId >= 0) {
      _loadTracksAsync();
    }
  }

  void _showAddTrackMenu() {
    // Find the button position
    final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    // Show popup menu
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        overlay.size.width - 300, // Position near the + button
        60, // Below the header
        overlay.size.width - 100,
        0,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'audio',
          child: Row(
            children: const [
              Icon(Icons.audiotrack, size: 18, color: Color(0xFF202020)),
              SizedBox(width: 12),
              Text('Audio Track', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'midi',
          child: Row(
            children: const [
              Icon(Icons.piano, size: 18, color: Color(0xFF202020)),
              SizedBox(width: 12),
              Text('MIDI Track', style: TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
      elevation: 8,
    ).then((value) {
      if (value != null) {
        _createTrack(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 300, // Reduced from 400px
      decoration: const BoxDecoration(
        color: Color(0xFF707070),
        border: Border(
          left: BorderSide(color: Color(0xFF909090)),
        ),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Track strips
          Expanded(
            child: _tracks.isEmpty
                ? _buildEmptyState()
                : _buildTrackList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF656565),
        border: Border(
          bottom: BorderSide(color: Color(0xFF909090)),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.tune,
            color: Color(0xFF202020),
            size: 20,
          ),
          const SizedBox(width: 12),
          const Text(
            'MIXER',
            style: TextStyle(
              color: Color(0xFF202020),
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          // Add track button
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: const Color(0xFF202020),
            iconSize: 20,
            onPressed: _showAddTrackMenu,
            tooltip: 'Add track',
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close),
            color: const Color(0xFF202020),
            iconSize: 20,
            onPressed: widget.onClose,
            tooltip: 'Close mixer',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.audio_file_outlined,
            size: 48,
            color: Colors.grey[700],
          ),
          const SizedBox(height: 16),
          Text(
            'No tracks yet',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a track to get started',
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackList() {
    return Column(
      children: [
        // Regular tracks (horizontal scroll)
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _tracks.where((t) => t.type != 'Master').map((track) => _buildTrackStrip(track)).toList(),
            ),
          ),
        ),

        // Master track at bottom
        if (_tracks.any((t) => t.type == 'Master'))
          _buildMasterTrackStrip(_tracks.firstWhere((t) => t.type == 'Master')),
      ],
    );
  }

  Widget _buildTrackStrip(TrackData track) {
    return Container(
      width: 100,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF656565),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF909090)),
      ),
      child: Column(
        children: [
          // Track name and type
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFF707070),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Column(
              children: [
                Text(
                  track.name,
                  style: const TextStyle(
                    color: Color(0xFF202020),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  track.type.toUpperCase(),
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),

          // Volume fader
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _buildVolumeFader(track),
            ),
          ),

          // Pan knob (simplified as slider for now)
          _buildPanControl(track),

          // Mute/Solo buttons
          _buildMuteSoloButtons(track),

          const SizedBox(height: 8),

          // FX and Delete buttons
          _buildTrackActions(track),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildTrackActions(TrackData track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // FX button
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                if (widget.onFXButtonClicked != null) {
                  // Use parent callback (new bottom panel approach)
                  widget.onFXButtonClicked!(
                    _selectedTrackForFX == track.id ? null : track.id
                  );
                  setState(() {
                    _selectedTrackForFX =
                        _selectedTrackForFX == track.id ? null : track.id;
                  });
                } else {
                  // Fallback to old approach (show effect panel on right)
                  setState(() {
                    _selectedTrackForFX =
                        _selectedTrackForFX == track.id ? null : track.id;
                  });
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedTrackForFX == track.id
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFF909090),
                foregroundColor: _selectedTrackForFX == track.id
                    ? Colors.white
                    : const Color(0xFF404040),
                padding: const EdgeInsets.symmetric(vertical: 4),
                minimumSize: const Size(0, 24),
              ),
              child: const Text('FX', style: TextStyle(fontSize: 10)),
            ),
          ),
          const SizedBox(width: 4),

          // Delete button
          SizedBox(
            width: 24,
            child: IconButton(
              icon: const Icon(Icons.close, size: 14),
              color: const Color(0xFF404040),
              padding: EdgeInsets.zero,
              onPressed: () => _confirmDeleteTrack(track),
              tooltip: 'Delete track',
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteTrack(TrackData track) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Track'),
        content: Text('Are you sure you want to delete "${track.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              widget.audioEngine?.deleteTrack(track.id);
              widget.onTrackDeleted?.call(track.id);
              Navigator.of(context).pop();
              _loadTracksAsync();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterTrackStrip(TrackData track) {
    return Container(
      width: 120,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF606060),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF4CAF50), width: 2),
      ),
      child: Column(
        children: [
          // Track name
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFF707070),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Column(
              children: [
                const Text(
                  'MASTER',
                  style: TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  track.type.toUpperCase(),
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),

          // Volume fader
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _buildVolumeFader(track),
            ),
          ),

          // Pan control
          _buildPanControl(track),

          const SizedBox(height: 8),

          // Limiter indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF707070),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.security, size: 12, color: Color(0xFF4CAF50)),
                  SizedBox(width: 4),
                  Text(
                    'LIMITER',
                    style: TextStyle(
                      color: Color(0xFF4CAF50),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildVolumeFader(TrackData track) {
    return Column(
      children: [
        // Volume label
        Text(
          '${track.volumeDb.toStringAsFixed(1)} dB',
          style: const TextStyle(
            color: Color(0xFF404040),
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 8),

        // Vertical slider
        Expanded(
          child: RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 12,
                ),
                activeTrackColor: const Color(0xFF4CAF50),
                inactiveTrackColor: const Color(0xFF909090),
                thumbColor: const Color(0xFF202020),
              ),
              child: Slider(
                value: _volumeDbToSlider(track.volumeDb),
                min: 0.0,
                max: 1.0,
                onChanged: (value) {
                  final volumeDb = _sliderToVolumeDb(value);
                  setState(() {
                    track.volumeDb = volumeDb;
                  });
                  widget.audioEngine?.setTrackVolume(track.id, volumeDb);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPanControl(TrackData track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Text(
            _panToLabel(track.pan),
            style: const TextStyle(
              color: Color(0xFF404040),
              fontSize: 10,
            ),
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 5,
              ),
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: 10,
              ),
              activeTrackColor: const Color(0xFF2196F3),
              inactiveTrackColor: const Color(0xFF909090),
              thumbColor: const Color(0xFF202020),
            ),
            child: Slider(
              value: track.pan,
              min: -1.0,
              max: 1.0,
              onChanged: (value) {
                setState(() {
                  track.pan = value;
                });
                widget.audioEngine?.setTrackPan(track.id, value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMuteSoloButtons(TrackData track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Mute button
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  track.mute = !track.mute;
                });
                widget.audioEngine?.setTrackMute(track.id, track.mute);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: track.mute
                    ? const Color(0xFFFF5722)
                    : const Color(0xFF909090),
                foregroundColor: track.mute
                    ? Colors.white
                    : const Color(0xFF404040),
                padding: const EdgeInsets.symmetric(vertical: 4),
                minimumSize: const Size(0, 24),
              ),
              child: const Text('M', style: TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(width: 4),

          // Solo button
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  track.solo = !track.solo;
                });
                widget.audioEngine?.setTrackSolo(track.id, track.solo);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: track.solo
                    ? const Color(0xFFFFC107)
                    : const Color(0xFF909090),
                foregroundColor: track.solo
                    ? Colors.black
                    : const Color(0xFF404040),
                padding: const EdgeInsets.symmetric(vertical: 4),
                minimumSize: const Size(0, 24),
              ),
              child: const Text('S', style: TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(width: 4),

          // Record Arm button
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  track.armed = !track.armed;
                });
                widget.audioEngine?.setTrackArmed(track.id, track.armed);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: track.armed
                    ? const Color(0xFFE53935)  // Bright red when armed
                    : const Color(0xFF909090),
                foregroundColor: track.armed
                    ? Colors.white
                    : const Color(0xFF404040),
                padding: const EdgeInsets.symmetric(vertical: 4),
                minimumSize: const Size(0, 24),
              ),
              child: const Text('R', style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  // Helper functions for volume conversion
  double _volumeDbToSlider(double volumeDb) {
    // Convert dB (-60 to +6) to slider (0 to 1)
    // 0 dB should be at 0.75 position
    return (volumeDb + 60.0) / 66.0;
  }

  double _sliderToVolumeDb(double slider) {
    // Convert slider (0 to 1) to dB (-60 to +6)
    return (slider * 66.0) - 60.0;
  }

  String _panToLabel(double pan) {
    if (pan < -0.05) {
      return 'L${(pan.abs() * 100).toStringAsFixed(0)}';
    } else if (pan > 0.05) {
      return 'R${(pan * 100).toStringAsFixed(0)}';
    } else {
      return 'C';
    }
  }
}
