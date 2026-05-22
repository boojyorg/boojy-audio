import 'dart:math' as math;

/// A send from a source track to a return bus.
class TrackSendData {
  final int returnId;
  final String label;
  final String effectType;
  final double amountLinear;

  const TrackSendData({
    required this.returnId,
    required this.label,
    required this.effectType,
    required this.amountLinear,
  });

  /// Engine CSV: "return_id,amount_db,return_name;..."
  static List<TrackSendData> parseTrackSendsCsv(
    String csv, {
    Map<int, String> returnEffectTypes = const {},
  }) {
    if (csv.isEmpty || csv.startsWith('Error')) return [];

    final sends = <TrackSendData>[];
    for (final entry in csv.split(';')) {
      if (entry.trim().isEmpty) continue;
      final parts = entry.split(',');
      if (parts.length < 3) continue;

      final returnId = int.tryParse(parts[0]);
      if (returnId == null) continue;

      final amountDb = double.tryParse(parts[1]) ?? -20.0;
      final label = parts.sublist(2).join(',');

      sends.add(
        TrackSendData(
          returnId: returnId,
          label: label,
          effectType: returnEffectTypes[returnId] ?? _guessEffectType(label),
          amountLinear: dbToLinear(amountDb),
        ),
      );
    }
    return sends;
  }

  static String _guessEffectType(String label) {
    return label.toLowerCase().replaceAll(' ', '');
  }

  static double dbToLinear(double db) {
    if (db <= -96.0) return 0.0;
    return math.pow(10, db / 20.0).toDouble();
  }

  static double linearToDb(double linear) {
    if (linear <= 0.0) return -96.0;
    return 20.0 * math.log(linear) / math.ln10;
  }

  /// Format linear amount as percentage for display (e.g. 0.1 → "10%").
  String get amountPercentLabel {
    if (amountLinear <= 0.0) return '0%';
    return '${(amountLinear * 100).round()}%';
  }
}

/// A return bus track (mixer-only in v0.3).
class ReturnTrackData {
  final int id;
  final String name;
  final String effectType;

  const ReturnTrackData({
    required this.id,
    required this.name,
    required this.effectType,
  });

  /// Engine CSV: "return_id,name,effect_type;..."
  static List<ReturnTrackData> parseAllReturnsCsv(String csv) {
    if (csv.isEmpty || csv.startsWith('Error')) return [];

    final returns = <ReturnTrackData>[];
    for (final entry in csv.split(';')) {
      if (entry.trim().isEmpty) continue;
      final parts = entry.split(',');
      if (parts.length < 3) continue;

      final id = int.tryParse(parts[0]);
      if (id == null) continue;

      returns.add(
        ReturnTrackData(
          id: id,
          name: parts[1],
          effectType: parts[2],
        ),
      );
    }
    return returns;
  }

  Map<int, String> get effectTypeById => {id: effectType};
}
