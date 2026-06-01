export const meta = {
  name: 'feature-gap-review',
  description:
    'Feature-coverage audit: survey FEATURE_TRACKER/ROADMAP/plans for claimed-vs-actual gaps + beginner-DAW teardowns ("what does a beginner expect that Boojy lacks") → classify each gap (v1.0-blocking | nice-to-have | out-of-scope-for-beginners) → synthesized ranked feature-gap backlog + recommended next theme. Model-tiered (readers Sonnet, classifiers Haiku, synthesis Opus). Beginner-first lens throughout.',
  whenToUse:
    'Before opening a new MINOR version plan, alongside codebase-review (correctness) and ui-ux-review (UI), to answer "what features are MISSING". Lighter than the codebase audit. Beginner-first: a missing pro feature is usually correctly out-of-scope. Optionally pass args.priorThemes (themes the other two reviews proposed) so synthesis reconciles. Save the returned report to docs/reviews/.',
  phases: [
    { title: 'Survey', detail: 'internal tracker/roadmap readers + beginner-DAW teardowns (Sonnet)' },
    { title: 'Classify', detail: 'tag each gap blocking/nice/out-of-scope (Haiku)' },
    { title: 'Synthesize', detail: 'ranked feature-gap backlog + theme (Opus)' },
  ],
}

// Internal readers: what does Boojy CLAIM vs actually have? Verify a sample against code, don't trust docs.
const INTERNAL = [
  { key: 'feature-tracker', focus: 'docs/FEATURE_TRACKER.md — the v1.0 feature checklist. For each major checked ("done") item, spot-check it against the actual code (engine/src + ui/lib) to confirm it is really built, not just ticked. List items that are claimed-done but missing/partial, and unchecked items that look load-bearing for a usable beginner DAW.' },
  { key: 'roadmap-plans', focus: 'docs/ROADMAP.md + docs/plans/ + docs/archive/plans/ + dreams.md §1 — features that were planned, deferred, or only partially landed. Surface "started but not finished" work and explicitly-deferred items that a beginner would still expect (e.g. the deferred effects/device overhaul, Serum/VST3 load bug, light/high-contrast theme).' },
]

// Beginner-oriented DAWs only — GarageBand is the north-star comparison, the others are popular entry points.
// Deliberately NOT pro DAWs: parity with Ableton/Logic/Pro Tools is out of scope by design.
const DAWS = ['GarageBand', 'BandLab', 'Soundtrap', 'FL Studio (beginner workflow)']

const GAPS = {
  type: 'object',
  properties: {
    summary: { type: 'string', description: 'one-paragraph read of how complete this surface is for a beginner' },
    gaps: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          feature: { type: 'string' },
          status: { type: 'string', enum: ['claimed-done-but-missing', 'partial', 'unbuilt', 'deferred'] },
          evidence: { type: 'string', description: 'doc line and/or file:line confirming the gap' },
          whyItMatters: { type: 'string', description: 'what a beginner cannot do without it' },
        },
        required: ['feature', 'status', 'evidence', 'whyItMatters'],
      },
    },
  },
  required: ['summary', 'gaps'],
}

const EXPECT = {
  type: 'object',
  properties: {
    notes: { type: 'string', description: 'what this DAW does well for absolute beginners' },
    expectations: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          feature: { type: 'string', description: 'a beginner-essential capability this DAW offers' },
          whyBeginnersExpect: { type: 'string' },
          boojyStatus: { type: 'string', description: 'has it / lacks it / partial — based on reading the Boojy repo' },
        },
        required: ['feature', 'whyBeginnersExpect', 'boojyStatus'],
      },
    },
  },
  required: ['notes', 'expectations'],
}

const CLASSIFY = {
  type: 'object',
  properties: {
    category: { type: 'string', enum: ['v1.0-blocking', 'nice-to-have', 'out-of-scope-for-beginners'] },
    rationale: { type: 'string', description: 'one line tied to the beginner-first north star' },
    effort: { type: 'string', enum: ['S', 'M', 'L', 'XL'] },
  },
  required: ['category', 'rationale', 'effort'],
}

const priorThemes = (args && args.priorThemes) || ''

phase('Survey')
const internalReads = (await parallel(INTERNAL.map((s) => () =>
  agent(
    `You are auditing Boojy Audio (Rust audio engine + Flutter UI) for MISSING FEATURES — not bugs, not UI polish. Boojy targets BEGINNERS/hobbyists (GarageBand model), so judge completeness against "can a beginner make a song end-to-end", NOT pro-DAW parity. Survey this surface:\n\n${s.focus}\n\nReport each genuine gap with the feature name, a status (claimed-done-but-missing / partial / unbuilt / deferred), evidence (doc line and/or file:line), and why it matters to a beginner. Be skeptical of the docs — verify "done" claims against real code. Give a one-paragraph completeness read.`,
    { label: `survey:${s.key}`, phase: 'Survey', model: 'sonnet', agentType: 'Explore', schema: GAPS }
  ).then((r) => ({ ...r, key: s.key }))
))).filter(Boolean)

