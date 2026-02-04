import 'dart:typed_data';
import '../models/midi_note_data.dart';

/// Result of decoding a MIDI file.
class MidiFileDecodeResult {
  final List<MidiNoteData> notes;
  final double? tempo; // BPM extracted from file (informational only)
  final String? trackName;

  MidiFileDecodeResult({
    required this.notes,
    this.tempo,
    this.trackName,
  });
}

/// Pure Dart Standard MIDI File (SMF) encoder/decoder.
///
/// Supports Type 0 (single track) and Type 1 (multi-track) files.
/// Uses 480 PPQ (pulses per quarter note) for encoding.
class MidiFileService {
  static const int _ppq = 480;

  // ─── ENCODE ────────────────────────────────────────────────────────

  /// Encode a list of MIDI notes into a Standard MIDI File (Type 0).
  ///
  /// [notes] are in beats (quarter notes). [tempo] is BPM.
  /// Returns raw bytes that can be written to a .mid file.
  static Uint8List encode(List<MidiNoteData> notes, {double tempo = 120.0}) {
    final trackData = _encodeTrack(notes, tempo);
    final header = _encodeHeader(1); // 1 track
    final builder = BytesBuilder();
    builder.add(header);
    builder.add(trackData);
    return builder.toBytes();
  }

  static Uint8List _encodeHeader(int numTracks) {
    final builder = BytesBuilder();
    // MThd
    builder.add([0x4D, 0x54, 0x68, 0x64]);
    // Chunk length = 6
    builder.add(_uint32(6));
    // Format = 0 (single track)
    builder.add(_uint16(0));
    // Number of tracks
    builder.add(_uint16(numTracks));
    // Division = PPQ
    builder.add(_uint16(_ppq));
    return builder.toBytes();
  }

  static Uint8List _encodeTrack(List<MidiNoteData> notes, double tempo) {
    final events = BytesBuilder();

    // Tempo meta-event at tick 0: FF 51 03 tt tt tt
    final microsPerBeat = (60000000.0 / tempo).round();
    events.add(_vlq(0)); // delta-time = 0
    events.add([0xFF, 0x51, 0x03]);
    events.add([
      (microsPerBeat >> 16) & 0xFF,
      (microsPerBeat >> 8) & 0xFF,
      microsPerBeat & 0xFF,
    ]);

    // Build sorted list of NoteOn/NoteOff events
    final midiEvents = <_MidiEvent>[];
    for (final note in notes) {
      final startTick = (note.startTime * _ppq).round();
      final endTick = ((note.startTime + note.duration) * _ppq).round();
      midiEvents.add(_MidiEvent(
        tick: startTick,
        status: 0x90, // NoteOn, channel 0
        data1: note.note.clamp(0, 127),
        data2: note.velocity.clamp(1, 127),
      ));
      midiEvents.add(_MidiEvent(
        tick: endTick,
        status: 0x80, // NoteOff, channel 0
        data1: note.note.clamp(0, 127),
        data2: 0,
      ));
    }

    // Sort by tick, NoteOff before NoteOn at same tick
    midiEvents.sort((a, b) {
      final tickCmp = a.tick.compareTo(b.tick);
      if (tickCmp != 0) return tickCmp;
      // NoteOff (0x80) before NoteOn (0x90) at same tick
      return a.status.compareTo(b.status);
    });

    // Write events with delta-times
    int lastTick = 0;
    for (final event in midiEvents) {
      final delta = event.tick - lastTick;
      events.add(_vlq(delta));
      events.add([event.status, event.data1, event.data2]);
      lastTick = event.tick;
    }

    // End-of-Track meta-event: delta=0, FF 2F 00
    events.add(_vlq(0));
    events.add([0xFF, 0x2F, 0x00]);

    // Wrap in MTrk chunk
    final trackBytes = events.toBytes();
    final builder = BytesBuilder();
    // MTrk
    builder.add([0x4D, 0x54, 0x72, 0x6B]);
    // Chunk length
    builder.add(_uint32(trackBytes.length));
    builder.add(trackBytes);
    return builder.toBytes();
  }

  // ─── DECODE ────────────────────────────────────────────────────────

