import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'audio_clip_edit_data.dart';
import 'clip_data.dart';

/// A Pitch, Volume or Reverse change made in the Audio Editor while several
/// audio clips are selected: the open clip and every other selected audio
/// clip get the same edit, as one undo step.
///
/// Dragging (or scrolling) shifts every clip by the same amount, so they keep
/// their differences; typing a value, a double-click reset and Reverse set
/// every clip to the same value.
@immutable
sealed class ClipGroupEdit {
  const ClipGroupEdit();

  /// [edit] with this change made.
  AudioClipEditData applyTo(AudioClipEditData edit);
}

/// Move the pitch by [cents] (100 to a semitone).
class ShiftPitch extends ClipGroupEdit {
  final int cents;
  const ShiftPitch(this.cents);

  @override
  AudioClipEditData applyTo(AudioClipEditData edit) {
    if (cents == 0) return edit;
    final (semitones, fine) = splitPitchCents(pitchCents(edit) + cents);
    return edit.copyWith(transposeSemitones: semitones, fineCents: fine);
  }
}

/// Set the semitones; each clip keeps its own cents.
class SetSemitones extends ClipGroupEdit {
  final int semitones;
  const SetSemitones(this.semitones);

  @override
  AudioClipEditData applyTo(AudioClipEditData edit) => edit.copyWith(
    transposeSemitones: semitones.clamp(minSemitones, maxSemitones),
  );
}

/// Set the cents; past ±50 they carry into the semitones, as typing them
/// into one clip does.
class SetCents extends ClipGroupEdit {
  final int cents;
  const SetCents(this.cents);

  @override
  AudioClipEditData applyTo(AudioClipEditData edit) {
    var semitones = edit.transposeSemitones;
    var fine = cents;
    while (fine > maxCents) {
      fine -= 100;
      semitones += 1;
    }
    while (fine < minCents) {
      fine += 100;
      semitones -= 1;
    }
    semitones = semitones.clamp(minSemitones, maxSemitones);
    if (semitones == maxSemitones && fine > 0) fine = 0;
    if (semitones == minSemitones && fine < 0) fine = 0;
    return edit.copyWith(transposeSemitones: semitones, fineCents: fine);
  }
}

/// Move the volume by [db]. A silent clip (-∞) stays silent: it's out of the
/// mix on purpose, and would otherwise stop the others going down at all.
class ShiftGain extends ClipGroupEdit {
  final double db;
  const ShiftGain(this.db);

  @override
  AudioClipEditData applyTo(AudioClipEditData edit) {
    if (db == 0 || edit.gainDb <= minGainDb) return edit;
    return edit.copyWith(
      gainDb: (edit.gainDb + db).clamp(minGainDb, maxGainDb),
    );
  }
}

/// Set the volume.
class SetGain extends ClipGroupEdit {
  final double db;
  const SetGain(this.db);

  @override
  AudioClipEditData applyTo(AudioClipEditData edit) =>
      edit.copyWith(gainDb: db.clamp(minGainDb, maxGainDb));
}

/// Reverse every clip, or none.
class SetReversed extends ClipGroupEdit {
  final bool reversed;
  const SetReversed({required this.reversed});

  @override
  AudioClipEditData applyTo(AudioClipEditData edit) =>
      edit.copyWith(reversed: reversed);
}

const int minSemitones = -48;
const int maxSemitones = 48;
const int minCents = -50;
const int maxCents = 50;
const double minGainDb = -70.0;
const double maxGainDb = 24.0;

/// The lowest volume a group drag takes a clip to (-70 dB is silent).
const double lowestAudibleGainDb = -69.9;

/// Highest and lowest pitch in cents: ±48 semitones and ±50 cents.
const int maxPitchCents = maxSemitones * 100 + maxCents;
const int minPitchCents = -maxPitchCents;

/// A clip's pitch as one number of cents.
int pitchCents(AudioClipEditData edit) =>
    edit.transposeSemitones * 100 + edit.fineCents;

