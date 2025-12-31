import 'package:flutter/material.dart';
import '../audio_engine.dart';
import '../theme/theme_extension.dart';

/// Effect data model
class EffectData {
  final int id;
  final String type;
  final Map<String, double> parameters;
  final bool bypassed;

  EffectData({
    required this.id,
    required this.type,
    required this.parameters,
    this.bypassed = false,
  });

  /// Parse effect info from format: "type:eq,bypassed:0,low_freq:100,low_gain:0,..."
  static EffectData? fromInfo(int id, String info) {
    try {
      final Map<String, double> params = {};
      String? type;
      bool bypassed = false;

      final pairs = info.split(',');
      for (final pair in pairs) {
        final parts = pair.split(':');
        if (parts.length == 2) {
          if (parts[0] == 'type') {
            type = parts[1];
          } else if (parts[0] == 'bypassed') {
            bypassed = parts[1] == '1';
          } else {
            params[parts[0]] = double.parse(parts[1]);
          }
        }
      }

      if (type == null) return null;

      return EffectData(id: id, type: type, parameters: params, bypassed: bypassed);
    } catch (e) {
      return null;
    }
  }

  /// Create a copy with updated bypass state
  EffectData copyWith({bool? bypassed}) {
    return EffectData(
      id: id,
      type: type,
      parameters: parameters,
      bypassed: bypassed ?? this.bypassed,
    );
  }
}

/// Effect parameter panel widget
class EffectParameterPanel extends StatefulWidget {
  final AudioEngine? audioEngine;
  final int trackId;
  final VoidCallback onClose;

  const EffectParameterPanel({
    super.key,
    required this.audioEngine,
    required this.trackId,
    required this.onClose,
  });

  @override
  State<EffectParameterPanel> createState() => _EffectParameterPanelState();
}

class _EffectParameterPanelState extends State<EffectParameterPanel> {
  List<EffectData> _effects = [];

  @override
  void initState() {
    super.initState();
    _loadEffects();
  }

  void _loadEffects() {
    if (widget.audioEngine == null) return;

    try {
      final effectIds = widget.audioEngine!.getTrackEffects(widget.trackId);
      if (effectIds.isEmpty) {
        setState(() {
          _effects = [];
        });
        return;
      }

      final effects = <EffectData>[];
      for (final idStr in effectIds.split(',')) {
        if (idStr.isEmpty) continue;
        final id = int.tryParse(idStr);
        if (id == null) continue;

        final info = widget.audioEngine!.getEffectInfo(id);
        final effect = EffectData.fromInfo(id, info);
        if (effect != null) {
          effects.add(effect);
        }
      }

      setState(() {
        _effects = effects;
      });
    } catch (e) {
      debugPrint('EffectParameterPanel: Error loading effects: $e');
    }
  }

  void _addEffect(String type) {
    if (widget.audioEngine == null) return;

    final effectId = widget.audioEngine!.addEffectToTrack(widget.trackId, type);
    if (effectId >= 0) {
      _loadEffects();
    }
  }

