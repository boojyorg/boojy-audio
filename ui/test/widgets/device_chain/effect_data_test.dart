import 'package:boojy_audio/widgets/device_chain/effect_data.dart';
import 'package:flutter_test/flutter_test.dart';

// The engine's get_effect_info strings (engine/src/api/effects.rs).
void main() {
  group('EffectData.fromInfo', () {
    test('a VST3 effect shows up with its name and plugin path', () {
      final effect = EffectData.fromInfo(
        7,
        'type:vst3,bypassed:0,name:Supermassive,'
        'path:/Library/Audio/Plug-Ins/VST3/ValhallaSupermassive.vst3',
      );

      expect(effect, isNotNull);
      expect(effect!.isVst3, isTrue);
      expect(effect.type, 'vst3:Supermassive');
      expect(
        effect.pluginPath,
        '/Library/Audio/Plug-Ins/VST3/ValhallaSupermassive.vst3',
      );
      expect(effect.bypassed, isFalse);
      expect(effect.parameters, isEmpty);
    });

    test('a Windows plugin path keeps its drive letter and commas', () {
      final effect = EffectData.fromInfo(
        7,
        r'type:vst3,bypassed:1,name:Pro-Q 3,path:C:\Program Files\Common '
        r'Files\VST3\Pro-Q 3, Copy.vst3',
      );

      expect(effect, isNotNull);
      expect(effect!.type, 'vst3:Pro-Q 3');
      expect(
        effect.pluginPath,
        r'C:\Program Files\Common Files\VST3\Pro-Q 3, Copy.vst3',
      );
      expect(effect.bypassed, isTrue);
    });

    test('a name with a colon stays whole', () {
      final effect = EffectData.fromInfo(
        7,
        'type:vst3,bypassed:0,name:Comp: Bus,path:/p/Comp.vst3',
      );

      expect(effect!.type, 'vst3:Comp: Bus');
    });

    test('a built-in effect reads its parameters as numbers', () {
      final effect = EffectData.fromInfo(
        3,
        'type:reverb,bypassed:1,room_size:0.5,damping:0.25,wet_dry:0.3',
      );

      expect(effect, isNotNull);
      expect(effect!.isVst3, isFalse);
      expect(effect.type, 'reverb');
      expect(effect.pluginPath, isNull);
      expect(effect.bypassed, isTrue);
      expect(effect.parameters, {
        'room_size': 0.5,
        'damping': 0.25,
        'wet_dry': 0.3,
      });
    });

    test('an unknown effect or an empty reply gives nothing', () {
      expect(EffectData.fromInfo(1, ''), isNull);
      expect(EffectData.fromInfo(1, 'bypassed:0'), isNull);
      expect(EffectData.fromInfo(1, 'type:vst3,bypassed:0,name:X'), isNull);
    });
  });
}
