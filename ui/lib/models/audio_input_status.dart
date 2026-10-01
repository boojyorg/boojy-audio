/// Settings value for "never open an input". Matches the engine's `INPUT_OFF`.
const String kAudioInputOff = '__off__';

/// The audio input as the engine resolves it right now.
class AudioInputStatus {
  /// The user turned input off in Settings.
  final bool isOff;

  /// The chosen device isn't connected, so the system default is used.
  final bool fellBack;

  /// Channels on the resolved device (0 when off or nothing is connected).
  final int channelCount;

  /// The device input opens on; empty when off or nothing is connected.
  final String deviceName;

  const AudioInputStatus({
    required this.isOff,
    required this.fellBack,
    required this.channelCount,
    required this.deviceName,
  });

  static const unknown = AudioInputStatus(
    isOff: false,
    fellBack: false,
    channelCount: 0,
    deviceName: '',
  );

  /// A one-line warning when recording audio won't use what the user
  /// expects, or null when all is well. [preferred] is the saved Settings
  /// choice (null = system default).
  String? notice({String? preferred}) {
    if (identical(this, unknown)) return null; // engine didn't answer
    if (isOff) return 'Audio input is off. Turn it on in Settings → Audio.';
    if (deviceName.isEmpty) return 'No audio input connected.';
    if (fellBack && preferred != null) {
      return "$preferred isn't connected, using $deviceName.";
    }
    return null;
  }

  /// Parse the engine's `"off|fell_back|channels|device name"`. The name is
  /// last and may itself contain `|`.
  static AudioInputStatus parse(String raw) {
    final parts = raw.split('|');
    if (parts.length < 4 || raw.startsWith('Error')) return unknown;
    return AudioInputStatus(
      isOff: parts[0] == '1',
      fellBack: parts[1] == '1',
      channelCount: int.tryParse(parts[2]) ?? 0,
      deviceName: parts.sublist(3).join('|'),
    );
  }
}

/// What the open input is doing (engine `InputHealth`).
enum InputHealthState { closed, off, waiting, heard, silent, failed, unknown }

/// The engine's input health: whether sound is arriving, and whether arming
/// held monitoring back because the input and output look like the
/// computer's own mic and speakers.
class AudioInputHealth {
  final InputHealthState state;
  final bool feedbackGuarded;

  const AudioInputHealth(this.state, {this.feedbackGuarded = false});

  static const unknown = AudioInputHealth(InputHealthState.unknown);

  /// Decode `get_audio_input_health_ffi`: the state code in the low byte,
  /// +256 when monitoring was held back. Negative means the engine failed.
  static AudioInputHealth fromCode(int code) {
    if (code < 0) return unknown;
    const states = [
      InputHealthState.closed,
      InputHealthState.off,
      InputHealthState.waiting,
      InputHealthState.heard,
      InputHealthState.silent,
      InputHealthState.failed,
    ];
    final index = code & 0xff;
    return AudioInputHealth(
      index < states.length ? states[index] : InputHealthState.unknown,
      feedbackGuarded: code & 0x100 != 0,
    );
  }

  /// The problem to show while an audio track is armed, or null when there
  /// is none (or it's too early to tell).
  String? get problem => switch (state) {
    InputHealthState.off =>
      'Audio input is off. Turn it on in Settings → Audio.',
    InputHealthState.silent ||
    InputHealthState.failed => "Boojy can't hear your input",
    _ => null,
  };
}
