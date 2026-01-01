import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/instrument_data.dart';

void main() {
  group('InstrumentData', () {
    group('constructor', () {
      test('creates instance with required fields', () {
        final instrument = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {'volume': 0.8},
        );

        expect(instrument.trackId, 1);
        expect(instrument.type, 'synthesizer');
        expect(instrument.parameters, {'volume': 0.8});
      });

      test('creates instance with all optional fields', () {
        final instrument = InstrumentData(
          trackId: 2,
          type: 'vst3',
          parameters: {},
          pluginPath: '/Library/Audio/Plug-Ins/VST3/Serum.vst3',
          pluginName: 'Serum',
          effectId: 42,
        );

        expect(instrument.pluginPath, '/Library/Audio/Plug-Ins/VST3/Serum.vst3');
        expect(instrument.pluginName, 'Serum');
        expect(instrument.effectId, 42);
      });

      test('optional fields default to null', () {
        final instrument = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {},
        );

        expect(instrument.pluginPath, isNull);
        expect(instrument.pluginName, isNull);
        expect(instrument.effectId, isNull);
      });
    });

    group('defaultSynthesizer factory', () {
      test('creates synthesizer with correct type', () {
        final synth = InstrumentData.defaultSynthesizer(5);

        expect(synth.trackId, 5);
        expect(synth.type, 'synthesizer');
      });

      test('has oscillator 1 parameters', () {
        final synth = InstrumentData.defaultSynthesizer(1);

        expect(synth.parameters['osc1_type'], 'saw');
        expect(synth.parameters['osc1_level'], 0.8);
        expect(synth.parameters['osc1_detune'], 0.0);
      });

      test('has oscillator 2 parameters', () {
        final synth = InstrumentData.defaultSynthesizer(1);

        expect(synth.parameters['osc2_type'], 'square');
        expect(synth.parameters['osc2_level'], 0.4);
        expect(synth.parameters['osc2_detune'], 7.0);
      });

      test('has filter parameters', () {
        final synth = InstrumentData.defaultSynthesizer(1);

        expect(synth.parameters['filter_type'], 'lowpass');
        expect(synth.parameters['filter_cutoff'], 0.8);
        expect(synth.parameters['filter_resonance'], 0.2);
      });

      test('has envelope parameters', () {
        final synth = InstrumentData.defaultSynthesizer(1);

        expect(synth.parameters['env_attack'], 0.01);
        expect(synth.parameters['env_decay'], 0.1);
        expect(synth.parameters['env_sustain'], 0.7);
        expect(synth.parameters['env_release'], 0.3);
      });

      test('is not VST3', () {
        final synth = InstrumentData.defaultSynthesizer(1);
        expect(synth.isVst3, false);
      });
    });

    group('vst3Instrument factory', () {
      test('creates VST3 instrument with correct type', () {
        final vst = InstrumentData.vst3Instrument(
          trackId: 3,
          pluginPath: '/path/to/plugin.vst3',
          pluginName: 'Test Plugin',
        );

        expect(vst.trackId, 3);
        expect(vst.type, 'vst3');
      });

      test('sets plugin path and name', () {
        final vst = InstrumentData.vst3Instrument(
          trackId: 3,
          pluginPath: '/Library/Audio/Plug-Ins/VST3/Diva.vst3',
          pluginName: 'Diva',
        );

        expect(vst.pluginPath, '/Library/Audio/Plug-Ins/VST3/Diva.vst3');
        expect(vst.pluginName, 'Diva');
      });

      test('sets effectId when provided', () {
        final vst = InstrumentData.vst3Instrument(
          trackId: 3,
          pluginPath: '/path/to/plugin.vst3',
          pluginName: 'Test',
          effectId: 99,
        );

        expect(vst.effectId, 99);
      });

      test('has empty parameters', () {
        final vst = InstrumentData.vst3Instrument(
          trackId: 3,
          pluginPath: '/path/to/plugin.vst3',
          pluginName: 'Test',
        );

        expect(vst.parameters, isEmpty);
      });

      test('is VST3', () {
        final vst = InstrumentData.vst3Instrument(
          trackId: 3,
          pluginPath: '/path/to/plugin.vst3',
          pluginName: 'Test',
        );

        expect(vst.isVst3, true);
      });
    });

    group('getParameter', () {
      test('returns existing parameter with correct type', () {
        final instrument = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {
            'volume': 0.75,
            'name': 'Lead',
            'enabled': true,
          },
        );

        expect(instrument.getParameter<double>('volume', 0.0), 0.75);
        expect(instrument.getParameter<String>('name', ''), 'Lead');
        expect(instrument.getParameter<bool>('enabled', false), true);
      });

      test('returns default when parameter missing', () {
        final instrument = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {},
        );

        expect(instrument.getParameter<double>('volume', 0.5), 0.5);
        expect(instrument.getParameter<String>('name', 'default'), 'default');
      });

      test('returns default when type mismatch', () {
        final instrument = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {'volume': 'not a number'},
        );

        expect(instrument.getParameter<double>('volume', 0.5), 0.5);
      });
    });

    group('updateParameter', () {
      test('returns new instance with updated parameter', () {
        final original = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {'volume': 0.5},
        );

        final updated = original.updateParameter('volume', 0.8);

        expect(updated.parameters['volume'], 0.8);
        expect(original.parameters['volume'], 0.5); // Original unchanged
      });

      test('preserves other fields', () {
        final original = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {'volume': 0.5, 'pan': 0.0},
        );

        final updated = original.updateParameter('volume', 0.8);

        expect(updated.trackId, 1);
        expect(updated.type, 'synthesizer');
        expect(updated.parameters['pan'], 0.0);
      });

      test('adds new parameter', () {
        final original = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {},
        );

        final updated = original.updateParameter('newParam', 123);

        expect(updated.parameters['newParam'], 123);
      });
    });

    group('toJson', () {
      test('serializes required fields', () {
        final instrument = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {'volume': 0.8},
        );

        final json = instrument.toJson();

        expect(json['trackId'], 1);
        expect(json['type'], 'synthesizer');
        expect(json['parameters'], {'volume': 0.8});
      });

      test('serializes optional fields when present', () {
        final instrument = InstrumentData(
          trackId: 2,
          type: 'vst3',
          parameters: {},
          pluginPath: '/path/to/plugin.vst3',
          pluginName: 'Test Plugin',
          effectId: 42,
        );

        final json = instrument.toJson();

        expect(json['pluginPath'], '/path/to/plugin.vst3');
        expect(json['pluginName'], 'Test Plugin');
        expect(json['effectId'], 42);
      });

      test('omits null optional fields', () {
        final instrument = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {},
        );

        final json = instrument.toJson();

        expect(json.containsKey('pluginPath'), false);
        expect(json.containsKey('pluginName'), false);
        expect(json.containsKey('effectId'), false);
      });
    });

    group('fromJson', () {
      test('deserializes required fields', () {
        final json = {
          'trackId': 1,
          'type': 'synthesizer',
          'parameters': {'volume': 0.8},
        };

        final instrument = InstrumentData.fromJson(json);

        expect(instrument.trackId, 1);
        expect(instrument.type, 'synthesizer');
        expect(instrument.parameters['volume'], 0.8);
      });

      test('deserializes optional fields', () {
        final json = {
          'trackId': 2,
          'type': 'vst3',
          'parameters': {},
          'pluginPath': '/path/to/plugin.vst3',
          'pluginName': 'Test Plugin',
          'effectId': 42,
        };

        final instrument = InstrumentData.fromJson(json);

        expect(instrument.pluginPath, '/path/to/plugin.vst3');
        expect(instrument.pluginName, 'Test Plugin');
        expect(instrument.effectId, 42);
      });

      test('handles missing optional fields', () {
        final json = {
          'trackId': 1,
          'type': 'synthesizer',
          'parameters': {},
        };

        final instrument = InstrumentData.fromJson(json);

        expect(instrument.pluginPath, isNull);
        expect(instrument.pluginName, isNull);
        expect(instrument.effectId, isNull);
      });
    });

    group('JSON round-trip', () {
      test('preserves synthesizer data through round-trip', () {
        final original = InstrumentData.defaultSynthesizer(1);

        final json = original.toJson();
        final restored = InstrumentData.fromJson(json);

        expect(restored.trackId, original.trackId);
        expect(restored.type, original.type);
        expect(restored.parameters, original.parameters);
      });

      test('preserves VST3 data through round-trip', () {
        final original = InstrumentData.vst3Instrument(
          trackId: 3,
          pluginPath: '/path/to/plugin.vst3',
          pluginName: 'Serum',
          effectId: 42,
        );

        final json = original.toJson();
        final restored = InstrumentData.fromJson(json);

        expect(restored.trackId, original.trackId);
        expect(restored.type, original.type);
        expect(restored.pluginPath, original.pluginPath);
        expect(restored.pluginName, original.pluginName);
        expect(restored.effectId, original.effectId);
      });
    });

    group('copyWith', () {
      test('copies all fields when none specified', () {
        final original = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {'volume': 0.8},
          pluginPath: '/path',
          pluginName: 'Name',
          effectId: 42,
        );

        final copy = original.copyWith();

        expect(copy.trackId, original.trackId);
        expect(copy.type, original.type);
        expect(copy.parameters, original.parameters);
        expect(copy.pluginPath, original.pluginPath);
        expect(copy.pluginName, original.pluginName);
        expect(copy.effectId, original.effectId);
      });

      test('updates trackId only', () {
        final original = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {},
        );

        final copy = original.copyWith(trackId: 99);

        expect(copy.trackId, 99);
        expect(copy.type, 'synthesizer');
      });

      test('updates type only', () {
        final original = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {},
        );

        final copy = original.copyWith(type: 'sampler');

        expect(copy.type, 'sampler');
        expect(copy.trackId, 1);
      });

      test('updates parameters only', () {
        final original = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {'old': 1},
        );

        final copy = original.copyWith(parameters: {'new': 2});

        expect(copy.parameters, {'new': 2});
      });

      test('updates VST3 fields', () {
        final original = InstrumentData.vst3Instrument(
          trackId: 1,
          pluginPath: '/old/path',
          pluginName: 'Old',
          effectId: 1,
        );

        final copy = original.copyWith(
          pluginPath: '/new/path',
          pluginName: 'New',
          effectId: 99,
        );

        expect(copy.pluginPath, '/new/path');
        expect(copy.pluginName, 'New');
        expect(copy.effectId, 99);
      });
    });

    group('isVst3', () {
      test('returns true for vst3 type', () {
        final vst = InstrumentData(
          trackId: 1,
          type: 'vst3',
          parameters: {},
        );

        expect(vst.isVst3, true);
      });

      test('returns false for synthesizer type', () {
        final synth = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {},
        );

        expect(synth.isVst3, false);
      });

      test('returns false for other types', () {
        final other = InstrumentData(
          trackId: 1,
          type: 'sampler',
          parameters: {},
        );

        expect(other.isVst3, false);
      });
    });

    group('edge cases', () {
      test('handles empty parameters', () {
        final instrument = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {},
        );

        expect(instrument.parameters, isEmpty);
        expect(instrument.getParameter<double>('any', 0.5), 0.5);
      });

      test('handles complex parameter values', () {
        final instrument = InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {
            'list': [1, 2, 3],
            'nested': {'a': 1, 'b': 2},
          },
        );

        expect(instrument.parameters['list'], [1, 2, 3]);
        expect(instrument.parameters['nested'], {'a': 1, 'b': 2});
      });

      test('handles track ID 0', () {
        final instrument = InstrumentData(
          trackId: 0,
          type: 'synthesizer',
          parameters: {},
        );

        expect(instrument.trackId, 0);
      });

      test('handles very long plugin paths', () {
        final longPath = '/Library/Audio/Plug-Ins/VST3/${'a' * 500}/plugin.vst3';
        final vst = InstrumentData.vst3Instrument(
          trackId: 1,
          pluginPath: longPath,
          pluginName: 'Test',
        );

        expect(vst.pluginPath, longPath);
      });
    });
  });
}
