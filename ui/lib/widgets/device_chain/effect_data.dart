/// Effect data model used by the device chain.
class EffectData {
  final int id;

  /// Built-in effects: "eq", "reverb", …; VST3 effects: `vst3:` + the plugin name.
  final String type;
  final Map<String, double> parameters;
  final bool bypassed;

  /// The plugin's file path, for VST3 effects only.
  final String? pluginPath;

  EffectData({
    required this.id,
    required this.type,
    required this.parameters,
    this.bypassed = false,
    this.pluginPath,
  });

  bool get isVst3 => pluginPath != null;

  /// Parse the engine's effect info. Built-in effects are
  /// "type:eq,bypassed:0,low_freq:100,…" with numeric values; VST3 effects are
  /// "type:vst3,bypassed:0,name:NAME,path:PATH" with `path` last, so the path
  /// (which may hold commas, or a Windows drive colon) is everything after it.
  static EffectData? fromInfo(int id, String info) {
    if (info.startsWith('type:vst3,')) return _fromVst3Info(id, info);

    final Map<String, double> params = {};
    String? type;
    bool bypassed = false;

    for (final pair in info.split(',')) {
      final parts = pair.split(':');
      if (parts.length != 2) continue;
      final key = parts[0].trim();
      final value = parts[1].trim();
      if (key == 'type') {
        type = value;
      } else if (key == 'bypassed') {
        bypassed = value == '1';
      } else {
        final v = double.tryParse(value);
        if (v != null) params[key] = v;
      }
    }

    if (type == null) return null;
    return EffectData(
      id: id,
      type: type,
      parameters: params,
      bypassed: bypassed,
    );
  }

  static EffectData? _fromVst3Info(int id, String info) {
    const pathMarker = ',path:';
    final pathIdx = info.indexOf(pathMarker);
    if (pathIdx < 0) return null;
    final path = info.substring(pathIdx + pathMarker.length);
    if (path.isEmpty) return null;

    // name: is the field just before path:, so it runs to the path marker.
    final head = info.substring(0, pathIdx); // "type:vst3,bypassed:X,name:NAME"
    var name = '';
    var beforeName = head;
    const nameMarker = ',name:';
    final nameIdx = head.indexOf(nameMarker);
    if (nameIdx >= 0) {
      name = head.substring(nameIdx + nameMarker.length);
      beforeName = head.substring(0, nameIdx);
    }

    return EffectData(
      id: id,
      type: 'vst3:$name',
      parameters: const {},
      bypassed: beforeName.contains('bypassed:1'),
      pluginPath: path,
    );
  }

  EffectData copyWith({bool? bypassed}) => EffectData(
    id: id,
    type: type,
    parameters: parameters,
    bypassed: bypassed ?? this.bypassed,
    pluginPath: pluginPath,
  );
}
