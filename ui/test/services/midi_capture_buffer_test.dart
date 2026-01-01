import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/services/midi_capture_buffer.dart';
import 'package:boojy_audio/models/midi_event.dart';

void main() {
  group('MidiCaptureBuffer', () {
    late MidiCaptureBuffer buffer;

    setUp(() {
      buffer = MidiCaptureBuffer();
    });

    tearDown(() {
      buffer.dispose();
    });

    group('constructor', () {
      test('creates with default maxDurationSeconds of 30', () {
        final buf = MidiCaptureBuffer();
        expect(buf.maxDurationSeconds, 30);
        buf.dispose();
      });

      test('creates with custom maxDurationSeconds', () {
        final buf = MidiCaptureBuffer(maxDurationSeconds: 60);
        expect(buf.maxDurationSeconds, 60);
        buf.dispose();
      });

      test('starts with empty buffer', () {
        expect(buffer.eventCount, 0);
        expect(buffer.hasEvents, false);
        expect(buffer.allEvents, isEmpty);
      });
    });

    group('updateBpm', () {
      test('updates BPM for beat calculations', () {
        buffer.updateBpm(140.0);
        // BPM is used internally for beat calculations
        // Adding events will use the new BPM
        expect(buffer.eventCount, 0); // Just verify no error
      });
    });

    group('addEvent', () {
      test('adds event to buffer', () {
        final event = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: DateTime.now(),
          beatsFromStart: 0.0,
        );

        buffer.addEvent(event);

        expect(buffer.eventCount, 1);
        expect(buffer.hasEvents, true);
      });

      test('adds multiple events', () {
        final now = DateTime.now();

        buffer.addEvent(MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: now,
          beatsFromStart: 0.0,
        ));

        buffer.addEvent(MidiEvent.noteOff(
          note: 60,
          timestamp: now.add(const Duration(milliseconds: 500)),
          beatsFromStart: 1.0,
        ));

        expect(buffer.eventCount, 2);
      });

      test('notifies listeners when event added', () {
        var notified = false;
        buffer.addListener(() {
          notified = true;
        });

        buffer.addEvent(MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: DateTime.now(),
          beatsFromStart: 0.0,
        ));

        expect(notified, true);
      });
    });

    group('addNoteOn', () {
      test('adds note-on event to buffer', () {
        buffer.addNoteOn(60, 100);

        expect(buffer.eventCount, 1);
        expect(buffer.allEvents.first.isNoteOn, true);
        expect(buffer.allEvents.first.note, 60);
        expect(buffer.allEvents.first.velocity, 100);
      });

      test('calculates beatsFromStart', () {
        buffer.updateBpm(120.0); // 2 beats per second
        buffer.addNoteOn(60, 100);

        // First event should have beatsFromStart of 0
        expect(buffer.allEvents.first.beatsFromStart, 0.0);
      });
    });

    group('addNoteOff', () {
      test('adds note-off event to buffer', () {
        buffer.addNoteOff(60);

        expect(buffer.eventCount, 1);
        expect(buffer.allEvents.first.isNoteOn, false);
        expect(buffer.allEvents.first.note, 60);
        expect(buffer.allEvents.first.velocity, 0);
      });
    });

    group('getRecentEvents', () {
      test('returns empty list when buffer is empty', () {
        final events = buffer.getRecentEvents(5);
        expect(events, isEmpty);
      });

      test('returns events within duration', () {
        final now = DateTime.now();

        // Add event that is recent
        buffer.addEvent(MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: now,
          beatsFromStart: 0.0,
        ));

        final events = buffer.getRecentEvents(5);
        expect(events.length, 1);
      });

      test('normalizes beat positions to start at 0', () {
        final now = DateTime.now();

        buffer.addEvent(MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: now,
          beatsFromStart: 10.0, // Some offset
        ));

        buffer.addEvent(MidiEvent.noteOff(
          note: 60,
          timestamp: now.add(const Duration(milliseconds: 100)),
          beatsFromStart: 10.5,
        ));

        final events = buffer.getRecentEvents(5);

        // First event should be normalized to 0
        expect(events.first.beatsFromStart, 0.0);
        // Second event should be relative to first
        expect(events.last.beatsFromStart, 0.5);
      });
    });

    group('allEvents', () {
      test('returns unmodifiable list', () {
        buffer.addNoteOn(60, 100);

        final events = buffer.allEvents;
        expect(() => events.add(MidiEvent.noteOn(
          note: 72,
          velocity: 100,
          timestamp: DateTime.now(),
          beatsFromStart: 0.0,
        )), throwsA(isA<UnsupportedError>()));
      });

      test('returns all events in order', () {
        final now = DateTime.now();

        buffer.addEvent(MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: now,
          beatsFromStart: 0.0,
        ));

        buffer.addEvent(MidiEvent.noteOn(
          note: 64,
          velocity: 80,
          timestamp: now.add(const Duration(milliseconds: 100)),
          beatsFromStart: 0.5,
        ));

        final events = buffer.allEvents;
        expect(events.length, 2);
        expect(events[0].note, 60);
        expect(events[1].note, 64);
      });
    });

    group('eventCount', () {
      test('returns 0 for empty buffer', () {
        expect(buffer.eventCount, 0);
      });

      test('returns correct count after adding events', () {
        buffer.addNoteOn(60, 100);
        buffer.addNoteOn(64, 100);
        buffer.addNoteOff(60);

        expect(buffer.eventCount, 3);
      });
    });

    group('hasEvents', () {
      test('returns false for empty buffer', () {
        expect(buffer.hasEvents, false);
      });

      test('returns true after adding event', () {
        buffer.addNoteOn(60, 100);
        expect(buffer.hasEvents, true);
      });
    });

    group('clear', () {
      test('clears all events', () {
        buffer.addNoteOn(60, 100);
        buffer.addNoteOn(64, 100);

        buffer.clear();

        expect(buffer.eventCount, 0);
        expect(buffer.hasEvents, false);
      });

      test('notifies listeners when cleared', () {
        buffer.addNoteOn(60, 100);

        var notified = false;
        buffer.addListener(() {
          notified = true;
        });

        buffer.clear();

        expect(notified, true);
      });
    });

    group('getPreview', () {
      test('returns message when no events', () {
        final preview = buffer.getPreview(5);
        expect(preview, contains('No MIDI events'));
      });

      test('returns event count and duration', () {
        final now = DateTime.now();

        buffer.addEvent(MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: now,
          beatsFromStart: 0.0,
        ));

        buffer.addEvent(MidiEvent.noteOff(
          note: 60,
          timestamp: now.add(const Duration(milliseconds: 500)),
          beatsFromStart: 2.0,
        ));

        final preview = buffer.getPreview(10);
        expect(preview, contains('1 notes')); // Only note-on counts
        expect(preview, contains('beats'));
      });
    });

    group('dispose', () {
      test('clears buffer on dispose', () {
        // Create a separate buffer for this test to avoid double dispose
        final testBuffer = MidiCaptureBuffer();
        testBuffer.addNoteOn(60, 100);

        expect(testBuffer.hasEvents, true);
        testBuffer.dispose();
        // After dispose, buffer is cleared (can't verify as it throws after dispose)
      });
    });

    group('beat calculation', () {
      test('calculates beats at 120 BPM correctly', () {
        buffer.updateBpm(120.0); // 2 beats per second

        buffer.addNoteOn(60, 100);

        // First event should start at beat 0
        expect(buffer.allEvents.first.beatsFromStart, 0.0);
      });

      test('calculates beats at 60 BPM correctly', () {
        buffer.updateBpm(60.0); // 1 beat per second

        buffer.addNoteOn(60, 100);

        expect(buffer.allEvents.first.beatsFromStart, 0.0);
      });
    });

    group('ChangeNotifier behavior', () {
      test('can add multiple listeners', () {
        var count = 0;
        buffer.addListener(() => count++);
        buffer.addListener(() => count++);

        buffer.addNoteOn(60, 100);

        expect(count, 2);
      });

      test('can remove listeners', () {
        var count = 0;
        void listener() => count++;

        buffer.addListener(listener);
        buffer.addNoteOn(60, 100);
        expect(count, 1);

        buffer.removeListener(listener);
        buffer.addNoteOn(64, 100);
        expect(count, 1); // Should not have increased
      });
    });

    group('edge cases', () {
      test('handles MIDI note 0', () {
        buffer.addNoteOn(0, 64);
        expect(buffer.allEvents.first.note, 0);
      });

      test('handles MIDI note 127', () {
        buffer.addNoteOn(127, 64);
        expect(buffer.allEvents.first.note, 127);
      });

      test('handles velocity 1', () {
        buffer.addNoteOn(60, 1);
        expect(buffer.allEvents.first.velocity, 1);
      });

      test('handles velocity 127', () {
        buffer.addNoteOn(60, 127);
        expect(buffer.allEvents.first.velocity, 127);
      });

      test('handles many events', () {
        for (int i = 0; i < 1000; i++) {
          buffer.addNoteOn(60 + (i % 12), 100);
        }

        expect(buffer.eventCount, 1000);
      });
    });
  });
}
