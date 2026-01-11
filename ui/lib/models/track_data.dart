/// Track data model
/// Unified model for track information parsed from audio engine CSV format
class TrackData {
  final int id;
  String name;
  final String type;
  double volumeDb;
  double pan;
  bool mute;
  bool solo;
  bool armed;

  TrackData({
    required this.id,
    required this.name,
    required this.type,
    required this.volumeDb,
    required this.pan,
    required this.mute,
    required this.solo,
    required this.armed,
  });

  /// Parse track info from CSV format: "track_id,name,type,volume_db,pan,mute,solo,armed"
  /// Handles both 7-field (legacy) and 8-field (with armed) formats
  static TrackData? fromCSV(String csv) {
    try {
      final parts = csv.split(',');
      if (parts.length < 7) return null;

      return TrackData(
        id: int.parse(parts[0]),
        name: parts[1],
        type: parts[2],
        volumeDb: double.parse(parts[3]),
        pan: double.parse(parts[4]),
        mute: parts[5] == 'true' || parts[5] == '1',
        solo: parts[6] == 'true' || parts[6] == '1',
        // Handle optional armed field (default to false if not present)
        armed: parts.length >= 8 ? (parts[7] == 'true' || parts[7] == '1') : false,
      );
    } catch (e) {
      return null;
    }
  }

  /// Convert to CSV format for serialization
  String toCSV() {
    return '$id,$name,$type,$volumeDb,$pan,$mute,$solo,$armed';
  }

  /// Create a copy with optional field overrides
  TrackData copyWith({
    int? id,
    String? name,
    String? type,
    double? volumeDb,
    double? pan,
    bool? mute,
    bool? solo,
    bool? armed,
  }) {
    return TrackData(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      volumeDb: volumeDb ?? this.volumeDb,
      pan: pan ?? this.pan,
      mute: mute ?? this.mute,
      solo: solo ?? this.solo,
      armed: armed ?? this.armed,
    );
  }
}