const competitiveReads = (await parallel(DAWS.map((d) => () =>
  agent(
    `Competitive feature teardown for a Boojy Audio feature-gap review. Boojy is a beginner-first DAW (GarageBand model). List the capabilities that ${d} gives ABSOLUTE BEGINNERS that make it feel complete (recording, loops/sounds library, simple instruments, basic effects, sharing/export, undo, automation, etc.). For each, say why a beginner expects it and — by reading the Boojy repo (engine/src + ui/lib + docs/FEATURE_TRACKER.md) — whether Boojy has it / lacks it / partial. Focus on beginner essentials, NOT pro features. Be specific.`,
    { label: `daw:${d}`, phase: 'Survey', model: 'sonnet', agentType: 'Explore', schema: EXPECT }
  ).then((r) => ({ ...r, daw: d }))
))).filter(Boolean)

// Unify both sources into one candidate-gap list for classification.
const candidates = [
  ...internalReads.flatMap((r) => (r.gaps || []).map((g) => ({
    feature: g.feature, source: `internal:${r.key}`, status: g.status, evidence: g.evidence, whyItMatters: g.whyItMatters,
  }))),
  ...competitiveReads.flatMap((r) => (r.expectations || [])
    .filter((e) => /lack|partial|no\b|missing/i.test(e.boojyStatus || ''))
    .map((e) => ({
      feature: e.feature, source: `daw:${r.daw}`, status: 'unbuilt', evidence: `${r.daw}: ${e.boojyStatus}`, whyItMatters: e.whyBeginnersExpect,
    }))),
]
candidates.forEach((c, i) => { c.id = 'G' + (i + 1) })
log(`${candidates.length} candidate gaps (${internalReads.length} internal surveys + ${competitiveReads.length} DAW teardowns) → classification`)

phase('Classify')
const classified = (await parallel(candidates.map((c) => () =>
  agent(
    `Classify this candidate MISSING FEATURE for Boojy Audio, a beginner-first DAW (GarageBand model). Decide: is it v1.0-blocking (a beginner genuinely can't make/finish a song without it), nice-to-have (real value but not a v1.0 gate), or out-of-scope-for-beginners (a pro feature that would correctly be skipped or deferred past 1.0)? Default to out-of-scope when it smells pro-only. Give a one-line rationale tied to the beginner-first north star and an effort estimate (S/M/L/XL).\n\nFeature: ${c.feature}\nSource: ${c.source}\nReported status: ${c.status}\nEvidence: ${c.evidence}\nWhy it reportedly matters: ${c.whyItMatters}`,
    { label: `classify:${c.id}`, phase: 'Classify', model: 'haiku', agentType: 'Explore', schema: CLASSIFY }
  ).then((v) => ({ ...c, ...v }))
))).filter(Boolean)

const blocking = classified.filter((c) => c.category === 'v1.0-blocking')
const nice = classified.filter((c) => c.category === 'nice-to-have')
const outOfScope = classified.filter((c) => c.category === 'out-of-scope-for-beginners')
log(`classified: ${blocking.length} v1.0-blocking, ${nice.length} nice-to-have, ${outOfScope.length} out-of-scope`)

phase('Synthesize')
const report = await agent(
  `Write a Feature-Gap Review for Boojy Audio, a beginner-first DAW (GarageBand model) heading toward v1.0. This review answers "what features are MISSING" — it complements a separate correctness audit and UI/UX review, so do NOT cover bugs or visual polish here.\n\nProduce markdown with: (1) executive summary — how close is Boojy to "a beginner can make a full song end-to-end?"; (2) the v1.0-BLOCKING gap list, each with why a beginner is stuck without it, evidence, and effort; (3) a nice-to-have backlog ranked by beginner-impact ÷ effort; (4) an explicit OUT-OF-SCOPE list (pro features we are deliberately NOT chasing) so they aren't re-raised; (5) how Boojy compares to GarageBand/BandLab/Soundtrap/FL Studio on beginner essentials; (6) a recommended next theme for the version after v0.4.0, paired with the alternative's cost.${priorThemes ? '\n\nThe other two reviews proposed these themes — reconcile your recommendation with them: ' + priorThemes : ''}\n\nInternal survey summaries: ${JSON.stringify(internalReads.map((r) => ({ key: r.key, summary: r.summary })))}\n\nDAW teardown notes: ${JSON.stringify(competitiveReads.map((r) => ({ daw: r.daw, notes: r.notes })))}\n\nv1.0-blocking gaps: ${JSON.stringify(blocking.map((c) => ({ feature: c.feature, source: c.source, evidence: c.evidence, whyItMatters: c.whyItMatters, rationale: c.rationale, effort: c.effort })))}\n\nNice-to-have: ${JSON.stringify(nice.map((c) => ({ feature: c.feature, evidence: c.evidence, rationale: c.rationale, effort: c.effort })))}\n\nOut-of-scope: ${JSON.stringify(outOfScope.map((c) => ({ feature: c.feature, rationale: c.rationale })))}`,
  { label: 'synthesize', phase: 'Synthesize', model: 'opus' }
)

return { report, candidateCount: candidates.length, blocking: blocking.length, niceToHave: nice.length, outOfScope: outOfScope.length }
