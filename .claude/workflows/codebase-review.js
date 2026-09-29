export const meta = {
  name: 'codebase-review',
  description:
    'Whole-app correctness audit: parallel subsystem reads → adversarial verification (skeptics try to refute each candidate) → synthesized 8/10 scorecard + ranked backlog mapped to v0.7/later. Model-tiered for cost (readers Sonnet, verifiers Haiku, synthesis Opus). Mirrors docs/archive/reviews/2026_05_29_codebase_review.md.',
  whenToUse:
    'At a MAJOR boundary (pre-1.0, or once per minor-version family) to pick the next correctness/hardening theme — not every patch. Heavy (~$30-50 tiered). Run gates green first; save the returned report to docs/reviews/. Tune VERIFIERS/DROP_IF_REFUTED for stricter/looser confirmation.',
  phases: [
    { title: 'Read', detail: 'one read-only reader per subsystem (Sonnet)' },
    { title: 'Verify', detail: 'N skeptics try to refute each candidate (Haiku)' },
    { title: 'Synthesize', detail: 'scorecard + backlog + theme (Opus)' },
  ],
}

// Subsystems mirror the §-structure of the 2026-05-29 review. Edit as the app grows.
const SUBSYSTEMS = [
  { key: 'engine-realtime', focus: 'Rust realtime audio path: renderer.rs, audio_graph/, device mgmt. Sample-rate/channel assumptions, locks on the audio thread, NaN/Inf guards, per-callback allocation.' },
  { key: 'engine-dsp', focus: 'Rust DSP correctness: synth.rs, sampler.rs, effects.rs. Envelopes, voice stealing, denormal flush, filter/aliasing, detector accuracy.' },
  { key: 'engine-persistence', focus: 'export/, project.rs, recorder.rs: offline export correctness (pan/mono), save/reload fidelity, time signature, recorded MIDI CC, clip metadata.' },
  { key: 'vst3', focus: 'VST3 hosting: vst3_host.rs/.cpp, api/vst3.rs, ffi/vst3.rs. Per-buffer vs per-sample processing, edit-controller thread affinity, editor-attach races, set_state validation on untrusted blobs.' },
  { key: 'ffi-locks', focus: 'FFI boundary + lock safety: src/ffi/*, src/api/*. ffi_catch coverage, matching free fns, the non-reentrant parking_lot::Mutex deadlock hazard at get_track/get_master_track/remove_track call sites.' },
  { key: 'ui-screens', focus: 'Flutter UI: daw_screen.dart + mixins, piano_roll, timeline, mixer strips. Dead/diverged mixin layer vs wired private copies, gesture-math duplication, overlap handling.' },
  { key: 'commands-undo', focus: 'services/commands/*, Dart FFI bindings, undo/redo. Stale-id-on-redo across Remove commands, index handling, command-pattern coverage gaps for state-changing actions.' },
  { key: 'round-trip', focus: 'Persistence round-trip: project_persistence.dart, ui_layout.json vs engine project.json dual source of truth, MIDI- vs audio-clip metadata parity on save/reload.' },
  { key: 'testing', focus: 'Test coverage gaps: which high-risk layers (engine api/ffi, save/reload fidelity, recording golden, send_commands, painters) have zero or weak coverage.' },
  { key: 'repo-ci', focus: 'Repo/process/CI: .github/workflows, CLAUDE.md claims vs reality (e.g. clippy fatality), gitignore footguns, doc/reality mismatches.' },
]

// Current plan context (docs/BACKLOG.md "Now", docs/EDITING.md, the 2026-09-13 review).
const PLAN_CONTEXT =
  'Context: docs/BACKLOG.md "Now" holds the 15-row scorecard (8/10 = as good as the equivalent in an established DAW) and the v0.7 / v0.8 split; "Decisions: don\'t re-raise" lists settled items. ' +
  'docs/EDITING.md is the PLANNED editing model; the five-tool row (Draw, Select, Erase, Duplicate, Slice) is known and being replaced, so do not report its design as a defect (real bugs in shared code such as undo, overlap or snapping still count). ' +
  'The 2026-09-13 review (docs/reviews/2026_09_13_product_review.md, sections 2 and 3) already lists C1 to C17; if you confirm one, cite its ID rather than reporting it as new.'

const FINDINGS = {
  type: 'object',
  properties: {
    score: { type: 'string', description: 'score out of 10 (half points) for this subsystem, where 8 = as dependable as the equivalent in an established DAW, + one-line justification' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          location: { type: 'string', description: 'file:line' },
          description: { type: 'string' },
          repro: { type: 'string', description: 'cheap runtime repro if obvious, else empty' },
        },
        required: ['title', 'severity', 'location', 'description'],
      },
    },
  },
  required: ['score', 'findings'],
}

