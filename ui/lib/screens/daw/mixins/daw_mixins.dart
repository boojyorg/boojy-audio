// Barrel export for DAW screen mixins
// Import this file to get all DAW screen mixins
//
// Mixin dependency order (each depends on previous):
// 1. DAWScreenStateMixin - foundation with all state variables
// 2. DAWPlaybackMixin - play, pause, stop, loop
// 3. DAWRecordingMixin - record, metronome, count-in, tempo
// 4. DAWUIMixin - panel toggles, keyboard shortcuts
// 5. DAWTrackMixin - track CRUD, selection, instruments
// 6. DAWClipMixin - MIDI/audio clip operations
// 7. DAWVst3Mixin - VST3 plugin management
// 8. DAWLibraryMixin - library item handlers, sampler
// 9. DAWProjectMixin - project file operations
// 10. DAWBuildMixin - widget builder helpers

export 'daw_screen_state.dart';
export 'daw_playback_mixin.dart';
export 'daw_recording_mixin.dart';
export 'daw_ui_mixin.dart';
export 'daw_track_mixin.dart';
export 'daw_clip_mixin.dart';
export 'daw_vst3_mixin.dart';
export 'daw_library_mixin.dart';
export 'daw_project_mixin.dart';
export 'daw_build_mixin.dart';
