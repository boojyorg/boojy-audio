//! Offline renders checked for their content, not just "finite and audible":
//! every sample plays once and in order, clip edits meet without gaps or
//! repeats, levels land where the fader and pan say, and nothing clicks.
//! Export renders through `render_offline`, so these are export checks too.

use super::AudioGraph;
use crate::audio_checks::{
    assert_valid, channel, clicks, decode_ramp, longest_silence, ramp_clip, ramp_mismatches,
    seconds, sine_clip,
};
use crate::audio_file::{AudioClip, TARGET_SAMPLE_RATE};
use crate::track::{AutomationPoint, ClipId, TimelineClip, TrackId, TrackType};
use std::sync::Arc;

const SR: usize = TARGET_SAMPLE_RATE as usize;

/// A fresh graph (master included) with one audio track at default settings.
fn graph_with_track() -> (AudioGraph, TrackId) {
    let graph = AudioGraph::new().unwrap();
    let track = graph
        .track_manager
        .lock()
        .create_track(TrackType::Audio, "Audio".into());
    (graph, track)
}

fn place(
    graph: &AudioGraph,
    track: TrackId,
    clip: Arc<AudioClip>,
    start: f64,
    offset: f64,
    duration: Option<f64>,
) -> ClipId {
    graph
        .add_clip_to_track_with_params(track, clip, start, offset, duration)
        .expect("track exists")
}

fn edit_clip(graph: &AudioGraph, track: TrackId, id: ClipId, edit: impl FnOnce(&mut TimelineClip)) {
    let tm = graph.track_manager.lock();
    let track_arc = tm.get_track(track).unwrap();
    let mut track = track_arc.lock();
    edit(track.audio_clips.iter_mut().find(|c| c.id == id).unwrap());
}

fn edit_track(graph: &AudioGraph, track: TrackId, edit: impl FnOnce(&mut crate::track::Track)) {
    let tm = graph.track_manager.lock();
    edit(&mut tm.get_track(track).unwrap().lock());
}

/// Render exactly `frames` frames of the full mix.
fn render(graph: &AudioGraph, frames: usize) -> Vec<f32> {
    let buf = graph.render_offline(seconds(frames));
    assert_eq!(buf.len(), frames * 2, "render length in samples");
    buf
}

/// Gain after the clip on each channel: fader × pan × master × master balance,
/// in the renderer's order.
fn post_gains(graph: &AudioGraph, track: TrackId) -> (f32, f32) {
    let tm = graph.track_manager.lock();
    let t = tm.get_track(track).unwrap();
    let t = t.lock();
    let m = tm.get_track(0).unwrap();
    let m = m.lock();
    let (pl, pr) = t.get_pan_gains();
    let (ml, mr) = m.get_pan_gains();
    (
        t.get_gain() * pl * m.get_gain() * ml,
        t.get_gain() * pr * m.get_gain() * mr,
    )
}

/// Why a rendered ramp clip doesn't play exactly `expected` source frames on
/// both channels, or `None` if it does.
fn ramp_problem(
    buf: &[f32],
    gains: (f32, f32),
    expected: &[Option<usize>],
    what: &str,
) -> Option<String> {
    assert_valid(buf, what);
    // The ramp is positive on the left, negative on the right.
    [(0, gains.0), (1, -gains.1)].into_iter().find_map(|(ch, gain)| {
        let got = decode_ramp(&channel(buf, ch), gain);
        let (count, first) = ramp_mismatches(&got, expected);
        (count > 0).then(|| {
            format!("{what}, channel {ch}: {count} frames wrong; first (frame, expected, got): {first:?}")
        })
    })
}

fn assert_ramp(buf: &[f32], gains: (f32, f32), expected: &[Option<usize>], what: &str) {
    if let Some(problem) = ramp_problem(buf, gains, expected, what) {
        panic!("{problem}");
    }
}

/// `Some(source frame)` across a clip's span, silence elsewhere.
fn span(
    total: usize,
    start: usize,
    source: impl Fn(usize) -> usize,
    len: usize,
) -> Vec<Option<usize>> {
    (0..total)
        .map(|f| (f >= start && f < start + len).then(|| source(f - start)))
        .collect()
}

