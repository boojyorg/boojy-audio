import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/constants/ui_constants.dart';

void main() {
  group('UIConstants MIDI', () {
    test('defaultMidiVelocity is in valid MIDI range', () {
      expect(UIConstants.defaultMidiVelocity, greaterThanOrEqualTo(0));
      expect(UIConstants.defaultMidiVelocity, lessThanOrEqualTo(127));
    });

    test('midiNoteOffVelocity is in valid MIDI range', () {
      expect(UIConstants.midiNoteOffVelocity, greaterThanOrEqualTo(0));
      expect(UIConstants.midiNoteOffVelocity, lessThanOrEqualTo(127));
    });

    test('maxMidiNote is 127', () {
      expect(UIConstants.maxMidiNote, equals(127));
    });

    test('minMidiNote is 0', () {
      expect(UIConstants.minMidiNote, equals(0));
    });

    test('MIDI note range is valid', () {
      expect(UIConstants.minMidiNote, lessThan(UIConstants.maxMidiNote));
    });
  });

  group('UIConstants scroll thresholds', () {
    test('playheadScrollThreshold is between 0 and 1', () {
      expect(UIConstants.playheadScrollThreshold, greaterThan(0));
      expect(UIConstants.playheadScrollThreshold, lessThan(1));
    });

    test('playheadScrollOffset is between 0 and 1', () {
      expect(UIConstants.playheadScrollOffset, greaterThan(0));
      expect(UIConstants.playheadScrollOffset, lessThan(1));
    });
  });

  group('UIConstants track dimensions', () {
    test('trackMinHeight is less than trackMaxHeight', () {
      expect(UIConstants.trackMinHeight, lessThan(UIConstants.trackMaxHeight));
    });

    test('defaultClipHeight is within track height range', () {
      expect(UIConstants.defaultClipHeight, greaterThanOrEqualTo(UIConstants.trackMinHeight));
      expect(UIConstants.defaultClipHeight, lessThanOrEqualTo(UIConstants.trackMaxHeight));
    });

    test('zoom min is less than zoom max', () {
      expect(UIConstants.timelineMinZoom, lessThan(UIConstants.timelineMaxZoom));
    });
  });
}
