//! Audio health: dropout and lock-wait counters, so "it crackled" comes with data.
//!
//! The audio thread only bumps atomics here (no I/O, no allocation, no waiting).
//! The UI reads them about once a second ([`snapshot`]) and writes the log.
//!
//! A dropout is counted two ways:
//! - **late**: rendering a buffer took longer than the buffer lasts, so the
//!   device ran dry (Boojy's own work was too slow);
//! - **missed**: the device's playback timestamps skipped one or more buffers
//!   (a stall from anywhere, including the OS or another app).

use parking_lot::{Mutex, MutexGuard};
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::time::{Duration, Instant};

static LATE_BUFFERS: AtomicU64 = AtomicU64::new(0);
static MISSED_BUFFERS: AtomicU64 = AtomicU64::new(0);
/// Busiest buffer since the last [`snapshot`], as render time ÷ buffer time × 1000.
static PEAK_LOAD_PERMILLE: AtomicU32 = AtomicU32::new(0);

/// Times the audio thread found a lock held (by the UI) and had to wait.
pub(crate) static SYNTH_LOCK_WAITS: AtomicU64 = AtomicU64::new(0);
pub(crate) static EFFECT_LOCK_WAITS: AtomicU64 = AtomicU64::new(0);
pub(crate) static TRACK_LOCK_WAITS: AtomicU64 = AtomicU64::new(0);
pub(crate) static RECORDER_LOCK_WAITS: AtomicU64 = AtomicU64::new(0);

/// Gaps longer than this are a sleep/wake or a stream restart, not a crackle.
const MAX_COUNTED_GAP: Duration = Duration::from_secs(2);

/// Lock `mutex`, counting a wait in `waits` when it's already held.
#[inline]
pub(crate) fn lock_or_count<'a, T>(mutex: &'a Mutex<T>, waits: &AtomicU64) -> MutexGuard<'a, T> {
    mutex.try_lock().unwrap_or_else(|| {
        waits.fetch_add(1, Ordering::Relaxed);
        mutex.lock()
    })
}

/// Render time as a share of the buffer's duration, in thousandths.
fn load_permille(elapsed: Duration, budget: Duration) -> u32 {
    if budget.is_zero() {
        return 0;
    }
    let permille = elapsed.as_nanos() * 1000 / budget.as_nanos();
    u32::try_from(permille).unwrap_or(u32::MAX)
}

/// Buffers skipped when two callbacks are `gap` apart and the longer of their
/// two buffers lasts `expected`. Jitter under half a buffer is normal; gaps
/// over [`MAX_COUNTED_GAP`] are ignored.
fn missed_buffers(gap: Duration, expected: Duration) -> u64 {
    if expected.is_zero() || gap > MAX_COUNTED_GAP {
        return 0;
    }
    let buffers = gap.as_secs_f64() / expected.as_secs_f64();
    if buffers < 1.5 {
        return 0;
    }
    buffers.round() as u64 - 1
}

fn buffer_duration(frames: usize, sample_rate: u32) -> Duration {
    if sample_rate == 0 {
        return Duration::ZERO;
    }
    Duration::from_secs_f64(frames as f64 / f64::from(sample_rate))
}

/// Times one audio callback; records its load (and a late buffer) when dropped,
/// so every return path out of the callback is covered.
pub(crate) struct BufferTimer {
    started: Instant,
    budget: Duration,
}

impl BufferTimer {
    pub(crate) fn start(frames: usize, sample_rate: u32) -> Self {
        Self {
            started: Instant::now(),
            budget: buffer_duration(frames, sample_rate),
        }
    }
}

impl Drop for BufferTimer {
    fn drop(&mut self) {
        let load = load_permille(self.started.elapsed(), self.budget);
        PEAK_LOAD_PERMILLE.fetch_max(load, Ordering::Relaxed);
        if load > 1000 {
            LATE_BUFFERS.fetch_add(1, Ordering::Relaxed);
        }
    }
}

/// Watches the time between callbacks for skipped buffers. One per stream,
/// owned by its callback.
///
/// Uses cpal's *callback* time, not its *playback* time: on both macOS and
/// Windows cpal sets playback = callback + this buffer's length, so playback
/// gaps jump whenever the buffer size changes (Windows varies it). Callbacks
/// are expected the longer of the two buffers apart: macOS paces them by the
/// previous buffer, while Windows tops its buffer up each time, so the gap
/// matches what was played since, the current buffer. A short Windows
/// underrun can slip under that; a stall can't.
pub(crate) struct GapDetector {
    sample_rate: u32,
    last_callback: Option<cpal::StreamInstant>,
    last_frames: usize,
}

impl GapDetector {
    pub(crate) fn new(sample_rate: u32) -> Self {
        Self {
            sample_rate,
            last_callback: None,
            last_frames: 0,
        }
    }

    pub(crate) fn on_callback(&mut self, callback: cpal::StreamInstant, frames: usize) {
        let gap = self
            .last_callback
            .and_then(|last| callback.duration_since(&last));
        self.last_callback = Some(callback);
        let missed = self.missed_since_last(gap, frames);
        if missed > 0 {
            MISSED_BUFFERS.fetch_add(missed, Ordering::Relaxed);
        }
    }