  /// Decode a Standard MIDI File into a list of notes.
  ///
  /// Supports Type 0 and Type 1 (merges all tracks).
  /// Notes are returned in beats (using the file's PPQ division).
  /// The file's tempo is extracted but NOT used for note timing
  /// (user chose "map to project tempo").
  static MidiFileDecodeResult decode(Uint8List data) {
    if (data.length < 14) {
      throw const FormatException('File too short to be a valid MIDI file');
    }

    int pos = 0;

    // Parse MThd header
    final headerTag = String.fromCharCodes(data.sublist(0, 4));
    if (headerTag != 'MThd') {
      throw const FormatException('Not a MIDI file (missing MThd header)');
    }
    pos = 4;

    final headerLen = _readUint32(data, pos);
    pos += 4;
    if (headerLen < 6) {
      throw FormatException('Invalid MThd header length: $headerLen');
    }

    final format = _readUint16(data, pos);
    pos += 2;
    final numTracks = _readUint16(data, pos);
    pos += 2;
    final division = _readUint16(data, pos);
    pos += 2;

    // Skip any extra header bytes
    pos = 8 + headerLen;

    if (format > 1) {
      throw FormatException('MIDI format $format not supported (only 0 and 1)');
    }

    // Check for SMPTE-based division (bit 15 set)
    int ppq;
    if (division & 0x8000 != 0) {
      // SMPTE — approximate as 480 PPQ
      ppq = 480;
    } else {
      ppq = division;
    }

    // Parse all tracks and merge
    final allNotes = <MidiNoteData>[];
    double? fileTempo;
    String? trackName;

    for (int t = 0; t < numTracks && pos < data.length; t++) {
      if (pos + 8 > data.length) break;

      final trackTag = String.fromCharCodes(data.sublist(pos, pos + 4));
      pos += 4;
      final trackLen = _readUint32(data, pos);
      pos += 4;

      if (trackTag != 'MTrk') {
        // Skip unknown chunk
        pos += trackLen;
        continue;
      }

      final trackEnd = pos + trackLen;
      final result = _decodeTrack(data, pos, trackEnd, ppq);
      allNotes.addAll(result.notes);
      fileTempo ??= result.tempo;
      trackName ??= result.trackName;
      pos = trackEnd;
    }

    return MidiFileDecodeResult(
      notes: allNotes,
      tempo: fileTempo,
      trackName: trackName,
    );
  }

  static _TrackDecodeResult _decodeTrack(
    Uint8List data,
    int start,
    int end,
    int ppq,
  ) {
    int pos = start;
    int absoluteTick = 0;
    double? tempo;
    String? trackName;

    // Active NoteOn events: key = (channel << 8) | note
    final activeNotes = <int, _ActiveNote>{};
    final completedNotes = <MidiNoteData>[];

    int runningStatus = 0;

    while (pos < end) {
      // Read delta-time
      final vlqResult = _readVlq(data, pos);
      final delta = vlqResult.value;
      pos = vlqResult.nextPos;
      absoluteTick += delta;

      if (pos >= end) break;

      int status = data[pos];

      // Handle running status
      if (status < 0x80) {
        // Use running status — don't advance pos
        status = runningStatus;
      } else {
        pos++;
        if (status < 0xF0) {
          runningStatus = status;
        }
      }

      if (status >= 0x80 && status <= 0xEF) {
        // Channel message
        final channel = status & 0x0F;
        final msgType = status & 0xF0;

        if (msgType == 0x80) {
          // NoteOff
          final note = data[pos++];
          pos++; // velocity (ignored)
          final key = (channel << 8) | note;
          final active = activeNotes.remove(key);
          if (active != null) {
            final startBeat = active.tick / ppq;
            final endBeat = absoluteTick / ppq;
            final duration = (endBeat - startBeat).clamp(0.01, double.infinity);
            completedNotes.add(MidiNoteData(
              note: note,
              velocity: active.velocity,
              startTime: startBeat,
              duration: duration,
            ));
          }
        } else if (msgType == 0x90) {
          // NoteOn
          final note = data[pos++];
          final velocity = data[pos++];
          final key = (channel << 8) | note;
          if (velocity == 0) {
            // NoteOn with velocity 0 = NoteOff
            final active = activeNotes.remove(key);
            if (active != null) {
              final startBeat = active.tick / ppq;
              final endBeat = absoluteTick / ppq;
              final duration =
                  (endBeat - startBeat).clamp(0.01, double.infinity);
              completedNotes.add(MidiNoteData(
                note: note,
                velocity: active.velocity,
                startTime: startBeat,
                duration: duration,
              ));
            }
          } else {
            // Close any existing note on same key (handle overlapping)
            final existing = activeNotes.remove(key);
            if (existing != null) {
              final startBeat = existing.tick / ppq;
              final endBeat = absoluteTick / ppq;
              final duration =
                  (endBeat - startBeat).clamp(0.01, double.infinity);
              completedNotes.add(MidiNoteData(
                note: note,
                velocity: existing.velocity,
                startTime: startBeat,
                duration: duration,
              ));
            }
            activeNotes[key] =
                _ActiveNote(tick: absoluteTick, velocity: velocity);
          }
        } else if (msgType == 0xA0) {
          // Polyphonic aftertouch — skip 2 data bytes
          pos += 2;
        } else if (msgType == 0xB0) {
          // Control change — skip 2 data bytes
          pos += 2;
        } else if (msgType == 0xC0) {
          // Program change — skip 1 data byte
          pos += 1;
        } else if (msgType == 0xD0) {
          // Channel aftertouch — skip 1 data byte
          pos += 1;
        } else if (msgType == 0xE0) {
          // Pitch bend — skip 2 data bytes
          pos += 2;
        }
      } else if (status == 0xFF) {
        // Meta-event
        final type = data[pos++];
        final vlqLen = _readVlq(data, pos);
        final len = vlqLen.value;
        pos = vlqLen.nextPos;

        if (type == 0x51 && len == 3) {
          // Tempo
          final usPerBeat = (data[pos] << 16) | (data[pos + 1] << 8) | data[pos + 2];
          tempo = 60000000.0 / usPerBeat;
        } else if (type == 0x03 && len > 0) {
          // Track name
          trackName = String.fromCharCodes(data.sublist(pos, pos + len));
        } else if (type == 0x2F) {
          // End of track
          pos += len;
          break;
        }

        pos += len;
      } else if (status == 0xF0 || status == 0xF7) {
        // SysEx — read length and skip
        final vlqLen = _readVlq(data, pos);
        pos = vlqLen.nextPos + vlqLen.value;
      } else {
        // Unknown — skip
        break;
      }
    }

    // Close any remaining active notes at the last tick
    for (final entry in activeNotes.entries) {
      final note = entry.key & 0xFF;
      final active = entry.value;
      final startBeat = active.tick / ppq;
      final endBeat = absoluteTick / ppq;
      final duration = (endBeat - startBeat).clamp(0.01, double.infinity);
      completedNotes.add(MidiNoteData(
        note: note,
        velocity: active.velocity,
        startTime: startBeat,
        duration: duration,
      ));
    }

    return _TrackDecodeResult(
      notes: completedNotes,
      tempo: tempo,
      trackName: trackName,
    );
  }