#[test]
fn full_mix_plays_every_sample_once_and_in_order() {
    // Awkward start frames are the ones whose seconds value doesn't convert
    // back to a whole frame exactly.
    for start in [0, 59_253, 96_001] {
        let (graph, track) = graph_with_track();
        let len = 3 * SR;
        place(&graph, track, ramp_clip(len, 2), seconds(start), 0.0, None);
        let total = start + len + 1_000;
        let buf = render(&graph, total);
        assert_ramp(
            &buf,
            post_gains(&graph, track),
            &span(total, start, |i| i, len),
            &format!("clip at frame {start}"),
        );
    }
}

#[test]
fn mono_clip_plays_on_both_channels() {
    let (graph, track) = graph_with_track();
    let len = SR;
    place(&graph, track, ramp_clip(len, 1), 0.0, 0.0, None);
    let buf = render(&graph, len);
    let (gl, gr) = post_gains(&graph, track);
    let expected = span(len, 0, |i| i, len);
    for (ch, gain) in [(0, gl), (1, gr)] {
        let (count, first) = ramp_mismatches(&decode_ramp(&channel(&buf, ch), gain), &expected);
        assert_eq!(count, 0, "mono clip, channel {ch}: first wrong {first:?}");
    }
}

/// A clip edit: (what, edit, frames on the timeline, source frame for
/// timeline frame `i`).
type Case = (
    &'static str,
    Box<dyn Fn(&mut TimelineClip)>,
    usize,
    Box<dyn Fn(usize) -> usize>,
);