    /// Buffers skipped before this callback, `gap` after the last one (none
    /// for the first callback).
    fn missed_since_last(&mut self, gap: Option<Duration>, frames: usize) -> u64 {
        let last = buffer_duration(self.last_frames, self.sample_rate);
        self.last_frames = frames;
        let Some(gap) = gap else { return 0 };
        missed_buffers(gap, last.max(buffer_duration(frames, self.sample_rate)))
    }
}

/// Counters as the UI sees them. All are totals since launch except
/// `peak_load_percent`, which covers the time since the previous snapshot,
/// and the buffer size and rate the stream runs at now.
#[derive(Debug, Clone, Copy, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AudioHealthSnapshot {
    pub late_buffers: u64,
    pub missed_buffers: u64,
    pub peak_load_percent: u32,
    pub synth_lock_waits: u64,
    pub effect_lock_waits: u64,
    pub track_lock_waits: u64,
    pub recorder_lock_waits: u64,
    pub buffer_frames: u32,
    pub sample_rate: u32,
}

/// Read the counters (and reset the peak load).
pub(crate) fn snapshot(buffer_frames: u32, sample_rate: u32) -> AudioHealthSnapshot {
    AudioHealthSnapshot {
        late_buffers: LATE_BUFFERS.load(Ordering::Relaxed),
        missed_buffers: MISSED_BUFFERS.load(Ordering::Relaxed),
        peak_load_percent: PEAK_LOAD_PERMILLE.swap(0, Ordering::Relaxed) / 10,
        synth_lock_waits: SYNTH_LOCK_WAITS.load(Ordering::Relaxed),
        effect_lock_waits: EFFECT_LOCK_WAITS.load(Ordering::Relaxed),
        track_lock_waits: TRACK_LOCK_WAITS.load(Ordering::Relaxed),
        recorder_lock_waits: RECORDER_LOCK_WAITS.load(Ordering::Relaxed),
        buffer_frames,
        sample_rate,
    }
}

#[cfg(test)]
mod tests {
    use super::{load_permille, lock_or_count, missed_buffers, GapDetector};
    use parking_lot::Mutex;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::Duration;

    fn ms(n: f64) -> Duration {
        Duration::from_secs_f64(n / 1000.0)
    }

    #[test]
    fn a_buffer_that_takes_longer_than_it_lasts_is_over_100_percent() {
        assert_eq!(load_permille(ms(5.0), ms(10.0)), 500);
        assert_eq!(load_permille(ms(10.0), ms(10.0)), 1000);
        assert!(load_permille(ms(11.0), ms(10.0)) > 1000);
        assert_eq!(load_permille(ms(5.0), Duration::ZERO), 0);
    }

    #[test]
    fn steady_callbacks_miss_nothing() {
        assert_eq!(missed_buffers(ms(5.33), ms(5.33)), 0);
        // Timing jitter under half a buffer is normal.
        assert_eq!(missed_buffers(ms(7.0), ms(5.33)), 0);
    }

    #[test]
    fn a_skipped_buffer_is_counted() {
        assert_eq!(missed_buffers(ms(10.67), ms(5.33)), 1);
        assert_eq!(missed_buffers(ms(21.3), ms(5.33)), 3);
    }

    #[test]
    fn a_skipped_device_cycle_is_counted_at_a_steady_buffer_size() {
        // macOS: callbacks one 256-frame buffer apart, then one cycle lost.
        let mut detector = GapDetector::new(48_000);
        assert_eq!(detector.missed_since_last(None, 256), 0);
        assert_eq!(detector.missed_since_last(Some(ms(5.33)), 256), 0);
        assert_eq!(detector.missed_since_last(Some(ms(10.67)), 256), 1);
    }

    #[test]
    fn changing_buffer_sizes_are_not_dropouts() {
        // Windows hands out variable sizes: 96 frames, then 192 frames 4 ms
        // later, is a healthy stream (review of #204).
        let mut detector = GapDetector::new(48_000);
        assert_eq!(detector.missed_since_last(None, 96), 0);
        assert_eq!(detector.missed_since_last(Some(ms(4.0)), 192), 0);
        // macOS-style pacing by the previous buffer when the size drops.
        assert_eq!(detector.missed_since_last(Some(ms(4.0)), 96), 0);
    }

    #[test]
    fn sleep_or_restart_gaps_are_not_dropouts() {
        assert_eq!(missed_buffers(Duration::from_secs(30), ms(5.33)), 0);
        assert_eq!(missed_buffers(ms(10.0), Duration::ZERO), 0);
    }

    #[test]
    fn lock_or_count_counts_only_when_the_lock_is_held() {
        let mutex = Mutex::new(0);
        let waits = AtomicU64::new(0);
        drop(lock_or_count(&mutex, &waits));
        assert_eq!(waits.load(Ordering::Relaxed), 0);

        let held = mutex.lock();
        std::thread::scope(|s| {
            let waiter = s.spawn(|| *lock_or_count(&mutex, &waits) + 1);
            while waits.load(Ordering::Relaxed) == 0 {
                std::thread::yield_now();
            }
            drop(held);
            assert_eq!(waiter.join().unwrap(), 1);
        });
        assert_eq!(waits.load(Ordering::Relaxed), 1);
    }
}