  void _removeEffect(int effectId) {
    if (widget.audioEngine == null) return;

    widget.audioEngine!.removeEffectFromTrack(widget.trackId, effectId);
    _loadEffects();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 350,
      decoration: BoxDecoration(
        color: context.colors.standard,
        border: Border(
          left: BorderSide(color: context.colors.surface),
        ),
      ),
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Effects list
          Expanded(
            child: _effects.isEmpty
                ? _buildEmptyState()
                : _buildEffectsList(),
          ),

          // Add effect menu
          _buildAddEffectMenu(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.darkest,
        border: Border(
          bottom: BorderSide(color: context.colors.surface),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.tune,
            color: context.colors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            'EFFECTS',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            color: context.colors.textSecondary,
            iconSize: 20,
            onPressed: widget.onClose,
            tooltip: 'Close effects',
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
            Icons.graphic_eq,
            size: 48,
            color: context.colors.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            'No effects',
            style: TextStyle(
              color: context.colors.textMuted,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add an effect to get started',
            style: TextStyle(
              color: context.colors.textMuted,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEffectsList() {
    return ListView.builder(
      itemCount: _effects.length,
      itemBuilder: (context, index) {
        final effect = _effects[index];
        return _buildEffectCard(effect);
      },
    );
  }

  Widget _buildEffectCard(EffectData effect) {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.colors.darkest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.colors.surface),
      ),
      child: Column(
        children: [
          // Effect header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.standard,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _getEffectIcon(effect.type),
                  color: context.colors.success,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _getEffectName(effect.type),
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: context.colors.textMuted,
                  iconSize: 18,
                  onPressed: () => _removeEffect(effect.id),
                  tooltip: 'Remove effect',
                ),
              ],
            ),
          ),

          // Effect parameters
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildEffectParameters(effect),
          ),
        ],
      ),
    );
  }

  Widget _buildEffectParameters(EffectData effect) {
    switch (effect.type) {
      case 'eq':
        return _buildEQParameters(effect);
      case 'compressor':
        return _buildCompressorParameters(effect);
      case 'reverb':
        return _buildReverbParameters(effect);
      case 'delay':
        return _buildDelayParameters(effect);
      case 'chorus':
        return _buildChorusParameters(effect);
      default:
        return const Text('Unknown effect');
    }
  }

  Widget _buildEQParameters(EffectData effect) {
    return Column(
      children: [
        _buildParameter('Low Freq', effect.id, 'low_freq',
            effect.parameters['low_freq'] ?? 100, 20, 500, ' Hz'),
        _buildParameter('Low Gain', effect.id, 'low_gain',
            effect.parameters['low_gain'] ?? 0, -12, 12, ' dB'),
        _buildParameter('Mid1 Freq', effect.id, 'mid1_freq',
            effect.parameters['mid1_freq'] ?? 500, 200, 2000, ' Hz'),
        _buildParameter('Mid1 Gain', effect.id, 'mid1_gain',
            effect.parameters['mid1_gain'] ?? 0, -12, 12, ' dB'),
        _buildParameter('Mid2 Freq', effect.id, 'mid2_freq',
            effect.parameters['mid2_freq'] ?? 2000, 1000, 8000, ' Hz'),
        _buildParameter('Mid2 Gain', effect.id, 'mid2_gain',
            effect.parameters['mid2_gain'] ?? 0, -12, 12, ' dB'),
        _buildParameter('High Freq', effect.id, 'high_freq',
            effect.parameters['high_freq'] ?? 8000, 4000, 16000, ' Hz'),
        _buildParameter('High Gain', effect.id, 'high_gain',
            effect.parameters['high_gain'] ?? 0, -12, 12, ' dB'),
      ],
    );
  }

  Widget _buildCompressorParameters(EffectData effect) {
    return Column(
      children: [
        _buildParameter('Threshold', effect.id, 'threshold',
            effect.parameters['threshold'] ?? -20, -60, 0, ' dB'),
        _buildParameter('Ratio', effect.id, 'ratio',
            effect.parameters['ratio'] ?? 4, 1, 20, ':1'),
        _buildParameter('Attack', effect.id, 'attack',
            effect.parameters['attack'] ?? 10, 1, 100, ' ms'),
        _buildParameter('Release', effect.id, 'release',
            effect.parameters['release'] ?? 100, 10, 1000, ' ms'),
        _buildParameter('Makeup', effect.id, 'makeup',
            effect.parameters['makeup'] ?? 0, 0, 24, ' dB'),
      ],
    );
  }

  Widget _buildReverbParameters(EffectData effect) {
    return Column(
      children: [
        _buildParameter('Room Size', effect.id, 'room_size',
            effect.parameters['room_size'] ?? 0.5, 0, 1, ''),
        _buildParameter('Damping', effect.id, 'damping',
            effect.parameters['damping'] ?? 0.5, 0, 1, ''),
        _buildParameter('Wet/Dry', effect.id, 'wet_dry',
            effect.parameters['wet_dry'] ?? 0.3, 0, 1, ''),
      ],
    );
  }

  Widget _buildDelayParameters(EffectData effect) {
    return Column(
      children: [
        _buildParameter('Time', effect.id, 'time',
            effect.parameters['time'] ?? 500, 10, 2000, ' ms'),
        _buildParameter('Feedback', effect.id, 'feedback',
            effect.parameters['feedback'] ?? 0.4, 0, 0.99, ''),
        _buildParameter('Wet/Dry', effect.id, 'wet_dry',
            effect.parameters['wet_dry'] ?? 0.3, 0, 1, ''),
      ],
    );
  }

  Widget _buildChorusParameters(EffectData effect) {
    return Column(
      children: [
        _buildParameter('Rate', effect.id, 'rate',
            effect.parameters['rate'] ?? 1.5, 0.1, 10, ' Hz'),
        _buildParameter('Depth', effect.id, 'depth',
            effect.parameters['depth'] ?? 0.5, 0, 1, ''),
        _buildParameter('Wet/Dry', effect.id, 'wet_dry',
            effect.parameters['wet_dry'] ?? 0.3, 0, 1, ''),
      ],
    );
  }

  Widget _buildParameter(
    String label,
    int effectId,
    String paramName,
    double value,
    double min,
    double max,
    String unit,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 12,
                ),
              ),
              Text(
                '${value.toStringAsFixed(1)}$unit',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 6,
              ),
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: 12,
              ),
              activeTrackColor: context.colors.success,
              inactiveTrackColor: context.colors.surface,
              thumbColor: context.colors.textSecondary,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: (newValue) {
                widget.audioEngine?.setEffectParameter(
                    effectId, paramName, newValue);
                _loadEffects();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddEffectMenu() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.darkest,
        border: Border(
          top: BorderSide(color: context.colors.surface),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: () => _addEffect('eq'),
            icon: const Icon(Icons.equalizer, size: 16),
            label: const Text('EQ'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.surface,
              foregroundColor: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          ElevatedButton.icon(
            onPressed: () => _addEffect('compressor'),
            icon: const Icon(Icons.compress, size: 16),
            label: const Text('Compressor'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.surface,
              foregroundColor: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _addEffect('reverb'),
                  icon: const Icon(Icons.blur_on, size: 16),
                  label: const Text('Reverb'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.surface,
                    foregroundColor: context.colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _addEffect('delay'),
                  icon: const Icon(Icons.av_timer, size: 16),
                  label: const Text('Delay'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.surface,
                    foregroundColor: context.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ElevatedButton.icon(
            onPressed: () => _addEffect('chorus'),
            icon: const Icon(Icons.graphic_eq, size: 16),
            label: const Text('Chorus'),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.surface,
              foregroundColor: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getEffectIcon(String type) {
    switch (type) {
      case 'eq':
        return Icons.equalizer;
      case 'compressor':
        return Icons.compress;
      case 'reverb':
        return Icons.blur_on;
      case 'delay':
        return Icons.av_timer;
      case 'chorus':
        return Icons.graphic_eq;
      default:
        return Icons.tune;
    }
  }

  String _getEffectName(String type) {
    switch (type) {
      case 'eq':
        return 'Parametric EQ';
      case 'compressor':
        return 'Compressor';
      case 'reverb':
        return 'Reverb';
      case 'delay':
        return 'Delay';
      case 'chorus':
        return 'Chorus';
      default:
        return type.toUpperCase();
    }
  }
}
