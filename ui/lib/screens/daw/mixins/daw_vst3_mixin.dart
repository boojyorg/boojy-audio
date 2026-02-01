import 'package:flutter/material.dart';
import '../../../models/instrument_data.dart';
import '../../../models/vst3_plugin_data.dart';
import '../../../services/commands/track_commands.dart';
import '../../../theme/theme_extension.dart';
import '../../../widgets/vst3_plugin_browser.dart';
import '../../daw_screen.dart';
import 'daw_screen_state.dart';
import 'daw_recording_mixin.dart';
import 'daw_ui_mixin.dart';
import 'daw_track_mixin.dart';
import 'daw_clip_mixin.dart';

/// Mixin containing VST3 plugin-related methods for DAWScreen.
/// Handles plugin scanning, adding, removing, and parameter editing.
mixin DAWVst3Mixin on State<DAWScreen>, DAWScreenStateMixin, DAWRecordingMixin, DAWUIMixin, DAWTrackMixin, DAWClipMixin {
  // ============================================
  // VST3 SCANNING
  // ============================================

  /// Scan for VST3 plugins
  Future<void> scanVst3Plugins({bool forceRescan = false}) async {
    if (vst3PluginManager == null) return;

    setState(() {
      statusMessage = forceRescan ? 'Rescanning VST3 plugins...' : 'Scanning VST3 plugins...';
    });

    final result = await vst3PluginManager!.scanPlugins(forceRescan: forceRescan);

    if (mounted) {
      setState(() {
        statusMessage = result;
      });
    }
  }

  // ============================================
  // VST3 PLUGIN MANAGEMENT
  // ============================================

  /// Add VST3 plugin to a track
  void addVst3PluginToTrack(int trackId, Map<String, String> plugin) {
    if (vst3PluginManager == null) return;

    final result = vst3PluginManager!.addToTrack(trackId, plugin);

    setState(() {
      statusMessage = result.message;
    });

    // Show snackbar based on result
    final colors = context.colors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success ? 'Added: ${result.message}' : 'Error: ${result.message}'),
        duration: Duration(seconds: result.success ? 2 : 3),
        backgroundColor: result.success ? colors.success : colors.error,
      ),
    );
  }

  /// Remove VST3 plugin from track
  void removeVst3Plugin(int effectId) {
    if (vst3PluginManager == null) return;

    final result = vst3PluginManager!.removeFromTrack(effectId);

    setState(() {
      statusMessage = result.message;
    });
  }

  /// Show VST3 plugin browser dialog
  Future<void> showVst3PluginBrowserDialog(int trackId) async {
    if (vst3PluginManager == null) return;

    final vst3Browser = await showVst3PluginBrowser(
      context,
      availablePlugins: vst3PluginManager!.availablePlugins,
      isScanning: vst3PluginManager!.isScanning,
      onRescanRequested: () {
        scanVst3Plugins(forceRescan: true);
      },
    );

    if (vst3Browser != null) {
      addVst3PluginToTrack(trackId, {
        'name': vst3Browser.name,
        'path': vst3Browser.path,
        'vendor': vst3Browser.vendor ?? '',
      });
    }
  }

  /// Handle VST3 plugin dropped on track
  void onVst3PluginDropped(int trackId, Vst3Plugin plugin) {
    if (vst3PluginManager == null) return;
    vst3PluginManager!.addPluginToTrack(trackId, plugin);
  }

  /// Get VST3 plugin counts per track
  Map<int, int> getTrackVst3PluginCounts() {
    return vst3PluginManager?.getTrackPluginCounts() ?? {};
  }

  /// Get VST3 plugins for a track
  List<Vst3PluginInstance> getTrackVst3Plugins(int trackId) {
    return vst3PluginManager?.getTrackPlugins(trackId) ?? [];
  }

  /// Handle VST3 parameter change
  void onVst3ParameterChanged(int effectId, int paramIndex, double value) {
    vst3PluginManager?.updateParameter(effectId, paramIndex, value);
  }

  // ============================================
  // VST3 PLUGIN EDITOR
  // ============================================

  /// Show VST3 plugin editor dialog
  void showVst3PluginEditor(int trackId) {
    if (vst3PluginManager == null) return;

    final effectIds = vst3PluginManager!.getTrackEffectIds(trackId);
    if (effectIds.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Plugins - Track $trackId'),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            itemCount: effectIds.length,
            itemBuilder: (context, index) {
              final effectId = effectIds[index];
              final pluginInfo = vst3PluginManager!.getPluginInfo(effectId);
              final pluginName = pluginInfo?['name'] ?? 'Unknown Plugin';

              return ListTile(
                title: Text(pluginName),
                trailing: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    showPluginParameterEditor(effectId, pluginName);
                  },
                  child: const Text('Edit'),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Show plugin parameter editor dialog
  void showPluginParameterEditor(int effectId, String pluginName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$pluginName - Parameters'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Parameter editing',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Drag the sliders to adjust plugin parameters.',
                                  style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Native editor support coming soon! For now, use the parameter sliders.'),
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            },
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Open GUI'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Show a few example parameters
                      ...buildParameterSliders(effectId),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Build parameter sliders for plugin editor
  List<Widget> buildParameterSliders(int effectId) {
    final List<Widget> sliders = [];

    for (int i = 0; i < 8; i++) {
      sliders.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Parameter ${i + 1}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '0.50',
                    style: TextStyle(fontSize: 11, color: context.colors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Slider(
                value: 0.5,
                min: 0.0,
                max: 1.0,
                divisions: 100,
                onChanged: (value) {
                  onVst3ParameterChanged(effectId, i, value);
                },
              ),
            ],
          ),
        ),
      );
    }

    return sliders;
  }

  // ============================================
  // VST3 INSTRUMENT DROP HANDLERS
  // ============================================

  /// Handle VST3 instrument dropped on existing track
  Future<void> onVst3InstrumentDropped(int trackId, Vst3Plugin plugin) async {
    if (audioEngine == null) return;

    try {
      // Load the VST3 plugin as a track instrument
      final effectId = audioEngine!.addVst3EffectToTrack(trackId, plugin.path);
      if (effectId < 0) {
        return;
      }

      // Create and store InstrumentData for this VST3 instrument
      trackController.setTrackInstrument(trackId, InstrumentData.vst3Instrument(
        trackId: trackId,
        pluginPath: plugin.path,
        pluginName: plugin.name,
        effectId: effectId,
      ));

      // Auto-populate track name with plugin name if not user-edited
      if (!trackController.isTrackNameUserEdited(trackId)) {
        audioEngine?.setTrackName(trackId, plugin.name);
      }

      // Send a test note to trigger audio processing (some VST3 instruments
      // like Serum show "Audio Processing disabled" until they receive MIDI)
      final noteOnResult = audioEngine!.vst3SendMidiNote(effectId, 0, 0, 60, 100); // C4, velocity 100
      if (noteOnResult.isNotEmpty) {
        // Note on sent
      }
      // Send note off after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted || audioEngine == null) return;
        audioEngine!.vst3SendMidiNote(effectId, 1, 0, 60, 0); // Note off
      });
    } catch (e) {
      debugPrint('Failed to preview VST3 instrument: $e');
    }
  }

  /// Handle VST3 instrument dropped on empty area - creates new track
  Future<void> onVst3InstrumentDroppedOnEmpty(Vst3Plugin plugin) async {
    if (audioEngine == null) return;

    try {
      // Create a new MIDI track using UndoRedoManager
      final command = CreateTrackCommand(
        trackType: 'midi',
        trackName: 'MIDI',
      );

      await undoRedoManager.execute(command);

      final trackId = command.createdTrackId;
      if (trackId == null || trackId < 0) {
        return;
      }

      // Create default 4-bar empty clip for the new track
      createDefaultMidiClip(trackId);

      // Load the VST3 plugin as a track instrument
      final effectId = audioEngine!.addVst3EffectToTrack(trackId, plugin.path);
      if (effectId < 0) {
        return;
      }

      // Create and store InstrumentData for this VST3 instrument
      trackController.setTrackInstrument(trackId, InstrumentData.vst3Instrument(
        trackId: trackId,
        pluginPath: plugin.path,
        pluginName: plugin.name,
        effectId: effectId,
      ));

      // Auto-populate track name with plugin name (new track, so not user-edited)
      audioEngine?.setTrackName(trackId, plugin.name);

      // Send a test note to trigger audio processing
      final noteOnResult = audioEngine!.vst3SendMidiNote(effectId, 0, 0, 60, 100);
      if (noteOnResult.isNotEmpty) {
        // Note on sent
      }
      // Send note off after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!mounted || audioEngine == null) return;
        audioEngine!.vst3SendMidiNote(effectId, 1, 0, 60, 0);
      });

      // Select the newly created track but NOT the clip (so Instrument tab shows)
      onTrackSelected(trackId, autoSelectClip: false);

      // Immediately refresh track widgets so the new track appears instantly
      refreshTrackWidgets();

      // Disarm other MIDI tracks (exclusive arm for new track)
      disarmOtherMidiTracks(trackId);
    } catch (e) {
      debugPrint('Failed to create VST3 instrument track: $e');
    }
  }

  /// Handle instrument parameter change
  void onInstrumentParameterChanged(InstrumentData instrumentData) {
    trackController.setTrackInstrument(instrumentData.trackId, instrumentData);
  }
}
