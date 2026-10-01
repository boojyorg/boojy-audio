/// New peaks of the take in progress, from the engine's live waveform:
/// one left/right pair per 10 ms of recording.
class LivePeaksChunk {
  /// Peaks the take has in total. Less than what was asked from means a new
  /// take started: start again from 0.
  final int total;
  final List<double> left;
  final List<double> right;

  const LivePeaksChunk({
    required this.total,
    required this.left,
    required this.right,
  });

  static const empty = LivePeaksChunk(total: 0, left: [], right: []);

  /// Parse `"total|l,r,l,r,…"`.
  static LivePeaksChunk parse(String raw) {
    final bar = raw.indexOf('|');
    if (bar < 0) return empty;
    final total = int.tryParse(raw.substring(0, bar));
    if (total == null) return empty;
    final body = raw.substring(bar + 1);
    if (body.isEmpty) return LivePeaksChunk(total: total, left: [], right: []);
    final values = body.split(',');
    final left = <double>[];
    final right = <double>[];
    for (var i = 0; i + 1 < values.length; i += 2) {
      left.add(double.tryParse(values[i]) ?? 0.0);
      right.add(double.tryParse(values[i + 1]) ?? 0.0);
    }
    return LivePeaksChunk(total: total, left: left, right: right);
  }
}
