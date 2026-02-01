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

  // Input routing
  int inputDeviceIndex; // -1 = no input assigned
  int inputChannel; // 0-based channel within device

  TrackData({
    required this.id,
    required this.name,
    required this.type,
    required this.volumeDb,
    required this.pan,
    required this.mute,
    required this.solo,
    required this.armed,
    this.inputDeviceIndex = -1,
    this.inputChannel = 0,
  });

  /// Parse track info from CSV format:
  /// "track_id,name,type,volume_db,pan,mute,solo,armed,input_device,input_channel"
  /// Handles 7-field (legacy), 8-field (with armed), and 10-field (with input routing) formats
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
        armed: parts.length >= 8 ? (parts[7] == 'true' || parts[7] == '1') : false,
        inputDeviceIndex: parts.length >= 9 ? (int.tryParse(parts[8]) ?? -1) : -1,
        inputChannel: parts.length >= 10 ? (int.tryParse(parts[9]) ?? 0) : 0,
      );
    } catch (e) {
      return null;
    }
  }

  /// Convert to CSV format for serialization
  String toCSV() {
    return '$id,$name,$type,$volumeDb,$pan,$mute,$solo,$armed,$inputDeviceIndex,$inputChannel';
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
    int? inputDeviceIndex,
    int? inputChannel,
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
      inputDeviceIndex: inputDeviceIndex ?? this.inputDeviceIndex,
      inputChannel: inputChannel ?? this.inputChannel,
    );
  }
}
