/// Effect data model used by the device chain.
class EffectData {
  final int id;
  final String type;
  final Map<String, double> parameters;
  final bool bypassed;

  EffectData({
    required this.id,
    required this.type,
    required this.parameters,
    this.bypassed = false,
  });

  /// Parse effect info from format: "type:eq,bypassed:0,low_freq:100,low_gain:0,..."
  static EffectData? fromInfo(int id, String info) {
    try {
      final Map<String, double> params = {};
      String? type;
      bool bypassed = false;

      for (final pair in info.split(',')) {
        final parts = pair.split(':');
        if (parts.length == 2) {
          if (parts[0] == 'type') {
            type = parts[1];
          } else if (parts[0] == 'bypassed') {
            bypassed = parts[1] == '1';
          } else {
            params[parts[0]] = double.parse(parts[1]);
          }
        }
      }

      if (type == null) return null;
      return EffectData(
        id: id,
        type: type,
        parameters: params,
        bypassed: bypassed,
      );
    } catch (_) {
      return null;
    }
  }

  EffectData copyWith({bool? bypassed}) => EffectData(
    id: id,
    type: type,
    parameters: parameters,
    bypassed: bypassed ?? this.bypassed,
  );
}
