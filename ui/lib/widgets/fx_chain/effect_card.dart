import 'package:flutter/material.dart';
import '../effect_parameter_panel.dart';
import '../../audio_engine.dart';
import '../../theme/theme_extension.dart';

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
            ? context.colors.darkest.withValues(alpha: 0.5)
            : context.colors.darkest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: effect.bypassed
              ? context.colors.surface.withValues(alpha: 0.5)
              : context.colors.surface,
        ),
      ),
      child: Column(
        children: [
          // Header with bypass toggle, name, and actions
          _buildHeader(context),

          // Effect parameters or floating placeholder
          Expanded(
            child: isFloating
                ? _buildFloatingPlaceholder(context)
                : _buildParameters(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: effect.bypassed
            ? context.colors.standard.withValues(alpha: 0.5)
            : context.colors.standard,
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
                    ? context.colors.textMuted
                    : context.colors.success,
                border: Border.all(
                  color: effect.bypassed
                      ? context.colors.textMuted
                      : context.colors.success,
                  width: 1.5,
                ),
              ),
              child: Icon(
                effect.bypassed ? Icons.circle_outlined : Icons.circle,
                size: 10,
                color: context.colors.textPrimary,
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
                    ? context.colors.textMuted
                    : context.colors.textSecondary,
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
              color: context.colors.accent,
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
              color: context.colors.accent,
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: onBringBack,
              tooltip: 'Bring back to panel',
            ),

          // Delete button
          IconButton(
            icon: const Icon(Icons.close),
            color: context.colors.textMuted,
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

  Widget _buildFloatingPlaceholder(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.open_in_new,
            size: 32,
            color: context.colors.textMuted,
          ),
          const SizedBox(height: 8),
          Text(
            'Open in separate window',
            style: TextStyle(
              color: context.colors.textMuted,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildParameters(BuildContext context) {
    return Opacity(
      opacity: effect.bypassed ? 0.5 : 1.0,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: _buildEffectParameters(context),
      ),
    );
  }

  Widget _buildEffectParameters(BuildContext context) {
    switch (effect.type) {
      case 'eq':
        return _buildEQParameters(context);
      case 'compressor':
        return _buildCompressorParameters(context);
      case 'reverb':
        return _buildReverbParameters(context);
      case 'delay':
        return _buildDelayParameters(context);
      case 'chorus':
        return _buildChorusParameters(context);
      case 'vst3':
        return _buildVst3Parameters(context);
      default:
        return Text(
          'Unknown effect: ${effect.type}',
          style: TextStyle(color: context.colors.textMuted, fontSize: 11),
        );
    }
  }

  Widget _buildEQParameters(BuildContext context) {
    return Column(
      children: [
        _buildCompactParameter(context, 'Low', 'low_gain', effect.parameters['low_gain'] ?? 0, -12, 12, ' dB'),
        _buildCompactParameter(context, 'Mid1', 'mid1_gain', effect.parameters['mid1_gain'] ?? 0, -12, 12, ' dB'),
        _buildCompactParameter(context, 'Mid2', 'mid2_gain', effect.parameters['mid2_gain'] ?? 0, -12, 12, ' dB'),
        _buildCompactParameter(context, 'High', 'high_gain', effect.parameters['high_gain'] ?? 0, -12, 12, ' dB'),
      ],
    );
  }

  Widget _buildCompressorParameters(BuildContext context) {
    return Column(
      children: [
        _buildCompactParameter(context, 'Thresh', 'threshold', effect.parameters['threshold'] ?? -20, -60, 0, ' dB'),
        _buildCompactParameter(context, 'Ratio', 'ratio', effect.parameters['ratio'] ?? 4, 1, 20, ':1'),
        _buildCompactParameter(context, 'Attack', 'attack', effect.parameters['attack'] ?? 10, 1, 100, 'ms'),
        _buildCompactParameter(context, 'Release', 'release', effect.parameters['release'] ?? 100, 10, 1000, 'ms'),
      ],
    );
  }

  Widget _buildReverbParameters(BuildContext context) {
    return Column(
      children: [
        _buildCompactParameter(context, 'Size', 'room_size', effect.parameters['room_size'] ?? 0.5, 0, 1, ''),
        _buildCompactParameter(context, 'Damp', 'damping', effect.parameters['damping'] ?? 0.5, 0, 1, ''),
        _buildCompactParameter(context, 'Mix', 'wet_dry', effect.parameters['wet_dry'] ?? 0.3, 0, 1, ''),
      ],
    );
  }

  Widget _buildDelayParameters(BuildContext context) {
    return Column(
      children: [
        _buildCompactParameter(context, 'Time', 'time', effect.parameters['time'] ?? 500, 10, 2000, 'ms'),
        _buildCompactParameter(context, 'Fdbk', 'feedback', effect.parameters['feedback'] ?? 0.4, 0, 0.99, ''),
        _buildCompactParameter(context, 'Mix', 'wet_dry', effect.parameters['wet_dry'] ?? 0.3, 0, 1, ''),
      ],
    );
  }

  Widget _buildChorusParameters(BuildContext context) {
    return Column(
      children: [
        _buildCompactParameter(context, 'Rate', 'rate', effect.parameters['rate'] ?? 1.5, 0.1, 10, 'Hz'),
        _buildCompactParameter(context, 'Depth', 'depth', effect.parameters['depth'] ?? 0.5, 0, 1, ''),
        _buildCompactParameter(context, 'Mix', 'wet_dry', effect.parameters['wet_dry'] ?? 0.3, 0, 1, ''),
      ],
    );
  }

  Widget _buildVst3Parameters(BuildContext context) {
    // VST3 plugins have their native UI - show placeholder
    return Center(
      child: Text(
        effect.parameters['name']?.toString() ?? 'VST3 Plugin',
        style: TextStyle(color: context.colors.textMuted, fontSize: 11),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildCompactParameter(
    BuildContext context,
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
              style: TextStyle(
                color: context.colors.textMuted,
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
                activeTrackColor: context.colors.success,
                inactiveTrackColor: context.colors.surface,
                thumbColor: context.colors.textSecondary,
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
              style: TextStyle(
                color: context.colors.textSecondary,
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
