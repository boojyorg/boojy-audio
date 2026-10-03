import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/audio_clip_edit_data.dart';
import 'package:boojy_audio/models/clip_data.dart';
import 'package:boojy_audio/models/instrument_data.dart';
import 'package:boojy_audio/models/midi_event.dart';
import 'package:boojy_audio/models/project_metadata.dart';
import 'package:boojy_audio/models/project_view_state.dart';
import 'package:boojy_audio/models/track_automation_data.dart';
import 'package:boojy_audio/models/track_data.dart';

void main() {
  // =========================================================================
  // AudioClipEditData
  // =========================================================================
  group('AudioClipEditData roundtrip', () {
    test('with all non-default values', () {
      const original = AudioClipEditData(
        loopEnabled: false,
        startOffsetBeats: 2.5,
        lengthBeats: 8.0,
        beatsPerBar: 3,
        beatUnit: 8,
        bpm: 140.0,
        syncEnabled: true,
        transposeSemitones: -5,
        fineCents: 25,
        gainDb: -3.5,
        isStereo: false,
        reversed: true,
        normalizeTargetDb: -6.0,
        loopStartBeats: 1.0,
        loopEndBeats: 7.0,
      );
      final json = original.toJson();
      final restored = AudioClipEditData.fromJson(json);
      expect(restored, equals(original));
    });

    test('with default values', () {
      const original = AudioClipEditData();
      final json = original.toJson();
      final restored = AudioClipEditData.fromJson(json);
      expect(restored, equals(original));
    });

    test('with null normalizeTargetDb', () {
      const original = AudioClipEditData(normalizeTargetDb: null);
      final json = original.toJson();
      final restored = AudioClipEditData.fromJson(json);
      expect(restored.normalizeTargetDb, isNull);
      expect(restored, equals(original));
    });
  });

  // =========================================================================
  // ClipData (no == override, compare field-by-field)
  // =========================================================================
  group('ClipData roundtrip', () {
    test('with all fields populated', () {
      const editData = AudioClipEditData(
        loopEnabled: false,
        bpm: 140.0,
        transposeSemitones: 3,
        reversed: true,
        gainDb: -2.0,
      );
      final original = ClipData(
        clipId: 42,
        trackId: 3,
        filePath: '/path/to/audio.wav',
        startTime: 5.5,
        duration: 10.0,
        offset: 1.5,
        waveformPeaks: [0.1, 0.5, 0.8, 0.3],
        color: const Color(0xFFFF5500),
        editData: editData,
        loopLength: 8.0,
        canRepeat: false,
      );

      final json = original.toJson();
      final restored = ClipData.fromJson(json);

      expect(restored.clipId, equals(42));
      expect(restored.trackId, equals(3));
      expect(restored.filePath, equals('/path/to/audio.wav'));
      expect(restored.startTime, equals(5.5));
      expect(restored.duration, equals(10.0));
      expect(restored.offset, equals(1.5));
      // Peaks are recomputed from the audio on load, never written to the file.
      expect(json.containsKey('waveformPeaks'), isFalse);
      expect(restored.waveformPeaks, isEmpty);
      expect(restored.color, equals(const Color(0xFFFF5500)));
      expect(restored.editData, equals(editData));
      expect(restored.loopLength, equals(8.0));
      expect(restored.canRepeat, isFalse);
    });

    test('still reads waveformPeaks written by older builds', () {
      final json = ClipData(
        clipId: 1,
        trackId: 0,
        filePath: 'test.wav',
        startTime: 0.0,
        duration: 4.0,
      ).toJson();
      json['waveformPeaks'] = [0.25, 0.75];

      final restored = ClipData.fromJson(json);

      expect(restored.waveformPeaks, equals([0.25, 0.75]));
      expect(restored.toJson().containsKey('waveformPeaks'), isFalse);
    });

    test('ignores an old clip-automation key', () {
      final json = ClipData(
        clipId: 1,
        trackId: 0,
        filePath: 'test.wav',
        startTime: 0.0,
        duration: 4.0,
      ).toJson();
      json['automation'] = {
        'lanes': {
          'volume': {
            'id': 'old',
            'parameter': 'volume',
            'points': [
              {'id': 'p', 'time': 0.0, 'value': 0.5},
            ],
          },
        },
      };

      final restored = ClipData.fromJson(json);

      expect(restored.clipId, equals(1));
      expect(restored.duration, equals(4.0));
      expect(restored.toJson().containsKey('automation'), isFalse);
    });

    test('with minimal/null optional fields', () {
      final original = ClipData(
        clipId: 1,
        trackId: 0,
        filePath: 'test.wav',
        startTime: 0.0,
        duration: 4.0,
      );

      final json = original.toJson();
      final restored = ClipData.fromJson(json);

      expect(restored.clipId, equals(1));
      expect(restored.trackId, equals(0));
      expect(restored.filePath, equals('test.wav'));
      expect(restored.startTime, equals(0.0));
      expect(restored.duration, equals(4.0));
      expect(restored.offset, equals(0.0));
      expect(restored.waveformPeaks, isEmpty);
      expect(restored.color, isNull);
      expect(restored.editData, isNull);
      expect(restored.loopLength, equals(4.0)); // defaults to duration
      expect(restored.canRepeat, isTrue);
    });
  });

  // =========================================================================
  // ProjectMetadata
  // =========================================================================
  group('ProjectMetadata roundtrip', () {
    test('with all fields', () {
      final created = DateTime(2025, 6, 15, 10, 30, 0);
      final modified = DateTime(2025, 6, 16, 14, 0, 0);
      final original = ProjectMetadata(
        name: 'My Beat',
        bpm: 145.0,
        timeSignatureNumerator: 3,
        timeSignatureDenominator: 4,
        createdDate: created,
        lastModified: modified,
      );

      final json = original.toJson();
      final restored = ProjectMetadata.fromJson(json);
      expect(restored, equals(original));
    });

    test('with null optional fields', () {
      const original = ProjectMetadata(name: 'Untitled');

      final json = original.toJson();
      final restored = ProjectMetadata.fromJson(json);
      expect(restored, equals(original));
      expect(restored.createdDate, isNull);
      expect(restored.lastModified, isNull);
    });
  });

  // =========================================================================
  // ProjectViewState
  // =========================================================================
  group('ProjectViewState roundtrip', () {
    test('with all non-default values', () {
      const original = ProjectViewState(
        horizontalScroll: 150.0,
        verticalScroll: 75.0,
        zoom: 2.5,
        libraryVisible: false,
        mixerVisible: true,
        editorVisible: false,
        virtualPianoVisible: true,
        selectedTrackId: 7,
        playheadPosition: 32.0,
      );

      final json = original.toJson();
      final restored = ProjectViewState.fromJson(json);
      expect(restored, equals(original));
    });

    test('with null selectedTrackId', () {
      const original = ProjectViewState(selectedTrackId: null);

      final json = original.toJson();
      final restored = ProjectViewState.fromJson(json);
      expect(restored, equals(original));
      expect(restored.selectedTrackId, isNull);
    });

    test('default state roundtrip', () {
      final original = ProjectViewState.defaultState();
      final json = original.toJson();
      final restored = ProjectViewState.fromJson(json);
      expect(restored, equals(original));
    });
  });

  // =========================================================================
  // MidiEvent
  // =========================================================================
  group('MidiEvent roundtrip', () {
    test('note on event', () {
      final timestamp = DateTime(2025, 6, 15, 12, 0, 0, 500);
      final original = MidiEvent(
        note: 60,
        velocity: 100,
        isNoteOn: true,
        timestamp: timestamp,
        beatsFromStart: 4.5,
      );

      final json = original.toJson();
      final restored = MidiEvent.fromJson(json);
      expect(restored, equals(original));
    });

    test('note off event', () {
      final timestamp = DateTime(2025, 6, 15, 12, 0, 1, 200);
      final original = MidiEvent(
        note: 72,
        velocity: 0,
        isNoteOn: false,
        timestamp: timestamp,
        beatsFromStart: 8.0,
      );

      final json = original.toJson();
      final restored = MidiEvent.fromJson(json);
      expect(restored, equals(original));
    });
  });

  // =========================================================================
  // AutomationPoint (track_automation_data.dart)
  // =========================================================================
  group('AutomationPoint roundtrip', () {
    test('with explicit id', () {
      final original = AutomationPoint(id: 'ap-001', time: 8.25, value: 0.65);

      final json = original.toJson();
      final restored = AutomationPoint.fromJson(json);
      expect(restored.id, equals(original.id));
      expect(restored.time, equals(original.time));
      expect(restored.value, equals(original.value));
      // Note: isSelected is not serialized (transient UI state)
    });
  });

  // =========================================================================
  // TrackAutomationLane
  // =========================================================================
  group('TrackAutomationLane roundtrip', () {
    test('with points and all fields', () {
      final original = TrackAutomationLane(
        id: 'tal-1',
        trackId: 5,
        parameter: AutomationParameter.pan,
        points: [
          AutomationPoint(id: 'tap1', time: 0.0, value: 0.0),
          AutomationPoint(id: 'tap2', time: 4.0, value: -0.8),
          AutomationPoint(id: 'tap3', time: 8.0, value: 0.5),
        ],
        isExpanded: false,
      );

      final json = original.toJson();
      final restored = TrackAutomationLane.fromJson(json);
      expect(restored.id, equals(original.id));
      expect(restored.trackId, equals(original.trackId));
      expect(restored.parameter, equals(original.parameter));
      expect(restored.isExpanded, equals(original.isExpanded));
      expect(restored.points.length, equals(3));
      for (int i = 0; i < original.points.length; i++) {
        expect(restored.points[i].id, equals(original.points[i].id));
        expect(restored.points[i].time, equals(original.points[i].time));
        expect(restored.points[i].value, equals(original.points[i].value));
      }
    });

    test('empty lane', () {
      final original = TrackAutomationLane(
        id: 'tal-empty',
        trackId: 2,
        parameter: AutomationParameter.volume,
        points: const [],
        isExpanded: true,
      );

      final json = original.toJson();
      final restored = TrackAutomationLane.fromJson(json);
      expect(restored.points, isEmpty);
      expect(restored.isExpanded, isTrue);
    });
  });

  // =========================================================================
  // InstrumentData (no == override, compare field-by-field)
  // =========================================================================
  group('InstrumentData roundtrip', () {
    test('synthesizer with parameters', () {
      final original = InstrumentData(
        trackId: 2,
        type: 'synthesizer',
        parameters: {
          'osc1_type': 'saw',
          'osc1_level': 0.8,
          'filter_cutoff': 0.65,
          'env_attack': 0.05,
          'env_release': 0.3,
        },
      );

      final json = original.toJson();
      final restored = InstrumentData.fromJson(json);
      expect(restored.trackId, equals(original.trackId));
      expect(restored.type, equals(original.type));
      expect(restored.parameters, equals(original.parameters));
      expect(restored.pluginPath, isNull);
      expect(restored.pluginName, isNull);
      expect(restored.effectId, isNull);
    });

    test('VST3 instrument with all optional fields', () {
      final original = InstrumentData(
        trackId: 5,
        type: 'vst3',
        parameters: {},
        pluginPath: '/Library/Audio/Plug-Ins/VST3/Serum.vst3',
        pluginName: 'Serum',
        effectId: 42,
      );

      final json = original.toJson();
      final restored = InstrumentData.fromJson(json);
      expect(restored.trackId, equals(original.trackId));
      expect(restored.type, equals(original.type));
      expect(restored.parameters, equals(original.parameters));
      expect(restored.pluginPath, equals(original.pluginPath));
      expect(restored.pluginName, equals(original.pluginName));
      expect(restored.effectId, equals(original.effectId));
    });

    test('default synthesizer factory', () {
      final original = InstrumentData.defaultSynthesizer(1);
      final json = original.toJson();
      final restored = InstrumentData.fromJson(json);
      expect(restored.trackId, equals(1));
      expect(restored.type, equals('synthesizer'));
      expect(restored.parameters.length, equals(original.parameters.length));
      for (final key in original.parameters.keys) {
        expect(
          restored.parameters[key],
          equals(original.parameters[key]),
          reason: 'Parameter "$key" mismatch',
        );
      }
    });
  });

  // =========================================================================
  // TrackData CSV roundtrip (no == override, compare field-by-field)
  // =========================================================================
  group('TrackData CSV roundtrip', () {
    test('full 10-field format', () {
      final original = TrackData(
        id: 3,
        name: 'Drums',
        type: 'audio',
        volumeDb: -6.5,
        pan: 0.3,
        mute: true,
        solo: false,
        armed: true,
        inputDeviceIndex: 2,
        inputChannel: 1,
      );

      final csv = original.toCSV();
      final restored = TrackData.fromCSV(csv);
      expect(restored, isNotNull);
      expect(restored!.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.type, equals(original.type));
      expect(restored.volumeDb, equals(original.volumeDb));
      expect(restored.pan, equals(original.pan));
      expect(restored.mute, equals(original.mute));
      expect(restored.solo, equals(original.solo));
      expect(restored.armed, equals(original.armed));
      expect(restored.inputDeviceIndex, equals(original.inputDeviceIndex));
      expect(restored.inputChannel, equals(original.inputChannel));
    });

    test('with default input routing', () {
      final original = TrackData(
        id: 0,
        name: 'Bass',
        type: 'midi',
        volumeDb: 0.0,
        pan: 0.0,
        mute: false,
        solo: true,
        armed: false,
        inputDeviceIndex: -1,
        inputChannel: 0,
      );

      final csv = original.toCSV();
      final restored = TrackData.fromCSV(csv);
      expect(restored, isNotNull);
      expect(restored!.id, equals(0));
      expect(restored.name, equals('Bass'));
      expect(restored.type, equals('midi'));
      expect(restored.volumeDb, equals(0.0));
      expect(restored.pan, equals(0.0));
      expect(restored.mute, isFalse);
      expect(restored.solo, isTrue);
      expect(restored.armed, isFalse);
      expect(restored.inputDeviceIndex, equals(-1));
      expect(restored.inputChannel, equals(0));
    });
  });

  // =========================================================================
  // Deep nesting: ClipData with full edit data
  // =========================================================================
  group('Deep nesting roundtrip', () {
    test('ClipData -> AudioClipEditData', () {
      final original = ClipData(
        clipId: 99,
        trackId: 7,
        filePath: '/deep/nested/test.wav',
        startTime: 10.0,
        duration: 20.0,
        offset: 2.0,
        waveformPeaks: [0.1, 0.9],
        color: const Color(0xFF00AAFF),
        editData: const AudioClipEditData(
          bpm: 128.0,
          reversed: true,
          transposeSemitones: -12,
          syncEnabled: true,
          normalizeTargetDb: -3.0,
          loopStartBeats: 2.0,
          loopEndBeats: 14.0,
        ),
        loopLength: 16.0,
        canRepeat: true,
      );

      final json = original.toJson();
      final restored = ClipData.fromJson(json);

      // Top level
      expect(restored.clipId, equals(99));
      expect(restored.trackId, equals(7));
      expect(restored.filePath, equals('/deep/nested/test.wav'));
      expect(restored.startTime, equals(10.0));
      expect(restored.duration, equals(20.0));
      expect(restored.offset, equals(2.0));
      expect(restored.waveformPeaks, isEmpty);
      expect(restored.color, equals(const Color(0xFF00AAFF)));
      expect(restored.loopLength, equals(16.0));
      expect(restored.canRepeat, isTrue);

      // EditData
      expect(restored.editData, isNotNull);
      expect(restored.editData!.bpm, equals(128.0));
      expect(restored.editData!.reversed, isTrue);
      expect(restored.editData!.transposeSemitones, equals(-12));
      expect(restored.editData!.syncEnabled, isTrue);
      expect(restored.editData!.normalizeTargetDb, equals(-3.0));
      expect(restored.editData!.loopStartBeats, equals(2.0));
      expect(restored.editData!.loopEndBeats, equals(14.0));
    });
  });
}
