import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/midi_event.dart';

void main() {
  group('MidiEvent', () {
    final testTimestamp = DateTime(2025, 1, 1, 12, 0, 0);

    group('constructor', () {
      test('creates instance with all required fields', () {
        final event = MidiEvent(
          note: 60,
          velocity: 100,
          isNoteOn: true,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        expect(event.note, 60);
        expect(event.velocity, 100);
        expect(event.isNoteOn, true);
        expect(event.timestamp, testTimestamp);
        expect(event.beatsFromStart, 4.0);
      });

      test('creates note-off event with velocity 0', () {
        final event = MidiEvent(
          note: 64,
          velocity: 0,
          isNoteOn: false,
          timestamp: testTimestamp,
          beatsFromStart: 8.0,
        );

        expect(event.isNoteOn, false);
        expect(event.velocity, 0);
      });
    });

    group('noteOn factory', () {
      test('creates note-on event with isNoteOn true', () {
        final event = MidiEvent.noteOn(
          note: 72,
          velocity: 127,
          timestamp: testTimestamp,
          beatsFromStart: 2.5,
        );

        expect(event.note, 72);
        expect(event.velocity, 127);
        expect(event.isNoteOn, true);
        expect(event.timestamp, testTimestamp);
        expect(event.beatsFromStart, 2.5);
      });

      test('creates note-on with minimum velocity', () {
        final event = MidiEvent.noteOn(
          note: 48,
          velocity: 1,
          timestamp: testTimestamp,
          beatsFromStart: 0.0,
        );

        expect(event.velocity, 1);
        expect(event.isNoteOn, true);
      });

      test('creates note-on with maximum velocity', () {
        final event = MidiEvent.noteOn(
          note: 48,
          velocity: 127,
          timestamp: testTimestamp,
          beatsFromStart: 0.0,
        );

        expect(event.velocity, 127);
      });
    });

    group('noteOff factory', () {
      test('creates note-off event with isNoteOn false and velocity 0', () {
        final event = MidiEvent.noteOff(
          note: 60,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        expect(event.note, 60);
        expect(event.velocity, 0);
        expect(event.isNoteOn, false);
        expect(event.timestamp, testTimestamp);
        expect(event.beatsFromStart, 4.0);
      });

      test('creates note-off for different MIDI notes', () {
        for (final note in [0, 60, 127]) {
          final event = MidiEvent.noteOff(
            note: note,
            timestamp: testTimestamp,
            beatsFromStart: 1.0,
          );
          expect(event.note, note);
          expect(event.isNoteOn, false);
        }
      });
    });

    group('fromJson', () {
      test('parses valid JSON correctly', () {
        final json = {
          'note': 60,
          'velocity': 100,
          'isNoteOn': true,
          'timestamp': '2025-01-01T12:00:00.000',
          'beatsFromStart': 4.0,
        };

        final event = MidiEvent.fromJson(json);

        expect(event.note, 60);
        expect(event.velocity, 100);
        expect(event.isNoteOn, true);
        expect(event.timestamp, DateTime(2025, 1, 1, 12, 0, 0));
        expect(event.beatsFromStart, 4.0);
      });

      test('parses note-off event from JSON', () {
        final json = {
          'note': 72,
          'velocity': 0,
          'isNoteOn': false,
          'timestamp': '2025-06-15T10:30:45.123',
          'beatsFromStart': 16.5,
        };

        final event = MidiEvent.fromJson(json);

        expect(event.isNoteOn, false);
        expect(event.velocity, 0);
      });

      test('handles integer beatsFromStart', () {
        final json = {
          'note': 60,
          'velocity': 100,
          'isNoteOn': true,
          'timestamp': '2025-01-01T12:00:00.000',
          'beatsFromStart': 4, // integer, not double
        };

        final event = MidiEvent.fromJson(json);
        expect(event.beatsFromStart, 4.0);
      });
    });

    group('toJson', () {
      test('serializes to valid JSON', () {
        final event = MidiEvent(
          note: 60,
          velocity: 100,
          isNoteOn: true,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        final json = event.toJson();

        expect(json['note'], 60);
        expect(json['velocity'], 100);
        expect(json['isNoteOn'], true);
        expect(json['timestamp'], testTimestamp.toIso8601String());
        expect(json['beatsFromStart'], 4.0);
      });

      test('serializes note-off event correctly', () {
        final event = MidiEvent.noteOff(
          note: 64,
          timestamp: testTimestamp,
          beatsFromStart: 8.0,
        );

        final json = event.toJson();

        expect(json['isNoteOn'], false);
        expect(json['velocity'], 0);
      });
    });

    group('JSON round-trip', () {
      test('preserves all data through serialization', () {
        final original = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        final json = original.toJson();
        final restored = MidiEvent.fromJson(json);

        expect(restored, original);
      });

      test('preserves note-off through round-trip', () {
        final original = MidiEvent.noteOff(
          note: 72,
          timestamp: testTimestamp,
          beatsFromStart: 8.5,
        );

        final json = original.toJson();
        final restored = MidiEvent.fromJson(json);

        expect(restored, original);
      });
    });

    group('toString', () {
      test('formats note-on event correctly', () {
        final event = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        expect(event.toString(), 'MidiEvent(ON note=60 vel=100 beats=4.0)');
      });

      test('formats note-off event correctly', () {
        final event = MidiEvent.noteOff(
          note: 72,
          timestamp: testTimestamp,
          beatsFromStart: 8.0,
        );

        expect(event.toString(), 'MidiEvent(OFF note=72 vel=0 beats=8.0)');
      });
    });

    group('equality', () {
      test('equals itself', () {
        final event = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        expect(event, event);
      });

      test('equals identical event', () {
        final event1 = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        final event2 = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        expect(event1, event2);
        expect(event1.hashCode, event2.hashCode);
      });

      test('not equal with different note', () {
        final event1 = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        final event2 = MidiEvent.noteOn(
          note: 61,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        expect(event1, isNot(event2));
      });

      test('not equal with different velocity', () {
        final event1 = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        final event2 = MidiEvent.noteOn(
          note: 60,
          velocity: 127,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        expect(event1, isNot(event2));
      });

      test('not equal with different isNoteOn', () {
        final noteOn = MidiEvent(
          note: 60,
          velocity: 100,
          isNoteOn: true,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        final noteOff = MidiEvent(
          note: 60,
          velocity: 100,
          isNoteOn: false,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        expect(noteOn, isNot(noteOff));
      });

      test('not equal with different timestamp', () {
        final event1 = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        final event2 = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp.add(const Duration(seconds: 1)),
          beatsFromStart: 4.0,
        );

        expect(event1, isNot(event2));
      });

      test('not equal with different beatsFromStart', () {
        final event1 = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        final event2 = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 4.5,
        );

        expect(event1, isNot(event2));
      });

      test('not equal to non-MidiEvent', () {
        final event = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        // Test equality with different types using dynamic to avoid static analysis warnings
        expect(event == ('not an event' as dynamic), false);
        expect(event == (60 as dynamic), false);
      });
    });

    group('hashCode', () {
      test('same for equal events', () {
        final event1 = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        final event2 = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        expect(event1.hashCode, event2.hashCode);
      });

      test('generally different for different events', () {
        final events = [
          MidiEvent.noteOn(note: 60, velocity: 100, timestamp: testTimestamp, beatsFromStart: 4.0),
          MidiEvent.noteOn(note: 61, velocity: 100, timestamp: testTimestamp, beatsFromStart: 4.0),
          MidiEvent.noteOn(note: 60, velocity: 127, timestamp: testTimestamp, beatsFromStart: 4.0),
          MidiEvent.noteOff(note: 60, timestamp: testTimestamp, beatsFromStart: 4.0),
        ];

        final hashCodes = events.map((e) => e.hashCode).toSet();
        // Should have distinct hash codes (though not strictly required)
        expect(hashCodes.length, events.length);
      });
    });

    group('immutability', () {
      test('class is immutable (annotated)', () {
        // MidiEvent is annotated with @immutable
        // All fields are final
        final event = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 4.0,
        );

        // These would be compile errors if fields weren't final:
        // event.note = 61;
        // event.velocity = 50;

        expect(event.note, 60);
        expect(event.velocity, 100);
      });
    });

    group('edge cases', () {
      test('handles MIDI note 0 (lowest)', () {
        final event = MidiEvent.noteOn(
          note: 0,
          velocity: 64,
          timestamp: testTimestamp,
          beatsFromStart: 0.0,
        );

        expect(event.note, 0);
      });

      test('handles MIDI note 127 (highest)', () {
        final event = MidiEvent.noteOn(
          note: 127,
          velocity: 64,
          timestamp: testTimestamp,
          beatsFromStart: 0.0,
        );

        expect(event.note, 127);
      });

      test('handles beatsFromStart 0.0', () {
        final event = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 0.0,
        );

        expect(event.beatsFromStart, 0.0);
      });

      test('handles fractional beatsFromStart', () {
        final event = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 3.75,
        );

        expect(event.beatsFromStart, 3.75);
      });

      test('handles very large beatsFromStart', () {
        final event = MidiEvent.noteOn(
          note: 60,
          velocity: 100,
          timestamp: testTimestamp,
          beatsFromStart: 10000.0,
        );

        expect(event.beatsFromStart, 10000.0);
      });
    });
  });
}
