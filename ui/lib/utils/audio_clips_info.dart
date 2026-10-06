import '../models/clip_data.dart';
import 'csv_field.dart';

/// One audio clip as the engine holds it (a row of `getAllAudioClipsInfo`).
class EngineAudioClipInfo {
  final int clipId;
  final int trackId;

  /// Seconds.
  final double startTime;
  final double offset;

  /// Explicit play length in seconds, or null when the clip plays to the end
  /// of its file.
  final double? duration;

  /// Length of the whole audio file in seconds.
  final double fileDuration;
  final double gainDb;
  final bool warpEnabled;
  final double stretchFactor;
  final int warpMode;
  final int transposeSemitones;
  final int transposeCents;
  final bool reversed;

  /// Seconds of the clip's own audio that repeat, or null when it doesn't.
  final double? loopLength;

  /// Where in the loop the clip begins (seconds of its own audio).
  final double loopStart;
  final String filePath;

  const EngineAudioClipInfo({
    required this.clipId,
    required this.trackId,
    required this.startTime,
    required this.offset,
    required this.duration,
    required this.fileDuration,
    required this.gainDb,
    required this.warpEnabled,
    required this.stretchFactor,
    required this.warpMode,
    required this.transposeSemitones,
    required this.transposeCents,
    required this.reversed,
    required this.loopLength,
    required this.loopStart,
    required this.filePath,
  });
}

/// Parse the engine's `getAllAudioClipsInfo` string: `;`-separated rows of
/// `clip_id,track_id,start_time,offset,duration,file_duration,gain_db,
/// warp_enabled,stretch_factor,warp_mode,transpose_semitones,transpose_cents,
/// reversed,loop_length,loop_start,file_path` (`duration` is -1 for "to the
/// end of the file", `loop_length` -1 for "doesn't repeat", `file_path`
/// percent-encoded).
///
/// Malformed rows are skipped rather than failing the whole project open; an
/// empty string or an `Error: …` reply yields no clips.
List<EngineAudioClipInfo> parseAudioClipsInfo(String raw) {
  if (raw.isEmpty || raw.startsWith('Error:')) return const [];

  final clips = <EngineAudioClipInfo>[];
  for (final row in raw.split(';')) {
    if (row.isEmpty) continue;
    final f = row.split(',');
    if (f.length < 16) continue;
    final clipId = int.tryParse(f[0]);
    final trackId = int.tryParse(f[1]);
    final startTime = double.tryParse(f[2]);
    final offset = double.tryParse(f[3]);
    final duration = double.tryParse(f[4]);
    final fileDuration = double.tryParse(f[5]);
    if (clipId == null ||
        trackId == null ||
        startTime == null ||
        offset == null ||
        duration == null ||
        fileDuration == null) {
      continue;
    }
    clips.add(
      EngineAudioClipInfo(
        clipId: clipId,
        trackId: trackId,
        startTime: startTime,
        offset: offset,
        duration: duration < 0 ? null : duration,
        fileDuration: fileDuration,
        gainDb: double.tryParse(f[6]) ?? 0.0,
        warpEnabled: f[7] == '1',
        stretchFactor: double.tryParse(f[8]) ?? 1.0,
        warpMode: int.tryParse(f[9]) ?? 0,
        transposeSemitones: int.tryParse(f[10]) ?? 0,
        transposeCents: int.tryParse(f[11]) ?? 0,
        reversed: f[12] == '1',
        loopLength: _positiveOrNull(double.tryParse(f[13])),
        loopStart: double.tryParse(f[14]) ?? 0.0,
        // The path is last; rejoin in case an unencoded comma slipped in.
        filePath: decodeCsvField(f.sublist(15).join(',')),
      ),
    );
  }
  return clips;
}

double? _positiveOrNull(double? v) => (v != null && v > 0) ? v : null;

/// Build the arrangement's audio clips from the engine's copy of the song,
/// merging the UI-only extras saved in `ui_layout.json`.
///
/// The engine decides *which* clips exist and where they sit (so audio you can
/// hear is always visible, even in a project whose layout file is out of step).
/// The saved layout only adds what the engine doesn't store: colour, loop
/// settings, edit parameters, and the display path.
///
/// A saved clip is matched by clip id **and** track id. The track check stops
/// a stale id from an older, damaged project layout from attaching someone
/// else's colour and edits to a clip that merely reuses the number.
///
/// - Engine clip with no saved match: still produced, with defaults.
/// - Saved clip with no engine clip: dropped (nothing would play it).
///
/// [peaksFor] computes a waveform for a clip that has no saved peaks (old
/// layout files carried peaks; new ones don't).
List<ClipData> rebuildAudioClips({
  required List<EngineAudioClipInfo> engineClips,
  required List<ClipData> savedClips,
  required List<double> Function(int clipId, double fileDuration) peaksFor,
}) {
  final savedById = {for (final c in savedClips) c.clipId: c};

  return [
    for (final e in engineClips)
      _mergeClip(
        e,
        savedById[e.clipId]?.trackId == e.trackId ? savedById[e.clipId] : null,
        peaksFor,
      ),
  ];
}

ClipData _mergeClip(
  EngineAudioClipInfo e,
  ClipData? saved,
  List<double> Function(int clipId, double fileDuration) peaksFor,
) {
  // Explicit engine length wins. Otherwise the clip plays to the end of its
  // file from its offset; a matched saved clip knows its arrangement length.
  final playableRest = (e.fileDuration - e.offset).clamp(0.0, double.infinity);
  final duration = e.duration ?? saved?.duration ?? playableRest;

  final savedPeaks = saved?.waveformPeaks ?? const <double>[];

  return ClipData(
    clipId: e.clipId,
    trackId: e.trackId,
    // The saved path is the file the user dropped (and what undo reloads);
    // the engine path is always a real, loadable file.
    filePath: (saved != null && saved.filePath.isNotEmpty)
        ? saved.filePath
        : e.filePath,
    startTime: e.startTime,
    duration: duration,
    offset: e.offset,
    waveformPeaks: savedPeaks.isNotEmpty
        ? savedPeaks
        : peaksFor(e.clipId, e.fileDuration),
    color: saved?.color,
    editData: saved?.editData,
    loopLength: _loopLength(saved),
    loopStart: saved?.loopStart ?? 0.0,
    canRepeat: saved?.canRepeat ?? true,
  );
}

/// A warped clip's loop length comes from its own beats. Older saves stored
/// it at the project tempo of the day, which drew the waveform too long or
/// short; the project tempo doesn't matter for a warped clip.
double? _loopLength(ClipData? saved) {
  final edit = saved?.editData;
  if (edit != null && edit.syncEnabled) return edit.loopLengthSeconds(edit.bpm);
  return saved?.loopLength;
}
