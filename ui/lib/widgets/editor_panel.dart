import 'package:flutter/material.dart';
import '../audio_engine.dart';
import 'virtual_piano.dart';
import 'effect_parameter_panel.dart';
import 'piano_roll.dart';
import 'synthesizer_panel.dart';
import 'vst3_plugin_parameter_panel.dart';
import '../models/midi_note_data.dart';
import '../models/instrument_data.dart';
import '../models/vst3_plugin_data.dart';

/// Editor panel widget - tabbed interface for Piano Roll, FX Chain, Instrument, and Virtual Piano
class EditorPanel extends StatefulWidget {
  final AudioEngine? audioEngine;
  final bool virtualPianoEnabled;
  final int? selectedTrackId; // Unified track selection
  final InstrumentData? currentInstrumentData;
  final VoidCallback? onVirtualPianoClose;
  final VoidCallback? onClosePanel; // Close the entire editor panel
  final MidiClipData? currentEditingClip;
  final Function(MidiClipData)? onMidiClipUpdated;
  final Function(InstrumentData)? onInstrumentParameterChanged;

  // M10: VST3 Plugin support
  final List<Vst3PluginInstance>? currentTrackPlugins;
  final Function(int effectId, int paramIndex, double value)? onVst3ParameterChanged;
  final Function(int effectId)? onVst3PluginRemoved;

  const EditorPanel({
    super.key,
    this.audioEngine,
    this.virtualPianoEnabled = false,
    this.selectedTrackId,
    this.currentInstrumentData,
    this.onVirtualPianoClose,
    this.onClosePanel,
    this.currentEditingClip,
    this.onMidiClipUpdated,
    this.onInstrumentParameterChanged,
    this.currentTrackPlugins,
    this.onVst3ParameterChanged,
    this.onVst3PluginRemoved,
  });

  @override
  State<EditorPanel> createState() => _EditorPanelState();
}

