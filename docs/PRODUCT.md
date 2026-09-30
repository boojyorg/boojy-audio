# Boojy Audio Product

What Boojy is for and the principles that decide what goes in. Scheduling lives in
[BACKLOG.md](BACKLOG.md).

## Promise

A free, open-source (GPL v3) DAW for making a complete song, from idea to export: play, draw or
sequence ideas, record vocals and instruments, arrange, mix, master and export. Programmed
instruments and recorded performances together, in a calm interface with sensible defaults and
minimal setup, for musicians from their first song to finished releases. Cross-platform is a
goal; what ships when is in [PLATFORMS.md](PLATFORMS.md).

The stages overlap: someone making beats also mixes; a vocalist uses sequenced parts. Don't
assume a user "doesn't care" about a stage. Tyr's own hip-hop and instrumental projects (4–14
tracks) are the reference workflow, not a limit; beginner accessibility is an equal lens.

## Principles

- **Listen first.** Controls encourage listening and musical judgement; visuals support editing
  and feedback without dominating. (An EQ graph isn't banned; this is how to judge whether it
  helps.)
- **Calm interface.** Spacious, quiet when healthy, progressive disclosure.
- **Fast capture.** Sound a few actions from opening the app; a phrase played before pressing
  record isn't lost.
- **Forgiveness.** Unlimited undo, non-destructive editing, capture after the fact.
- **Minimal setup.** Sensible defaults, few required choices, no routing before recording;
  precision stays available where it matters.

## Scope

- **Complete the core workflows** (record, edit, arrange, mix, master, export). Simple
  experience, not simple ambitions.
- **Reduce setup, choices and repeated steps** before adding features. Defer niche capabilities
  without a clear need.
- **A small, good set of stock instruments and effects**, so a song can be finished with nothing
  installed; VST3 for more. Growing a stock instrument is a deliberate decision.
- **Linear arrangement** is the primary model; sequencing within a track (arpeggiator, step
  sequencer) is fine, a pattern-first clip-launch workflow is not.
- Excluded directions are in BACKLOG's Decisions; check there before re-proposing one.

## Decision filter

For any feature, default or change:

1. Does this help someone make or finish music?
2. What complexity does it add, for the user and the codebase, and is that paid for by (1)?

A principle here is never on its own a requirement; specific behaviour proposals go to BACKLOG.
