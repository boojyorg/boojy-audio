import 'package:flutter/material.dart';
import '../effect_parameter_panel.dart';
import '../../audio_engine.dart';

/// A card representing a single effect in the horizontal FX chain.
/// Displays effect name, bypass toggle, and parameter controls.
class EffectCard extends StatelessWidget {
  final EffectData effect;
  final AudioEngine? audioEngine;
  final bool isVst3;
  final bool isFloating; // VST3 popped out to floating window
  final VoidCallback onBypassToggle;
  final VoidCallback? onPopOut; // VST3 only
  final VoidCallback? onBringBack; // VST3 only
  final VoidCallback onDelete;
  final VoidCallback onParameterChanged;

  const EffectCard({
    super.key,
    required this.effect,
    required this.audioEngine,
    this.isVst3 = false,
    this.isFloating = false,
    required this.onBypassToggle,
    this.onPopOut,
    this.onBringBack,
    required this.onDelete,
    required this.onParameterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: effect.bypassed
            ? const Color(0xFF1E1E1E).withOpacity(0.5)
            : const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: effect.bypassed
              ? const Color(0xFF404040).withOpacity(0.5)
              : const Color(0xFF404040),
        ),
      ),
      child: Column(
        children: [
          // Header with bypass toggle, name, and actions
          _buildHeader(),

          // Effect parameters or floating placeholder
          Expanded(
            child: isFloating
                ? _buildFloatingPlaceholder()
                : _buildParameters(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: effect.bypassed
            ? const Color(0xFF2B2B2B).withOpacity(0.5)
            : const Color(0xFF2B2B2B),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
      ),
      child: Row(
        children: [
          // Bypass toggle
          GestureDetector(
            onTap: onBypassToggle,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: effect.bypassed
                    ? const Color(0xFF666666)
                    : const Color(0xFF4CAF50),
                border: Border.all(
                  color: effect.bypassed
                      ? const Color(0xFF808080)
                      : const Color(0xFF66BB6A),
                  width: 1.5,
                ),
              ),
              child: Icon(
                effect.bypassed ? Icons.circle_outlined : Icons.circle,
                size: 10,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Effect name
          Expanded(
            child: Text(
              _getEffectName(effect.type),
              style: TextStyle(
                color: effect.bypassed
                    ? const Color(0xFF808080)
                    : const Color(0xFFA0A0A0),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Pop-out button (VST3 only)
          if (isVst3 && !isFloating)
            IconButton(
              icon: const Icon(Icons.open_in_new),
              color: const Color(0xFF2196F3),
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: onPopOut,
              tooltip: 'Pop out to floating window',
            ),

          // Bring back button (VST3 floating only)
          if (isVst3 && isFloating)
            IconButton(
              icon: const Icon(Icons.input),
              color: const Color(0xFF2196F3),
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: onBringBack,
              tooltip: 'Bring back to panel',
            ),

          // Delete button
          IconButton(
            icon: const Icon(Icons.close),
            color: const Color(0xFF808080),
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: onDelete,
            tooltip: 'Remove effect',
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingPlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.open_in_new,
            size: 32,
            color: Colors.grey[700],
          ),
          const SizedBox(height: 8),
          Text(
            'Open in separate window',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildParameters() {
    return Opacity(
      opacity: effect.bypassed ? 0.5 : 1.0,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: _buildEffectParameters(),
      ),
    );
  }

  Widget _buildEffectParameters() {
    switch (effect.type) {
      case 'eq':
        return _buildEQParameters();
      case 'compressor':
        return _buildCompressorParameters();
      case 'reverb':
        return _buildReverbParameters();
      case 'delay':
        return _buildDelayParameters();
      case 'chorus':
        return _buildChorusParameters();
      case 'vst3':
        return _buildVst3Parameters();
      default:
        return Text(
          'Unknown effect: ${effect.type}',
          style: const TextStyle(color: Color(0xFF808080), fontSize: 11),
        );
    }
  }

  Widget _buildEQParameters() {
    return Column(
      children: [
        _buildCompactParameter('Low', 'low_gain', effect.parameters['low_gain'] ?? 0, -12, 12, ' dB'),
        _buildCompactParameter('Mid1', 'mid1_gain', effect.parameters['mid1_gain'] ?? 0, -12, 12, ' dB'),
        _buildCompactParameter('Mid2', 'mid2_gain', effect.parameters['mid2_gain'] ?? 0, -12, 12, ' dB'),
        _buildCompactParameter('High', 'high_gain', effect.parameters['high_gain'] ?? 0, -12, 12, ' dB'),
      ],
    );
  }

  Widget _buildCompressorParameters() {
    return Column(
      children: [
        _buildCompactParameter('Thresh', 'threshold', effect.parameters['threshold'] ?? -20, -60, 0, ' dB'),
        _buildCompactParameter('Ratio', 'ratio', effect.parameters['ratio'] ?? 4, 1, 20, ':1'),
        _buildCompactParameter('Attack', 'attack', effect.parameters['attack'] ?? 10, 1, 100, 'ms'),
        _buildCompactParameter('Release', 'release', effect.parameters['release'] ?? 100, 10, 1000, 'ms'),
      ],
    );
  }

  Widget _buildReverbParameters() {
    return Column(
      children: [
        _buildCompactParameter('Size', 'room_size', effect.parameters['room_size'] ?? 0.5, 0, 1, ''),
        _buildCompactParameter('Damp', 'damping', effect.parameters['damping'] ?? 0.5, 0, 1, ''),
        _buildCompactParameter('Mix', 'wet_dry', effect.parameters['wet_dry'] ?? 0.3, 0, 1, ''),
      ],
    );
  }

  Widget _buildDelayParameters() {
    return Column(
      children: [
        _buildCompactParameter('Time', 'time', effect.parameters['time'] ?? 500, 10, 2000, 'ms'),
        _buildCompactParameter('Fdbk', 'feedback', effect.parameters['feedback'] ?? 0.4, 0, 0.99, ''),
        _buildCompactParameter('Mix', 'wet_dry', effect.parameters['wet_dry'] ?? 0.3, 0, 1, ''),
      ],
    );
  }

  Widget _buildChorusParameters() {
    return Column(
      children: [
        _buildCompactParameter('Rate', 'rate', effect.parameters['rate'] ?? 1.5, 0.1, 10, 'Hz'),
        _buildCompactParameter('Depth', 'depth', effect.parameters['depth'] ?? 0.5, 0, 1, ''),
        _buildCompactParameter('Mix', 'wet_dry', effect.parameters['wet_dry'] ?? 0.3, 0, 1, ''),
      ],
    );
  }

  Widget _buildVst3Parameters() {
    // VST3 plugins have their native UI - show placeholder
    return Center(
      child: Text(
        effect.parameters['name']?.toString() ?? 'VST3 Plugin',
        style: const TextStyle(color: Color(0xFF808080), fontSize: 11),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildCompactParameter(
    String label,
    String paramName,
    double value,
    double min,
    double max,
    String unit,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 45,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF808080),
                fontSize: 10,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: const Color(0xFF4CAF50),
                inactiveTrackColor: const Color(0xFF404040),
                thumbColor: const Color(0xFFA0A0A0),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: effect.bypassed
                    ? null
                    : (newValue) {
                        audioEngine?.setEffectParameter(effect.id, paramName, newValue);
                        onParameterChanged();
                      },
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '${value.toStringAsFixed(1)}$unit',
              style: const TextStyle(
                color: Color(0xFFA0A0A0),
                fontSize: 9,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _getEffectName(String type) {
    switch (type) {
      case 'eq':
        return 'EQ';
      case 'compressor':
        return 'Compressor';
      case 'reverb':
        return 'Reverb';
      case 'delay':
        return 'Delay';
      case 'chorus':
        return 'Chorus';
      case 'limiter':
        return 'Limiter';
      case 'vst3':
        return effect.parameters['name']?.toString() ?? 'VST3';
      default:
        return type.toUpperCase();
    }
  }
}
