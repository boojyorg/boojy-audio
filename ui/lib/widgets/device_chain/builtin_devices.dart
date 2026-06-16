import 'package:flutter/material.dart';
import '../../theme/boojy_icons.dart';

/// Canonical descriptor for a built-in effect type.
///
/// Single source of truth shared by the device picker, the add-effect menu,
/// and the library panel's Effects category — do not duplicate these lists.
class BuiltinEffectInfo {
  const BuiltinEffectInfo({
    required this.type,
    required this.name,
    required this.icon,
  });

  /// Engine-side type string, e.g. `'eq'`, `'compressor'`.
  final String type;
  final String name;
  final IconData icon;
}

/// All built-in effects in display order.
///
/// Note: [BI] glyphs are static getters (not compile-time const), so this list
/// cannot be a `const`. Use it as a plain final / read-only list.
final List<BuiltinEffectInfo> builtinEffects = [
  BuiltinEffectInfo(type: 'eq', name: 'EQ', icon: BI.equalizer),
  BuiltinEffectInfo(type: 'compressor', name: 'Compressor', icon: BI.compress),
  BuiltinEffectInfo(type: 'reverb', name: 'Reverb', icon: BI.waveSine),
  BuiltinEffectInfo(type: 'delay', name: 'Delay', icon: BI.metronome),
  BuiltinEffectInfo(type: 'chorus', name: 'Chorus', icon: BI.waveform),
  BuiltinEffectInfo(
    type: 'limiter',
    name: 'Limiter',
    icon: BI.arrowsHorizontal,
  ),
];