  // ─── VLQ (Variable-Length Quantity) Helpers ─────────────────────────

  /// Encode an integer as a MIDI variable-length quantity.
  static Uint8List _vlq(int value) {
    if (value < 0) value = 0;
    if (value < 0x80) return Uint8List.fromList([value]);

    final bytes = <int>[];
    bytes.add(value & 0x7F);
    value >>= 7;
    while (value > 0) {
      bytes.add((value & 0x7F) | 0x80);
      value >>= 7;
    }
    return Uint8List.fromList(bytes.reversed.toList());
  }

  /// Read a VLQ from data at [pos]. Returns value and next position.
  static _VlqResult _readVlq(Uint8List data, int pos) {
    int value = 0;
    int b;
    do {
      if (pos >= data.length) break;
      b = data[pos++];
      value = (value << 7) | (b & 0x7F);
    } while (b & 0x80 != 0);
    return _VlqResult(value, pos);
  }

  // ─── Binary Helpers ────────────────────────────────────────────────

  static Uint8List _uint32(int value) {
    return Uint8List.fromList([
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  static Uint8List _uint16(int value) {
    return Uint8List.fromList([
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  static int _readUint32(Uint8List data, int pos) {
    return (data[pos] << 24) | (data[pos + 1] << 16) | (data[pos + 2] << 8) | data[pos + 3];
  }

  static int _readUint16(Uint8List data, int pos) {
    return (data[pos] << 8) | data[pos + 1];
  }
}

// ─── Internal Types ──────────────────────────────────────────────────

class _MidiEvent {
  final int tick;
  final int status;
  final int data1;
  final int data2;

  _MidiEvent({
    required this.tick,
    required this.status,
    required this.data1,
    required this.data2,
  });
}

class _ActiveNote {
  final int tick;
  final int velocity;

  _ActiveNote({required this.tick, required this.velocity});
}

class _VlqResult {
  final int value;
  final int nextPos;

  _VlqResult(this.value, this.nextPos);
}

class _TrackDecodeResult {
  final List<MidiNoteData> notes;
  final double? tempo;
  final String? trackName;

  _TrackDecodeResult({
    required this.notes,
    this.tempo,
    this.trackName,
  });
}
