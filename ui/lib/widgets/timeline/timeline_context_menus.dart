// ignore_for_file: avoid_positional_boolean_parameters
import 'package:flutter/material.dart';
import '../../models/clip_data.dart';
import '../../models/midi_note_data.dart';
import '../../services/undo_redo_manager.dart';
import '../../services/commands/clip_commands.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../context_menus/clip_context_menu.dart';
import '../../utils/track_colors.dart';
import '../shared/boojy_dropdown.dart';
import 'timeline_state.dart';
import 'timeline_selection.dart';
import '../timeline_view.dart';

/// Mixin containing context menu and clip operation methods for TimelineView.
/// Separates menu/dialog UI and clip manipulation from main timeline code.
mixin TimelineContextMenusMixin
    on State<TimelineView>, TimelineViewStateMixin, TimelineSelectionMixin {
  // ========================================================================
  // CONTEXT MENUS
  // ========================================================================

  /// Show context menu for an audio clip
  void showAudioClipContextMenu(Offset position, ClipData clip) {
    showClipContextMenu(
      context: context,
      position: position,
      clipType: ClipType.audio,
      canJoin: selectedAudioClipIds.length >= 2,
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'delete':
          deleteAudioClip(clip);
          break;
        case 'duplicate':
          duplicateAudioClip(clip);
          break;
        case 'join':
          widget.audioClipCallbacks.onJoinSelected?.call();
          break;
        case 'split':
          // Future: Audio clip split from context menu (v0.3.0)
          break;
        case 'cut':
        case 'copy':
        case 'paste':
          // Future: Audio clip cut/copy/paste (v0.3.0)
          break;
        case 'mute':
          // Future: Audio clip mute toggle (v0.3.0)
          break;
        case 'color':
          // Future: Clip color picker (v0.6.0)
          break;
        case 'rename':
          // Future: Clip inline rename (v0.6.0)
          break;
      }
    });
  }

  /// Show context menu for a MIDI clip
  void showMidiClipContextMenu(Offset position, MidiClipData clip) {
    showClipContextMenu(
      context: context,
      position: position,
      clipType: ClipType.midi,
      canJoin: selectedMidiClipIds.length >= 2,
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'delete':
          widget.midiClipCallbacks.onDeleted?.call(clip.clipId, clip.trackId);
          break;
        case 'duplicate':
          duplicateMidiClip(clip);
          break;
        case 'split':
          splitMidiClipAtPlayhead(clip);
          break;
        case 'join':
          widget.midiClipCallbacks.onJoinSelected?.call();
          break;
        case 'cut':
          cutMidiClip(clip);
          break;
        case 'copy':
          copyMidiClip(clip);
          break;
        case 'paste':
          pasteMidiClip(clip.trackId);
          break;
        case 'mute':
          toggleMidiClipMute(clip);
          break;
        case 'loop':
          toggleMidiClipLoop(clip);
          break;
        case 'bounce':
          // Future: Bounce MIDI to audio (v0.3.0)
          break;
        case 'export_midi':
          widget.midiClipCallbacks.onExported?.call(clip);
          break;
        case 'color':
          showColorPicker(clip);
          break;
        case 'rename':
          showRenameDialog(clip);
          break;
      }
    });
  }

  /// Show context menu for the time ruler
  void showRulerContextMenu(Offset globalPosition, Offset localPosition) {
    // listen:false — reading context.colors in a handler asserts in debug.
    final colors = context.themeProvider.colors;

    // Calculate beat position from click (ruler is outside scroll → add offset)
    final scrollOffset = scrollController.hasClients
        ? scrollController.offset
        : 0.0;
    final xInContent = localPosition.dx + scrollOffset;
    final clickedBeat = xInContent / pixelsPerBeat;
    // Snap to bar boundary up-front so we can capture it in the .then closure.
    final snappedBeat = (clickedBeat / 4.0).floor() * 4.0;

    showBoojyMenu<String>(
      context: context,
      anchor: Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      items: [
        BoojyMenuItem(
          value: 'set_loop_start',
          icon: BI.skipBack,
          label: 'Set Loop Start Here',
        ),
        BoojyMenuItem(
          value: 'set_loop_end',
          icon: BI.skipForward,
          label: 'Set Loop End Here',
        ),
        const BoojyMenuDivider<String>(),
        BoojyMenuItem(
          value: 'set_loop_1_bar',
          icon: BI.selection,
          label: 'Set 1 Bar Loop Here',
        ),
        BoojyMenuItem(
          value: 'set_loop_4_bars',
          icon: BI.gridOn,
          label: 'Set 4 Bar Loop Here',
        ),
        const BoojyMenuDivider<String>(),
        BoojyMenuItem(
          value: 'add_marker',
          icon: BI.bookmark,
          label: 'Add Marker',
          enabled: false,
        ),
      ],
      selectedValue: null,
      colors: colors,
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'set_loop_start':
          widget.onLoopRegionChanged?.call(snappedBeat, widget.loopEndBeats);
        case 'set_loop_end':
          widget.onLoopRegionChanged?.call(
            widget.loopStartBeats,
            snappedBeat + 4.0,
          );
        case 'set_loop_1_bar':
          widget.onLoopRegionChanged?.call(snappedBeat, snappedBeat + 4.0);
        case 'set_loop_4_bars':
          widget.onLoopRegionChanged?.call(snappedBeat, snappedBeat + 16.0);
        case 'add_marker':
          break; // Future: Timeline markers
      }
    });
  }

  /// Show context menu for empty track area
  void showEmptyAreaContextMenu(
    Offset globalPosition,
    Offset localPosition,
    TimelineTrackData track,
    bool isMidiTrack,
  ) {
    // listen:false — reading context.colors in a handler asserts in debug.
    final colors = context.themeProvider.colors;

    final beatPosition = calculateBeatPosition(localPosition);
    final snappedBeat = snapToGrid(beatPosition);
    final canPaste = clipboardMidiClip != null;

    showBoojyMenu<String>(
      context: context,
      anchor: Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      items: [
        if (isMidiTrack)
          BoojyMenuItem(
            value: 'create_clip',
            icon: BI.add,
            label: 'Create MIDI Clip Here',
            shortcut: 'Double-click',
          ),
        BoojyMenuItem(
          value: 'paste',
          icon: BI.paste,
          label: 'Paste',
          shortcut: '⌘V',
          enabled: canPaste,
        ),
        const BoojyMenuDivider<String>(),
        BoojyMenuItem(
          value: 'select_all',
          icon: BI.selectAll,
          label: 'Select All Clips',
          shortcut: '⌘A',
        ),
      ],
      selectedValue: null,
      colors: colors,
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'create_clip':
          widget.dragDropCallbacks.onCreateClipOnTrack?.call(
            track.id,
            snappedBeat,
            4.0,
          );
        case 'paste':
          if (canPaste) pasteMidiClip(track.id);
        case 'select_all':
          selectAllClips();
      }
    });
  }

  /// Show track type selection popup after drag-to-create
  void showTrackTypePopup(
    BuildContext ctx,
    Offset globalPosition,
    double startBeats,
    double durationBeats,
  ) {
    // listen:false — reading context.colors in a handler asserts in debug.
    final colors = ctx.themeProvider.colors;

    showBoojyMenu<String>(
      context: ctx,
      anchor: Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      items: [
        BoojyMenuItem(value: 'midi', icon: BI.piano, label: 'MIDI Track'),
        BoojyMenuItem(value: 'audio', icon: BI.musicNote, label: 'Audio Track'),
      ],
      selectedValue: null,
      colors: colors,
    ).then((value) {
      if (value != null) {
        widget.dragDropCallbacks.onCreateTrackWithClip?.call(
          value,
          startBeats,
          durationBeats,
        );
      }
    });
  }

  // ========================================================================
  // CLIP OPERATIONS
  // ========================================================================

  /// Delete an audio clip
  Future<void> deleteAudioClip(ClipData clip) async {
    final command = DeleteAudioClipCommand(
      clipData: clip,
      onClipRemoved: (clipId) {
        if (mounted) {
          setState(() {
            clips.removeWhere((c) => c.clipId == clipId);
            if (selectedAudioClipId == clipId) {
              selectedAudioClipId = null;
            }
            selectedAudioClipIds.remove(clipId);
          });
        }
      },
      onClipRestored: (restoredClip) {
        if (mounted) {
          setState(() {
            clips.add(restoredClip);
          });
        }
      },
    );
    await UndoRedoManager().execute(command);
  }

  /// Duplicate an audio clip (place copy at specified position or after original)
  void duplicateAudioClip(ClipData clip, {double? atPosition}) {
    final newStartTime = atPosition ?? clip.startTime + clip.duration;
    widget.audioClipCallbacks.onCopied?.call(clip, newStartTime);
  }

  /// Duplicate a MIDI clip
  void duplicateMidiClip(MidiClipData clip) {
    final newStartTime = clip.startTime + clip.duration;
    widget.midiClipCallbacks.onCopied?.call(clip, newStartTime);
  }

  /// Quantize a MIDI clip
  void quantizeMidiClip(MidiClipData clip) {
    const gridSizeBeats = 1.0; // 1 beat
    final quantizedStart =
        (clip.startTime / gridSizeBeats).round() * gridSizeBeats;

    if ((quantizedStart - clip.startTime).abs() < 0.001) {
      return;
    }

    final quantizedClip = clip.copyWith(startTime: quantizedStart);
    widget.midiClipCallbacks.onUpdated?.call(quantizedClip);
  }

  /// Split MIDI clip at playhead position.
  ///
  /// Routed through the daw layer's undoable split (same path as the slice tool
  /// and Cmd+E), so it's undoable and never destroys the right region.
  void splitMidiClipAtPlayhead(MidiClipData clip) {
    // Convert playhead from seconds to beats
    final beatsPerSecond = widget.tempo / 60.0;
    final playheadBeats = widget.playheadNotifier.value * beatsPerSecond;

    // Check if playhead is within clip bounds
    if (playheadBeats <= clip.startTime || playheadBeats >= clip.endTime) {
      return;
    }

    // Split point in beats relative to clip start
    final splitPointBeats = playheadBeats - clip.startTime;

    // Route through the daw layer's undoable split (engine+manager primitives).
    widget.midiClipCallbacks.onSplit?.call(clip, splitPointBeats);
  }

  // ========================================================================
  // MIDI CLIP CLIPBOARD OPERATIONS
  // ========================================================================

  /// Copy a MIDI clip to clipboard
  void copyMidiClip(MidiClipData clip) {
    clipboardMidiClip = clip;
  }

  /// Cut a MIDI clip (copy to clipboard, then delete)
  void cutMidiClip(MidiClipData clip) {
    clipboardMidiClip = clip;
    widget.midiClipCallbacks.onDeleted?.call(clip.clipId, clip.trackId);
  }

  /// Paste a MIDI clip from clipboard to track
  void pasteMidiClip(int trackId) {
    if (clipboardMidiClip == null) {
      return;
    }

    // Paste at playhead position (convert from seconds to beats)
    final beatsPerSecond = widget.tempo / 60.0;
    final pastePosition = widget.playheadNotifier.value * beatsPerSecond;
    widget.midiClipCallbacks.onCopied?.call(clipboardMidiClip!, pastePosition);
  }

  // ========================================================================
  // MIDI CLIP PROPERTY TOGGLES
  // ========================================================================

  /// Toggle mute state of a MIDI clip
  void toggleMidiClipMute(MidiClipData clip) {
    final mutedClip = clip.copyWith(isMuted: !clip.isMuted);
    widget.midiClipCallbacks.onUpdated?.call(mutedClip);
  }

  /// Toggle loop state of a MIDI clip (controls if content can repeat when stretched)
  void toggleMidiClipLoop(MidiClipData clip) {
    final loopedClip = clip.copyWith(canRepeat: !clip.canRepeat);
    widget.midiClipCallbacks.onUpdated?.call(loopedClip);
  }

  // ========================================================================
  // MIDI CLIP DIALOGS
  // ========================================================================

  /// Show color picker for a MIDI clip
  void showColorPicker(MidiClipData clip) {
    // Use the curated track palette (soft row) instead of raw Material colours.
    final colors = TrackColors.manualPalette.take(8).toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clip Color'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((color) {
            return GestureDetector(
              onTap: () {
                final coloredClip = clip.copyWith(color: color);
                widget.midiClipCallbacks.onUpdated?.call(coloredClip);
                Navigator.of(context).pop();
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: clip.color == color
                        ? this.context.colors.textPrimary
                        : this.context.colors.dark,
                    width: 3,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Show rename dialog for a MIDI clip
  void showRenameDialog(MidiClipData clip) {
    final controller = TextEditingController(text: clip.name);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Clip'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Clip Name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            if (value.isNotEmpty) {
              final renamedClip = clip.copyWith(name: value);
              widget.midiClipCallbacks.onUpdated?.call(renamedClip);
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = controller.text;
              if (value.isNotEmpty) {
                final renamedClip = clip.copyWith(name: value);
                widget.midiClipCallbacks.onUpdated?.call(renamedClip);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}
