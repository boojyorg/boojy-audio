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
  final double volumeDb;
  final int transposeSemitones;
  final int fineCents;
  final bool reversed;
  final double originalBpm;
  final bool warpEnabled;
  final int warpMode; // 0=repitch, 1=warp
  final int beatsPerBar;
  final int beatUnit;

  const SamplerInfo({
    required this.durationSeconds,
    required this.sampleRate,
    required this.loopEnabled,
    required this.loopStartSeconds,
    required this.loopEndSeconds,
    required this.rootNote,
    required this.attackMs,
    required this.releaseMs,
    this.volumeDb = 0.0,
    this.transposeSemitones = 0,
    this.fineCents = 0,
    this.reversed = false,
    this.originalBpm = 120.0,
    this.warpEnabled = false,
    this.warpMode = 0,
    this.beatsPerBar = 4,
    this.beatUnit = 4,
  });
}
