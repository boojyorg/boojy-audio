# Boojy Audio — Product

What Boojy is and the principles that decide what goes in. Scheduling and platform commitments
live in [BACKLOG.md](BACKLOG.md); accepted behaviour lives in specs and engineering rules.

## Product promise

Boojy Audio is a free, open-source DAW for composing, recording, arranging, mixing and mastering
music. It combines programmed instruments and recorded performances in a calm, spacious
interface, with sensible defaults and minimal setup. It is designed for musicians, from their
first song to finished releases.

Free forever and open source (GPL v3). Cross-platform is a product goal; which platforms ship
when is a backlog decision, not a promise made here.

## Primary use

Making a complete song from idea to export:

- Play, draw or sequence musical ideas.
- Record vocals and instruments.
- Combine parts into an arrangement.
- Mix, master and export a finished song.

These overlap. Someone making beats also mixes and masters; a vocalist uses sequenced parts; a
band uses samples. Do not assume a user "doesn't care" about a stage of the workflow.

Tyr's own hip-hop and instrumental projects, typically 4–14 tracks, are the reference workflow.
That is a reference, not a track limit or a genre restriction. Beginner accessibility is a
second, equal lens: the vanilla experience should work well without extensive configuration.

## Principles

- **Listen first.** Controls should encourage listening and musical judgement. Visuals support
  editing, understanding and essential feedback without dominating the experience. Effects
  should offer useful, restrained starting points. This does not prohibit an EQ graph or a
  spectrum display; it is how to judge whether one helps.
- **Calm interface.** Spacious, quiet when healthy, progressive disclosure. Show what the
  current task needs; keep the rest one step away.
- **Fast capture.** An idea disappears in a minute. Sound should be a few actions from opening
  the app, and a phrase played before pressing record should not be lost.
- **Forgiveness.** Unlimited undo, non-destructive editing, punch-in. The app should feel safe
  to try things in.
- **Minimal setup.** Sensible defaults, few required choices, no routing to configure before
  recording. Precision and control stay available where they matter.

## Included tools and plugins

A small, good collection of stock instruments and effects. The goal is that a song can be
finished with nothing installed, and extended with VST3 plugins when wanted. Stock instruments
stay focused and approachable; their exact designs are engineering decisions recorded in
[ARCHITECTURE.md](ARCHITECTURE.md), and growing one is a deliberate decision, not drift.

## Scope boundaries

- **Complete the core workflows.** Include the capabilities that let someone finish real music:
  recording, editing, arranging, mixing, mastering, export. Simplicity describes the experience,
  not an assumption that the musician has simple ambitions.
- **Reduce setup, unnecessary choices and repeated steps** before adding features.
- **Defer niche capabilities unless there is a clear need.** Specialist extensions are
  considered individually, on evidence, in the backlog.
- **Linear arrangement** describes how a song is laid out on the timeline. It does not prohibit
  sequencing within a track (an arpeggiator, a drum step sequencer). It does rule out a
  pattern-first, clip-launch workflow as the primary model.
- **Excluded directions** are recorded in the backlog's decisions section; check there before
  re-proposing one.

## Decision filter

For any proposed feature, default or change, answer both:

1. Does this help someone make or finish music?
2. What complexity does it add, for the user and for the codebase, and is that paid for by (1)?

Specific behaviour proposals (default states, automatic actions, preset chains) go to the
backlog as candidates until accepted. A principle here is never on its own a requirement.