class _EditorPanelState extends State<EditorPanel> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _selectedTabIndex = _tabController.index;
      });
    });
  }

  @override
  void didUpdateWidget(EditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only auto-switch tabs if this is the first track selection (from null)
    // Otherwise, preserve the current tab when switching between tracks
    if (widget.selectedTrackId != oldWidget.selectedTrackId) {
      if (oldWidget.selectedTrackId == null && widget.selectedTrackId != null) {
        // First selection: auto-switch to appropriate tab
        if (widget.currentInstrumentData != null) {
          _tabController.index = 2; // Instrument tab
        } else {
          _tabController.index = 0; // Piano Roll tab
        }
      }
      // If switching from one track to another, preserve current tab
    }

    // Auto-switch to Piano Roll tab when clip selected
    if (widget.currentEditingClip != null && oldWidget.currentEditingClip == null) {
      _tabController.index = 0;
    }

    // Auto-switch to Instrument tab when instrument data first appears
    if (widget.currentInstrumentData != null && oldWidget.currentInstrumentData == null) {
      _tabController.index = 2;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      decoration: const BoxDecoration(
        color: Color(0xFF242424),
        border: Border(
          top: BorderSide(color: Color(0xFF444444)),
        ),
      ),
      child: Column(
        children: [
          // Custom tab bar with icons and pill-style active indicator
          Container(
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFF2A2A2A),
              border: Border(
                bottom: BorderSide(color: Color(0xFF3A3A3A)),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                // Tab buttons
                _buildTabButton(0, Icons.piano_outlined, 'Piano Roll'),
                const SizedBox(width: 4),
                _buildTabButton(1, Icons.equalizer, 'FX Chain'),
                const SizedBox(width: 4),
                _buildTabButton(2, Icons.music_note, 'Instrument'),
                const Spacer(),
                // Close button
                Tooltip(
                  message: 'Close Panel',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onClosePanel,
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.close,
                          size: 18,
                          color: Color(0xFF9E9E9E),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPianoRollTab(),
                _buildFXChainTab(),
                _buildInstrumentTab(),
              ],
            ),
          ),

          // Virtual Piano (below tabs, always visible when enabled)
          if (widget.virtualPianoEnabled)
            VirtualPiano(
              audioEngine: widget.audioEngine,
              isEnabled: widget.virtualPianoEnabled,
              onClose: widget.onVirtualPianoClose,
              selectedTrackId: widget.selectedTrackId,
            ),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label) {
    final isSelected = _selectedTabIndex == index;
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _tabController.index = index;
          },
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF00BCD4) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? Colors.white : const Color(0xFF9E9E9E),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? Colors.white : const Color(0xFF9E9E9E),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPianoRollTab() {
    // Use real clip data if available, otherwise create an empty clip for the selected track
    final clipData = widget.currentEditingClip ?? (widget.selectedTrackId != null
      ? MidiClipData(
          clipId: -1, // -1 indicates a new, unsaved clip
          trackId: widget.selectedTrackId!,
          startTime: 0.0,
          duration: 16.0,
          name: 'New MIDI Clip',
          notes: [],
        )
      : null);

    if (clipData == null) {
      // No track selected - show empty state
      return Container(
        color: const Color(0xFF242424),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.piano_outlined,
                size: 64,
                color: Colors.grey[700],
              ),
              const SizedBox(height: 16),
              const Text(
                'Piano Roll',
                style: TextStyle(
                  color: Color(0xFFE0E0E0),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a MIDI track or clip to start editing',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return PianoRoll(
      audioEngine: widget.audioEngine,
      clipData: clipData,
      onClipUpdated: widget.onMidiClipUpdated,
      onClose: () {
        // Switch back to another tab or close bottom panel
        _tabController.index = 3; // Switch to Virtual Piano tab
      },
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF9E9E9E),
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildFXChainTab() {
    if (widget.selectedTrackId == null) {
      return Container(
        color: const Color(0xFF242424),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.graphic_eq,
                size: 64,
                color: Colors.grey[700],
              ),
              const SizedBox(height: 16),
              const Text(
                'FX Chain',
                style: TextStyle(
                  color: Color(0xFFE0E0E0),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a track to edit effects',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show effect parameter panel when track selected
    return EffectParameterPanel(
      audioEngine: widget.audioEngine,
      trackId: widget.selectedTrackId!,
      onClose: () {
        // Don't close the panel, just show empty state
        // Parent widget handles clearing selectedTrackId
      },
    );
  }

  Widget _buildInstrumentTab() {
    if (widget.selectedTrackId == null || widget.currentInstrumentData == null) {
      return Container(
        color: const Color(0xFF242424),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.piano,
                size: 64,
                color: Colors.grey[700],
              ),
              const SizedBox(height: 16),
              const Text(
                'Instrument',
                style: TextStyle(
                  color: Color(0xFFE0E0E0),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a track with an instrument to edit',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Check if this is a VST3 instrument
    if (widget.currentInstrumentData!.isVst3) {
      // Create Vst3PluginInstance from the track's instrument data
      // This ensures the Instruments panel shows the VST3 instrument,
      // not the FX chain plugins
      final vst3Instrument = Vst3PluginInstance(
        effectId: widget.currentInstrumentData!.effectId!,
        pluginName: widget.currentInstrumentData!.pluginName ?? 'VST3 Instrument',
        pluginPath: widget.currentInstrumentData!.pluginPath ?? '',
      );

      // Show VST3 plugin parameter panel for VST3 instruments
      return Vst3PluginParameterPanel(
        audioEngine: widget.audioEngine,
        trackId: widget.selectedTrackId!,
        plugins: [vst3Instrument],
        onParameterChanged: widget.onVst3ParameterChanged,
        onRemovePlugin: widget.onVst3PluginRemoved,
      );
    }

    // Show synthesizer panel for built-in instruments
    return SynthesizerPanel(
      audioEngine: widget.audioEngine,
      trackId: widget.selectedTrackId!,
      instrumentData: widget.currentInstrumentData,
      onParameterChanged: (instrumentData) {
        widget.onInstrumentParameterChanged?.call(instrumentData);
      },
      onClose: () {
        // Parent widget handles clearing selectedTrackId
      },
    );
  }

}
