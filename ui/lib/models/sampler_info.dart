/// Sampler info data class for UI synchronization.
/// Contains all sampler state needed by the Sampler Editor UI.
class SamplerInfo {
  final double durationSeconds;
  final double sampleRate;
  final bool loopEnabled;
  final double loopStartSeconds;
  final double loopEndSeconds;
  final int rootNote;
  final double attackMs;
  final double releaseMs;

  const SamplerInfo({
    required this.durationSeconds,
    required this.sampleRate,
    required this.loopEnabled,
    required this.loopStartSeconds,
    required this.loopEndSeconds,
    required this.rootNote,
    required this.attackMs,
    required this.releaseMs,
  });
}