const VERDICT = {
  type: 'object',
  properties: {
    refuted: { type: 'boolean', description: 'true if you could refute it: wrong, already handled elsewhere, or unreachable in practice' },
    reason: { type: 'string' },
  },
  required: ['refuted', 'reason'],
}

const VERIFIERS = 3 // skeptics per candidate
const DROP_IF_REFUTED = 2 // drop a candidate when >= this many skeptics refute it

phase('Read')
const reads = (await parallel(SUBSYSTEMS.map((s) => () =>
  agent(
    `You are auditing the Boojy Audio codebase (Rust audio engine + Flutter UI) for LATENT correctness bugs the green test suite never exercises — fragility under non-default audio devices, real plugin load, untrusted project files, and the undo/redo paths a dogfooding musician hits constantly. Read this subsystem deeply:\n\n${s.focus}\n\nReport every candidate defect with a precise file:line, a severity, and a one-line description (plus a cheap runtime repro if obvious). Be concrete and skeptical — prefer real defects over style nits. Score the subsystem out of 10.\n\n${PLAN_CONTEXT}`,
    { label: `read:${s.key}`, phase: 'Read', model: 'sonnet', agentType: 'Explore', schema: FINDINGS }
  ).then((r) => ({ ...r, key: s.key }))
))).filter(Boolean)

const scores = reads.map((r) => ({ key: r.key, score: r.score }))
const candidates = reads.flatMap((r) => (r.findings || []).map((f) => ({ ...f, subsystem: r.key })))
candidates.forEach((c, i) => { c.id = 'C' + (i + 1) })
log(`${candidates.length} candidate defects from ${reads.length} subsystems → adversarial verification`)

phase('Verify')
const judged = (await parallel(candidates.map((c) => () =>
  parallel(Array.from({ length: VERIFIERS }, (_, i) => () =>
    agent(
      `Adversarially verify this candidate defect by trying to REFUTE it — show it is wrong, already handled elsewhere, or unreachable in practice. Read the cited code and its surrounding context before deciding. Set refuted=true ONLY if you genuinely find it is not a real bug. (Refutation lens ${i + 1} of ${VERIFIERS}.)\n\nCandidate: ${c.title}\nLocation: ${c.location}\nClaim: ${c.description}`,
      { label: `verify:${c.id}`, phase: 'Verify', model: 'haiku', agentType: 'Explore', schema: VERDICT }
    )
  )).then((votes) => {
    const v = votes.filter(Boolean)
    const refuted = v.filter((x) => x.refuted).length
    return { ...c, refutedVotes: refuted, confirmed: refuted < DROP_IF_REFUTED }
  })
))).filter(Boolean)

const confirmed = judged.filter((c) => c.confirmed)
const dropped = judged.filter((c) => !c.confirmed)
log(`${confirmed.length}/${candidates.length} survived adversarial verification (${dropped.length} refuted & dropped)`)

phase('Synthesize')
const report = await agent(
  `Write a State-of-the-App review for Boojy Audio in the style of docs/archive/reviews/2026_05_29_codebase_review.md. Inputs below are adversarially-verified (code-level confidence; no GUI repro was run).\n\nProduce markdown with: (1) executive summary + scores out of 10 (half points) for the docs/BACKLOG.md scorecard rows this audit can speak to (mainly 1 Stability & performance, 2 Recording, 3 Arranging & clip editing, 9 Projects & export, 14 Repo, tests & CI), built from the subsystem scores below; the evidence is code-level only, so say where a row needs a usage check before it can be trusted; (2) confirmed bugs grouped by severity, each with file:line and cheap repro; (3) a prioritized improvement backlog ranked by severity × impact ÷ effort (S/M/L/XL) — NO new features, only fixes/hardening/tests/refactors; (4) how the confirmed bugs and hardening work map to the v0.7 rows (1, 2, 3, 9) versus later, paired with the alternative's cost. State the refuted-and-dropped count so they aren't re-hunted.\n\n${PLAN_CONTEXT}\n\nSubsystem scores: ${JSON.stringify(scores)}\n\nConfirmed defects: ${JSON.stringify(confirmed.map((c) => ({ id: c.id, title: c.title, severity: c.severity, location: c.location, description: c.description, repro: c.repro, subsystem: c.subsystem })))}\n\nRefuted & dropped: ${dropped.length}.`,
  { label: 'synthesize', phase: 'Synthesize', model: 'opus' }
)

return { report, candidateCount: candidates.length, confirmedCount: confirmed.length, droppedCount: dropped.length, scores }
