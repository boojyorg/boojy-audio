export const meta = {
  name: 'ui-ux-review',
  description:
    'UI/UX review: parallel readers over the Flutter UI by area + 4 competitive DAW teardowns → synthesized verdict, bug ledger, design direction, ASCII mockups, and a milestone proposal. Optional screenshot grounding. Model-tiered (readers + teardowns Sonnet, synthesis Opus). Mirrors docs/reviews/ui_ux_review_2026_05_30.md.',
  whenToUse:
    "Before opening a new MINOR version's plan doc, to set the visual/UX theme. Lighter than the codebase audit. Pass current screenshots via args.screenshots (absolute paths) for visual grounding — without them the visual read is incomplete. Save the returned report to docs/reviews/.",
  phases: [
    { title: 'Read', detail: 'one read-only reader per UI area (Sonnet)' },
    { title: 'Compare', detail: '4 competitive DAW teardowns (Sonnet)' },
    { title: 'Synthesize', detail: 'verdict + ledger + direction + mockups + milestone (Opus)' },
  ],
}

const AREAS = [
  { key: 'theme-tokens', focus: 'Theme & tokens: lib/theme/* (app_colors, tokens). Colour-temperature consistency, hardcoded Color(0x..) leakage outside the palette, typeface/font setup, the BT.scaled() scaling story.' },
  { key: 'top-bar', focus: 'Top bar (transport_bar.dart): button shape-language consistency, radius/font/hover rhythm, narrow-width responsiveness/overflow.' },
  { key: 'transport-time', focus: 'Transport & time readout: position_display, tempo/sig, bars/time/both cycling, pinned ruler readout.' },
  { key: 'piano-roll', focus: 'Piano roll: lane contrast (white vs black keys), root-note highlight, note colour/legibility, grid tiers, zoom, select/draw affordances.' },
  { key: 'timeline', focus: 'Timeline/arrangement: clip rendering, ghost headers, empty-state prompt, grid painter, playhead colour.' },
  { key: 'mixer', focus: 'Mixer + track strips: fader orientation, meters (peak-hold/unity), M/S/R hover, sends, dB readouts, track identity/colour, add-track entry points.' },
  { key: 'effects-devices', focus: 'Effects/device chain: device-shell consistency, slider/knob legibility & hit targets, a universal MIX knob, meters, EQ presentation.' },
  { key: 'chrome-settings', focus: 'Window chrome + settings: macOS title strip, the multiple settings dialogs and their consistency, dropdown/header chrome, start screen.' },
]

const DAWS = ['GarageBand', 'Ableton Live', 'FL Studio', 'Logic Pro']

const UI_FINDINGS = {
  type: 'object',
  properties: {
    observations: { type: 'string', description: "qualitative read of this area: what feels off and why (beginner-first lens)" },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          title: { type: 'string' },
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          effort: { type: 'string', enum: ['S', 'M', 'L', 'XL'] },
          location: { type: 'string', description: 'file:line or widget' },
          rootCause: { type: 'string' },
          fix: { type: 'string' },
        },
        required: ['title', 'severity', 'effort', 'location', 'fix'],
      },
    },
  },
  required: ['observations', 'findings'],
}

const TEARDOWN = {
  type: 'object',
  properties: {
    steal: { type: 'array', items: { type: 'string' } },
    avoid: { type: 'array', items: { type: 'string' } },
    notes: { type: 'string' },
  },
  required: ['steal', 'avoid'],
}

const screenshots = (args && args.screenshots) || []

phase('Read')
const reads = (await parallel(AREAS.map((a) => () =>
  agent(
    `Review the Boojy Audio Flutter UI for this area:\n\n${a.focus}\n\nBoojy targets BEGINNERS/hobbyists (GarageBand model), not pros — judge it beginner-first ("calm precise instrument", premium-but-simple, silence-when-healthy). Report concrete UI/UX bugs and inconsistencies, each with a file:line or widget, severity, effort (S/M/L/XL), root cause, and a fix. Add a short qualitative read of what feels off and why.${screenshots.length ? ' Screenshots of the running app are at: ' + screenshots.join(', ') + ' — Read them to ground your visual judgements against the real pixels.' : ''}`,
    { label: `read:${a.key}`, phase: 'Read', model: 'sonnet', agentType: 'Explore', schema: UI_FINDINGS }
  ).then((r) => ({ ...r, key: a.key }))
))).filter(Boolean)

const findings = reads.flatMap((r) => (r.findings || []).map((f) => ({ ...f, area: r.key })))
const observations = reads.map((r) => ({ area: r.key, observations: r.observations }))
log(`${findings.length} UI findings across ${reads.length} areas`)

phase('Compare')
const teardowns = (await parallel(DAWS.map((d) => () =>
  agent(
    `Competitive teardown for a Boojy Audio UI/UX review. How does ${d} handle the top bar / time readout, piano roll, mixer, effects/device UI, and overall visual language? Give concrete "steal" (worth adopting for a beginner-first DAW) and "avoid" (what makes ${d} feel busy, dated, or pro-only) lists. Be specific and opinionated.`,
    { label: `daw:${d}`, phase: 'Compare', model: 'sonnet', schema: TEARDOWN }
  ).then((t) => ({ ...t, daw: d }))
))).filter(Boolean)

phase('Synthesize')
const report = await agent(
  `Write a UI/UX Review & Design Direction for Boojy Audio in the style of docs/reviews/ui_ux_review_2026_05_30.md. Boojy is beginner-first (GarageBand model), premium-but-simple, "a calm precise instrument".\n\nProduce markdown with: (1) a one-paragraph verdict + letter grade; (2) the core diagnosis — the few root causes under most symptoms; (3) a full bug & inconsistency ledger (dedup the findings below; flag quick wins ≤S effort); (4) how Boojy compares to the 4 DAWs (steal/avoid per area); (5) a design direction; (6) a few ASCII before→after mockups for the highest-leverage screens; (7) a proposed next milestone with in/out scope, each design decision paired with the alternative's cost.\n\nUI findings: ${JSON.stringify(findings)}\n\nArea observations: ${JSON.stringify(observations)}\n\nDAW teardowns: ${JSON.stringify(teardowns)}\n\n${screenshots.length ? 'Screenshots were grounded at: ' + screenshots.join(', ') + '.' : 'No screenshots were provided — note in the report that visual grounding is incomplete and recommend verifying on `fvm flutter run -d macos`.'}`,
  { label: 'synthesize', phase: 'Synthesize', model: 'opus' }
)

return { report, findingCount: findings.length, areas: reads.length, daws: teardowns.length }