/// [cents] as semitones and cents, the cents within ±50 (a half rounds
/// towards zero, so +50 ct stays +50 ct and doesn't become +1 st −50 ct).
(int, int) splitPitchCents(int cents) {
  final clamped = cents.clamp(minPitchCents, maxPitchCents);
  final semitones = clamped.sign * ((clamped.abs() + 49) ~/ 100);
  return (semitones, clamped - semitones * 100);
}

/// A clip's edits, or the plain ones a clip has before its first edit.
AudioClipEditData editDataOf(ClipData clip) =>
    clip.editData ?? AudioClipEditData(loopEnabled: clip.canRepeat);

/// The selected audio clips the Audio Editor's Pitch, Volume and Reverse act
/// on, summed up for its controls: how many, and the spread of their values.
@immutable
class ClipGroup {
  final int count;
  final int lowSemitones;
  final int highSemitones;
  final int lowCents;
  final int highCents;
  final int lowPitch;
  final int highPitch;

  /// The volume spread, silent clips included (for display).
  final double lowGainDb;
  final double highGainDb;

  /// The spread over the clips that aren't silent (the ones a volume drag
  /// moves); null when they all are.
  final double? lowAudibleGainDb;
  final double? highAudibleGainDb;

  /// How many of the clips are reversed.
  final int reversedCount;

  const ClipGroup._({
    required this.count,
    required this.lowSemitones,
    required this.highSemitones,
    required this.lowCents,
    required this.highCents,
    required this.lowPitch,
    required this.highPitch,
    required this.lowGainDb,
    required this.highGainDb,
    required this.lowAudibleGainDb,
    required this.highAudibleGainDb,
    required this.reversedCount,
  });

  /// The group of [edits], or null for fewer than two (one clip edits alone).
  static ClipGroup? of(List<AudioClipEditData> edits) {
    if (edits.length < 2) return null;
    T low<T extends num>(Iterable<T> l) => l.reduce((a, b) => a < b ? a : b);
    T high<T extends num>(Iterable<T> l) => l.reduce((a, b) => a > b ? a : b);
    final semitones = edits.map((e) => e.transposeSemitones);
    final cents = edits.map((e) => e.fineCents);
    final pitches = edits.map(pitchCents);
    final gains = edits.map((e) => e.gainDb);
    final audible = gains.where((g) => g > minGainDb);
    return ClipGroup._(
      count: edits.length,
      lowSemitones: low(semitones),
      highSemitones: high(semitones),
      lowCents: low(cents),
      highCents: high(cents),
      lowPitch: low(pitches),
      highPitch: high(pitches),
      lowGainDb: low(gains),
      highGainDb: high(gains),
      lowAudibleGainDb: audible.isEmpty ? null : low(audible),
      highAudibleGainDb: audible.isEmpty ? null : high(audible),
      reversedCount: edits.where((e) => e.reversed).length,
    );
  }

  bool get pitchDiffers => lowPitch != highPitch;
  bool get gainDiffers => lowGainDb != highGainDb;
  bool get reverseDiffers => reversedCount != 0 && reversedCount != count;

  /// [cents] cut down so no clip goes past the pitch limits: the whole group
  /// stops together and keeps its spacing. With [wholeSemitones] (a
  /// semitone drag) the cut is to whole semitones.
  int clampPitchShift(int cents, {bool wholeSemitones = false}) {
    final clamped = cents.clamp(
      minPitchCents - lowPitch,
      maxPitchCents - highPitch,
    );
    return wholeSemitones ? (clamped ~/ 100) * 100 : clamped;
  }

  /// [db] cut down so no clip that isn't silent goes past the volume limits.
  /// Going down, the group stops just above silent: a clip that went silent
  /// would stay put after (see [ShiftGain]), and the spacing would be lost.
  double clampGainShift(double db) {
    final low = lowAudibleGainDb;
    final high = highAudibleGainDb;
    if (low == null || high == null) return db;
    final floor = math.min(0.0, lowestAudibleGainDb - low);
    return db.clamp(floor, math.max(0.0, maxGainDb - high));
  }
}
