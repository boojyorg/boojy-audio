// Data models for VST3 plugin support (M7)

/// Represents a scanned VST3 plugin
class Vst3Plugin {
  final String name;
  final String path;
  final String? vendor;
  final bool isInstrument;
  final bool isEffect;

  Vst3Plugin({
    required this.name,
    required this.path,
    this.vendor,
    this.isInstrument = false,
    this.isEffect = true,
  });

  /// Create from scan result map
  factory Vst3Plugin.fromMap(Map<String, String> map) {
    return Vst3Plugin(
      name: map['name'] ?? 'Unknown Plugin',
      path: map['path'] ?? '',
      vendor: map['vendor'],
      isInstrument: map['is_instrument'] == '1',
      isEffect: map['is_effect'] == '1',
    );
  }

  @override
  String toString() {
    final type = isInstrument ? 'Instrument' : (isEffect ? 'Effect' : 'Unknown');
    return 'Vst3Plugin(name: $name, vendor: ${vendor ?? 'Unknown'}, type: $type)';
  }
}

/// Information about a VST3 parameter
class Vst3ParameterInfo {
  final int index;
  final String name;
  final double min;
  final double max;
  final double defaultValue;
  final String unit;

  Vst3ParameterInfo({
    required this.index,
    required this.name,
    this.min = 0.0,
    this.max = 1.0,
    this.defaultValue = 0.5,
    this.unit = '',
  });

  /// Create from FFI result map
  factory Vst3ParameterInfo.fromMap(int index, Map<String, dynamic> map) {
    return Vst3ParameterInfo(
      index: index,
      name: map['name'] ?? 'Parameter $index',
      min: map['min'] ?? 0.0,
      max: map['max'] ?? 1.0,
      defaultValue: map['default'] ?? 0.5,
      unit: map['unit'] ?? '',
    );
  }

  @override
  String toString() {
    return 'Vst3ParameterInfo(index: $index, name: $name, range: $min-$max, default: $defaultValue)';
  }
}

/// Represents a loaded VST3 plugin instance on a track
class Vst3PluginInstance {
  final int effectId;
  final String pluginName;
  final String pluginPath;
  final Map<int, Vst3ParameterInfo> parameters;
  final Map<int, double> parameterValues;

  Vst3PluginInstance({
    required this.effectId,
    required this.pluginName,
    required this.pluginPath,
    Map<int, Vst3ParameterInfo>? parameters,
    Map<int, double>? parameterValues,
  })  : parameters = parameters ?? {},
        parameterValues = parameterValues ?? {};

  /// Get parameter info by index
  Vst3ParameterInfo? getParameterInfo(int index) {
    return parameters[index];
  }

  /// Get parameter value by index
  double? getParameterValue(int index) {
    return parameterValues[index];
  }

  /// Update parameter value cache
  void setParameterValue(int index, double value) {
    parameterValues[index] = value;
  }

  /// Group parameters by prefix (e.g., "Filter Cutoff" → "Filter" group)
  Map<String, List<Vst3ParameterInfo>> groupParameters() {
    final groups = <String, List<Vst3ParameterInfo>>{};

    for (final param in parameters.values) {
      String groupName = 'Parameters'; // Default group

      // Try to extract group from parameter name
      // Common patterns: "Filter Cutoff", "Amp Attack", "LFO Rate", etc.
      final words = param.name.split(' ');
      if (words.length > 1) {
        // Check if first word could be a group name (all caps, or capitalized)
        final firstWord = words[0];
        if (firstWord.length > 2 &&
            (firstWord.toUpperCase() == firstWord ||
             RegExp(r'^[A-Z][a-z]+$').hasMatch(firstWord))) {
          groupName = firstWord;
        }
      }

      groups.putIfAbsent(groupName, () => []);
      groups[groupName]!.add(param);
    }

    // Sort parameters within each group by index
    for (final group in groups.values) {
      group.sort((a, b) => a.index.compareTo(b.index));
    }

    return groups;
  }

  /// Filter parameters by search query
  List<Vst3ParameterInfo> filterParameters(String query) {
    if (query.isEmpty) {
      return parameters.values.toList()..sort((a, b) => a.index.compareTo(b.index));
    }

    final lowercaseQuery = query.toLowerCase();
    return parameters.values
        .where((param) => param.name.toLowerCase().contains(lowercaseQuery))
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));
  }

  @override
  String toString() {
    return 'Vst3PluginInstance(effectId: $effectId, name: $pluginName, parameters: ${parameters.length})';
  }
}