#[test]
fn clip_edits_play_the_right_source_frames() {
    let len = 2 * SR;
    let start = 59_253;
    let cases: Vec<Case> = vec![
        (
            "reversed",
            Box::new(|c| c.reversed = true),
            len,
            Box::new(move |i| len - 1 - i),
        ),
        (
            "warp, stretched audio ready",
            Box::new(move |c| {
                c.warp_enabled = true;
                c.warp_mode = 0;
                c.stretch_factor = 2.0;
                // Stand-in for the time-stretched audio: half as long.
                c.stretched_cache = Some(ramp_clip(len / 2, 2));
            }),
            len / 2,
            Box::new(|i| i),
        ),
        (
            "warp, stretched audio not ready yet",
            Box::new(|c| {
                c.warp_enabled = true;
                c.warp_mode = 0;
                c.stretch_factor = 2.0;
            }),
            len / 2,
            Box::new(|i| 2 * i),
        ),
        (
            "re-pitch at double speed",
            Box::new(|c| {
                c.warp_enabled = true;
                c.warp_mode = 1;
                c.stretch_factor = 2.0;
            }),
            len / 2,
            Box::new(|i| 2 * i),
        ),
        (
            // Transpose changes pitch, never the read speed (the pitch shift
            // lives in the processed audio, which this edit doesn't build).
            "transposed up an octave",
            Box::new(|c| c.transpose_semitones = 12),
            len,
            Box::new(|i| i),
        ),
    ];

    let problems: Vec<String> = cases
        .into_iter()
        .filter_map(|(what, edit, played, source)| {
            let (graph, track) = graph_with_track();
            let id = place(&graph, track, ramp_clip(len, 2), seconds(start), 0.0, None);
            edit_clip(&graph, track, id, edit);
            let total = start + len + 1_000;
            let buf = render(&graph, total);
            ramp_problem(
                &buf,
                post_gains(&graph, track),
                &span(total, start, source, played),
                what,
            )
        })
        .collect();
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn trimmed_clip_edits_play_the_right_source_frames() {
    // A clip trimmed to its source's 0.5–1.5 s: the trim is in seconds of the
    // clip's own audio, so warp must stretch what plays from there, not the
    // trim too (the right half of a split warped clip played the wrong part).
    let len = 2 * SR;
    let start = 59_253;
    let trim = SR / 2;
    let kept = SR;
    let cases: Vec<Case> = vec![
        ("plain", Box::new(|_| {}), kept, Box::new(move |i| trim + i)),
        (
            "reversed",
            Box::new(|c| c.reversed = true),
            kept,
            Box::new(move |i| trim + kept - 1 - i),
        ),
        (
            "warp, stretched audio ready",
            Box::new(move |c| {
                c.warp_enabled = true;
                c.warp_mode = 0;
                c.stretch_factor = 2.0;
                c.stretched_cache = Some(ramp_clip(len / 2, 2));
            }),
            kept / 2,
            // The stand-in stretched audio counts its own frames.
            Box::new(move |i| trim / 2 + i),
        ),
        (
            "re-pitch at double speed",
            Box::new(|c| {
                c.warp_enabled = true;
                c.warp_mode = 1;
                c.stretch_factor = 2.0;
            }),
            kept / 2,
            Box::new(move |i| trim + 2 * i),
        ),
        (
            "re-pitch at double speed, reversed",
            Box::new(|c| {
                c.warp_enabled = true;
                c.warp_mode = 1;
                c.stretch_factor = 2.0;
                c.reversed = true;
            }),
            kept / 2,
            Box::new(move |i| trim + 2 * (kept / 2 - 1 - i)),
        ),
    ];

    let problems: Vec<String> = cases
        .into_iter()
        .filter_map(|(what, edit, played, source)| {
            let (graph, track) = graph_with_track();
            let id = place(
                &graph,
                track,
                ramp_clip(len, 2),
                seconds(start),
                seconds(trim),
                Some(seconds(kept)),
            );
            edit_clip(&graph, track, id, edit);
            let total = start + len + 1_000;
            let buf = render(&graph, total);
            ramp_problem(
                &buf,
                post_gains(&graph, track),
                &span(total, start, source, played),
                what,
            )
        })
        .collect();
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn split_clip_plays_seamlessly() {
    // Splitting keeps the left part (duration cut at the split) and adds a
    // right part starting at the split with a matching offset. Played back,
    // the two halves must be the original: every frame once, no gap, no
    // doubled frame where they meet.
    let len = 3 * SR;
    let start = 12_000;
    // Split points: a frame-aligned beat, one beat at 97 BPM (between frames
    // and inexact in binary), and an awkward frame.
    for split in [
        seconds(start) + 1.5,
        60.0 / 97.0 + seconds(start),
        seconds(71_111),
    ] {
        let (graph, track) = graph_with_track();
        let clip = ramp_clip(len, 2);
        let left = split - seconds(start);
        place(&graph, track, clip.clone(), seconds(start), 0.0, Some(left));
        place(
            &graph,
            track,
            clip.clone(),
            split,
            left,
            Some(clip.duration_seconds - left),
        );
        let total = start + len + 1_000;
        let buf = render(&graph, total);
        assert_ramp(
            &buf,
            post_gains(&graph, track),
            &span(total, start, |i| i, len),
            &format!("split at {split}s"),
        );
    }
}

#[test]
fn back_to_back_clips_meet_without_gap_or_overlap() {
    // A clip and its duplicate placed right after it (start + length).
    let len = 48_017; // not a round number of milliseconds
    for start in [0, 59_253] {
        let (graph, track) = graph_with_track();
        let clip = ramp_clip(len, 2);
        let first = seconds(start);
        place(&graph, track, clip.clone(), first, 0.0, None);
        place(
            &graph,
            track,
            clip.clone(),
            first + clip.duration_seconds,
            0.0,
            None,
        );
        let total = start + 2 * len + 1_000;
        let buf = render(&graph, total);
        let expected: Vec<Option<usize>> = (0..total)
            .map(|f| (f >= start && f < start + 2 * len).then(|| (f - start) % len))
            .collect();
        assert_ramp(
            &buf,
            post_gains(&graph, track),
            &expected,
            &format!("back to back from frame {start}"),
        );
    }
}

#[test]
fn levels_follow_fader_pan_and_master() {
    // Expected gains are written out from the pan laws, not read back from
    // the engine: tracks pan with constant power (−3 dB each side at
    // centre), the master is a balance (unity at centre).
    let db = |d: f32| 10f32.powf(d / 20.0);
    let centre = std::f32::consts::FRAC_1_SQRT_2;
    // (what, fader dB, pan, master dB, master pan, expected L, expected R)
    let cases = [
        ("defaults", 0.0, 0.0, 0.0, 0.0, centre, centre),
        (
            "fader −6 dB",
            -6.0,
            0.0,
            0.0,
            0.0,
            centre * db(-6.0),
            centre * db(-6.0),
        ),
        ("hard left", 0.0, -1.0, 0.0, 0.0, 1.0, 0.0),
        ("hard right", 0.0, 1.0, 0.0, 0.0, 0.0, 1.0),
        (
            "master −12 dB",
            0.0,
            0.0,
            -12.0,
            0.0,
            centre * db(-12.0),
            centre * db(-12.0),
        ),
        (
            "master balance half left",
            0.0,
            0.0,
            0.0,
            -0.5,
            centre,
            centre * 0.5,
        ),
        ("fader at the bottom", -96.0, 0.0, 0.0, 0.0, 0.0, 0.0),
    ];
    for (what, fader, pan, master_db, master_pan, want_l, want_r) in cases {
        let (graph, track) = graph_with_track();
        place(&graph, track, ramp_clip(SR / 10, 1), 0.0, 0.0, None);
        edit_track(&graph, track, |t| {
            t.volume_db = fader;
            t.pan = pan;
        });
        edit_track(&graph, 0, |m| {
            m.volume_db = master_db;
            m.pan = master_pan;
        });
        let buf = render(&graph, SR / 10);
        let source = ramp_clip(SR / 10, 1);
        for (ch, want) in [(0, want_l), (1, want_r)] {
            let got = channel(&buf, ch);
            let worst = got
                .iter()
                .zip(&source.samples)
                .map(|(g, s)| (g - s * want).abs())
                .fold(0.0f32, f32::max);
            assert!(
                worst < 1e-6,
                "{what}, channel {ch}: expected gain {want}, off by up to {worst}"
            );
        }
    }
}

#[test]
fn mute_and_solo_silence_the_right_tracks() {
    let (graph, a) = graph_with_track();
    let b = graph
        .track_manager
        .lock()
        .create_track(TrackType::Audio, "B".into());
    place(&graph, a, ramp_clip(SR / 10, 2), 0.0, 0.0, None);
    place(&graph, b, sine_clip(SR / 10, 440.0, 0.5), 0.0, 0.0, None);
    let expected = span(SR / 10, 0, |i| i, SR / 10);

    // Muting B leaves exactly A's ramp.
    edit_track(&graph, b, |t| t.mute = true);
    assert_ramp(
        &render(&graph, SR / 10),
        post_gains(&graph, a),
        &expected,
        "B muted",
    );

    // Soloing A (B unmuted) also leaves exactly A.
    edit_track(&graph, b, |t| t.mute = false);
    edit_track(&graph, a, |t| t.solo = true);
    assert_ramp(
        &render(&graph, SR / 10),
        post_gains(&graph, a),
        &expected,
        "A soloed",
    );

    // Muting the soloed track leaves silence.
    edit_track(&graph, a, |t| t.mute = true);
    let buf = render(&graph, SR / 10);
    assert!(
        buf.iter().all(|&s| s == 0.0),
        "muted solo track must be silent"
    );
}

#[test]
fn midi_notes_start_on_their_frame_wherever_the_clip_starts() {
    use crate::midi::{MidiClip, MidiEvent};

    // First audible frame of a note at clip frame 1000, for a clip at `start`.
    let onset = |start: usize| -> usize {
        let graph = AudioGraph::new().unwrap();
        let track = graph
            .track_manager
            .lock()
            .create_track(TrackType::Midi, "Synth".into());
        graph.track_synth_manager.lock().create_synth(track);
        let clip = MidiClip::with_events(
            vec![
                MidiEvent::note_on(60, 100, 1_000),
                MidiEvent::note_off(60, 0, 1_000 + SR as u64),
            ],
            TARGET_SAMPLE_RATE,
        );
        graph
            .add_midi_clip_to_track(track, Arc::new(clip), seconds(start), 0)
            .unwrap();
        let buf = render(&graph, start + 4_000);
        channel(&buf, 0)
            .iter()
            .position(|&s| s != 0.0)
            .expect("note is audible")
    };

    let at_zero = onset(0);
    for start in [59_253, 96_001, 123_457] {
        assert_eq!(
            onset(start),
            start + at_zero,
            "note in a clip at frame {start} must start {at_zero} frames after its own position"
        );
    }
}

#[test]
fn volume_automation_across_render_blocks_is_click_free() {
    // A steady tone under a 4 s fade: the render runs in 512-frame blocks,
    // and fader automation is applied per frame, so the waveform must stay
    // as smooth as the tone itself — no step at block edges, no gaps.
    let (graph, track) = graph_with_track();
    let len = 4 * SR;
    let (hz, amp) = (220.0, 0.5);
    place(&graph, track, sine_clip(len, hz, amp), 0.0, 0.0, None);
    edit_track(&graph, track, |t| {
        t.volume_automation = vec![
            AutomationPoint {
                time_seconds: 0.0,
                value_db: 0.0,
            },
            AutomationPoint {
                time_seconds: 4.0,
                value_db: -20.0,
            },
        ];
    });
    let buf = render(&graph, len);
    assert_valid(&buf, "faded tone");
    let left = channel(&buf, 0);
    let (gain, _) = post_gains(&graph, track); // fader at its 0 dB start
    let steepest = (std::f64::consts::TAU * hz * f64::from(amp)) as f32 * gain / SR as f32;
    let found = clicks(&left, steepest * 1.01);
    assert!(
        found.is_empty(),
        "clicks at frames {:?}",
        &found[..found.len().min(5)]
    );
    assert!(longest_silence(&left[1..]) <= 1, "dropout inside the tone");
}

#[test]
fn busy_mix_with_effects_and_sends_stays_valid() {
    // Everything at once, deliberately too loud: tracks summing well over
    // full scale, every built-in effect, a send to a reverb return, and a
    // synth. The export must stay finite and inside ±1 (the master limiter's
    // job) with no dropout in the always-playing tone.
    use crate::effects::{Chorus, Compressor, Delay, EffectType, ParametricEQ, Reverb};
    use crate::midi::{MidiClip, MidiEvent};

    let (graph, tone) = graph_with_track();
    let len = 6 * SR;
    let (drums, synth, ret) = {
        let mut tm = graph.track_manager.lock();
        (
            tm.create_track(TrackType::Audio, "Loud".into()),
            tm.create_track(TrackType::Midi, "Synth".into()),
            tm.create_track(TrackType::Return, "Verb".into()),
        )
    };
    graph.track_synth_manager.lock().create_synth(synth);
    place(&graph, tone, sine_clip(len, 110.0, 0.9), 0.0, 0.0, None);
    place(&graph, drums, sine_clip(len, 3_000.0, 1.0), 0.5, 0.0, None);
    let notes: Vec<MidiEvent> = (0..24u8)
        .flat_map(|n| {
            let at = u64::from(n) * (SR as u64 / 4);
            [
                MidiEvent::note_on(48 + n, 127, at),
                MidiEvent::note_off(48 + n, 0, at + 9_000),
            ]
        })
        .collect();
    graph
        .add_midi_clip_to_track(
            synth,
            Arc::new(MidiClip::with_events(notes, TARGET_SAMPLE_RATE)),
            0.0,
            0,
        )
        .unwrap();

    let chains = [
        (
            tone,
            vec![
                EffectType::EQ(ParametricEQ::new()),
                EffectType::Compressor(Compressor::new()),
            ],
        ),
        (
            drums,
            vec![
                EffectType::Delay(Delay::new()),
                EffectType::Chorus(Chorus::new()),
            ],
        ),
        (synth, vec![EffectType::Reverb(Reverb::new())]),
        (ret, vec![EffectType::Reverb(Reverb::new())]),
    ];
    for (track, effects) in chains {
        let ids: Vec<u64> = {
            let mut em = graph.effect_manager.lock();
            effects.into_iter().map(|fx| em.create_effect(fx)).collect()
        };
        edit_track(&graph, track, |t| t.fx_chain.extend(ids));
    }
    for (track, gain_db) in [(tone, 6.0), (drums, 6.0), (synth, 6.0)] {
        edit_track(&graph, track, |t| {
            t.volume_db = gain_db;
            t.sends.push(crate::track::Send {
                target_track_id: ret,
                amount: 1.0,
                pre_fader: false,
            });
        });
    }

    let buf = render(&graph, len);
    assert_valid(&buf, "busy mix");
    assert!(
        longest_silence(&channel(&buf, 0)[1..]) <= 1,
        "dropout in a mix that never stops playing"
    );
}
