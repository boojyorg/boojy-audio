/// Audio engine performance benchmarks.
///
/// Run with: `cargo bench` from the engine directory.
/// Results are written to `target/criterion/` with HTML reports.
///
/// The audio callback budget at 48 kHz / 256 samples is ~5.33 ms.
/// These benchmarks measure individual components so you can see
/// how much of that budget each piece consumes.
use criterion::{black_box, criterion_group, criterion_main, Criterion, BenchmarkId};
use engine::audio_file::TARGET_SAMPLE_RATE;
use engine::effects::{
    Chorus, Compressor, Delay, Effect, Limiter, ParametricEQ, Reverb,
};
use engine::synth::{Synth, TrackSynthManager};

const BUFFER_SIZE: usize = 256;

// ── Effects benchmarks ──────────────────────────────────────────────────

fn bench_effects(c: &mut Criterion) {
    let mut group = c.benchmark_group("effects");

    // Benchmark each effect processing one buffer (256 stereo frames)
    group.bench_function("parametric_eq/256", |b| {
        let mut eq = ParametricEQ::new();
        b.iter(|| {
            for _ in 0..BUFFER_SIZE {
                black_box(eq.process_frame(0.5, 0.5));
            }
        });
    });

    group.bench_function("compressor/256", |b| {
        let mut comp = Compressor::new();
        b.iter(|| {
            for _ in 0..BUFFER_SIZE {
                black_box(comp.process_frame(0.5, 0.5));
            }
        });
    });

    group.bench_function("reverb/256", |b| {
        let mut reverb = Reverb::new();
        b.iter(|| {
            for _ in 0..BUFFER_SIZE {
                black_box(reverb.process_frame(0.5, 0.5));
            }
        });
    });

    group.bench_function("delay/256", |b| {
        let mut delay = Delay::new();
        b.iter(|| {
            for _ in 0..BUFFER_SIZE {
                black_box(delay.process_frame(0.5, 0.5));
            }
        });
    });

    group.bench_function("chorus/256", |b| {
        let mut chorus = Chorus::new();
        b.iter(|| {
            for _ in 0..BUFFER_SIZE {
                black_box(chorus.process_frame(0.5, 0.5));
            }
        });
    });

    group.bench_function("limiter/256", |b| {
        let mut limiter = Limiter::new();
        b.iter(|| {
            for _ in 0..BUFFER_SIZE {
                black_box(limiter.process_frame(0.5, 0.5));
            }
        });
    });

    group.finish();
}

// ── Effect chain benchmarks (simulates N effects per track) ─────────────

fn bench_effect_chain(c: &mut Criterion) {
    let mut group = c.benchmark_group("effect_chain");

    for chain_len in [1, 2, 4, 8] {
        group.bench_with_input(
            BenchmarkId::new("effects_per_track", chain_len),
            &chain_len,
            |b, &n| {
                // Build a typical chain: EQ + Compressor + Reverb + ...
                let mut effects: Vec<Box<dyn Effect>> = Vec::new();
                for i in 0..n {
                    let effect: Box<dyn Effect> = match i % 4 {
                        0 => Box::new(ParametricEQ::new()),
                        1 => Box::new(Compressor::new()),
                        2 => Box::new(Reverb::new()),
                        _ => Box::new(Delay::new()),
                    };
                    effects.push(effect);
                }

                b.iter(|| {
                    for _ in 0..BUFFER_SIZE {
                        let mut l = 0.5_f32;
                        let mut r = 0.5_f32;
                        for effect in &mut effects {
                            let (ol, or) = effect.process_frame(l, r);
                            l = ol;
                            r = or;
                        }
                        black_box((l, r));
                    }
                });
            },
        );
    }

    group.finish();
}

// ── Synth polyphony benchmarks ──────────────────────────────────────────

fn bench_synth(c: &mut Criterion) {
    let mut group = c.benchmark_group("synth");

    for voice_count in [1, 4, 8] {
        group.bench_with_input(
            BenchmarkId::new("voices", voice_count),
            &voice_count,
            |b, &n| {
                let mut synth = Synth::new(TARGET_SAMPLE_RATE as f32);
                // Trigger N notes
                for i in 0..n {
                    synth.note_on(60 + i as u8, 100);
                }

                b.iter(|| {
                    for _ in 0..BUFFER_SIZE {
                        black_box(synth.process_sample());
                    }
                });
            },
        );
    }

    group.finish();
}

// ── Multi-track mix benchmarks (simulates N tracks of synth output) ─────

fn bench_track_mixing(c: &mut Criterion) {
    let mut group = c.benchmark_group("track_mixing");

    for track_count in [4, 16, 32, 64] {
        group.bench_with_input(
            BenchmarkId::new("tracks", track_count),
            &track_count,
            |b, &n| {
                let mut mgr = TrackSynthManager::new(TARGET_SAMPLE_RATE as f32);
                // Create N tracks, each with a synth playing one note
                for i in 0..n {
                    mgr.create_synth(i as u64);
                    mgr.note_on(i as u64, 60 + (i % 12) as u8, 100);
                }

                b.iter(|| {
                    for _ in 0..BUFFER_SIZE {
                        let mut mix_l = 0.0_f32;
                        let mut mix_r = 0.0_f32;
                        for track_id in 0..n {
                            let (l, r) = mgr.process_sample_stereo(track_id as u64);
                            mix_l += l;
                            mix_r += r;
                        }
                        black_box((mix_l, mix_r));
                    }
                });
            },
        );
    }

    group.finish();
}

// ── Full signal path benchmark (tracks + effects + limiter) ─────────────

fn bench_full_signal_path(c: &mut Criterion) {
    let mut group = c.benchmark_group("full_signal_path");

    for track_count in [4, 16, 32] {
        group.bench_with_input(
            BenchmarkId::new("tracks_with_fx", track_count),
            &track_count,
            |b, &n| {
                let mut mgr = TrackSynthManager::new(TARGET_SAMPLE_RATE as f32);
                // Per-track effect chains (EQ + Compressor)
                let mut track_fx: Vec<(Box<dyn Effect>, Box<dyn Effect>)> = Vec::new();

                for i in 0..n {
                    mgr.create_synth(i as u64);
                    mgr.note_on(i as u64, 60 + (i % 12) as u8, 100);
                    track_fx.push((
                        Box::new(ParametricEQ::new()),
                        Box::new(Compressor::new()),
                    ));
                }

                let mut master_limiter = Limiter::new();

                b.iter(|| {
                    for _ in 0..BUFFER_SIZE {
                        let mut mix_l = 0.0_f32;
                        let mut mix_r = 0.0_f32;

                        for (i, (eq, comp)) in track_fx.iter_mut().enumerate() {
                            let (mut l, mut r) = mgr.process_sample_stereo(i as u64);
                            // FX chain
                            let (el, er) = eq.process_frame(l, r);
                            l = el;
                            r = er;
                            let (cl, cr) = comp.process_frame(l, r);
                            // Apply volume (0.7) and pan (center)
                            mix_l += cl * 0.7;
                            mix_r += cr * 0.7;
                        }

                        // Master limiter
                        black_box(master_limiter.process_frame(mix_l, mix_r));
                    }
                });
            },
        );
    }

    group.finish();
}

criterion_group!(
    benches,
    bench_effects,
    bench_effect_chain,
    bench_synth,
    bench_track_mixing,
    bench_full_signal_path,
);
criterion_main!(benches);
