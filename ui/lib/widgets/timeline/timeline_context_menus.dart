import 'package:flutter/material.dart';
import '../../models/clip_data.dart';
import '../../models/midi_note_data.dart';
import '../../services/undo_redo_manager.dart';
import '../../services/commands/clip_commands.dart';
import '../../theme/theme_extension.dart';
import '../context_menus/clip_context_menu.dart';
import 'timeline_state.dart';
import 'timeline_selection.dart';
import '../timeline_view.dart';

/// Mixin containing context menu and clip operation methods for TimelineView.
/// Separates menu/dialog UI and clip manipulation from main timeline code.
mixin TimelineContextMenusMixin on State<TimelineView>, TimelineViewStateMixin, TimelineSelectionMixin {

  // ========================================================================
  // CONTEXT MENUS
  // ========================================================================

  /// Show context menu for an audio clip
  void showAudioClipContextMenu(Offset position, ClipData clip) {
    showClipContextMenu(
      context: context,
      position: position,
      clipType: ClipType.audio,
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'delete':
          deleteAudioClip(clip);
          break;
        case 'duplicate':
          duplicateAudioClip(clip);
          break;
        case 'split':
          // TODO: Implement split for audio clips
          break;
        case 'cut':
          // TODO: Implement cut for audio clips
          break;
        case 'copy':
          // TODO: Implement copy for audio clips
          break;
        case 'paste':
          // TODO: Implement paste for audio clips
          break;
        case 'mute':
          // TODO: Implement mute for audio clips
          break;
        case 'color':
          // TODO: Implement color picker for audio clips
          break;
        case 'rename':
          // TODO: Implement rename for audio clips
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
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'delete':
          widget.onMidiClipDeleted?.call(clip.clipId, clip.trackId);
          break;
        case 'duplicate':
          duplicateMidiClip(clip);
          break;
        case 'split':
          splitMidiClipAtPlayhead(clip);
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
          // TODO: Implement bounce to audio
          break;
        case 'export_midi':
          widget.onMidiClipExported?.call(clip);
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
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    // Calculate beat position from click
    final scrollOffset = scrollController.hasClients ? scrollController.offset : 0.0;
    final xInContent = localPosition.dx + scrollOffset;
    final clickedBeat = xInContent / pixelsPerBeat;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'set_loop_start',
          child: Row(
            children: [
              Icon(Icons.first_page, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              const Text('Set Loop Start Here'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'set_loop_end',
          child: Row(
            children: [
              Icon(Icons.last_page, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              const Text('Set Loop End Here'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'set_loop_1_bar',
          child: Row(
            children: [
              Icon(Icons.crop_square, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              const Text('Set 1 Bar Loop Here'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'set_loop_4_bars',
          child: Row(
            children: [
              Icon(Icons.view_module, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              const Text('Set 4 Bar Loop Here'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'add_marker',
          enabled: false, // Placeholder for future feature
          child: Row(
            children: [
              Icon(Icons.bookmark_add, size: 18, color: context.colors.textMuted),
              const SizedBox(width: 8),
              Text('Add Marker', style: TextStyle(color: context.colors.textMuted)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;

      // Snap to bar boundary
      final snappedBeat = (clickedBeat / 4.0).floor() * 4.0;

      switch (value) {
        case 'set_loop_start':
          widget.onLoopRegionChanged?.call(snappedBeat, widget.loopEndBeats);
          break;
        case 'set_loop_end':
          widget.onLoopRegionChanged?.call(widget.loopStartBeats, snappedBeat + 4.0);
          break;
        case 'set_loop_1_bar':
          widget.onLoopRegionChanged?.call(snappedBeat, snappedBeat + 4.0);
          break;
        case 'set_loop_4_bars':
          widget.onLoopRegionChanged?.call(snappedBeat, snappedBeat + 16.0);
          break;
        case 'add_marker':
          // TODO: Implement markers in future version
          break;
      }
    });
  }

  /// Show context menu for empty track area
  void showEmptyAreaContextMenu(Offset globalPosition, Offset localPosition, TimelineTrackData track, bool isMidiTrack) {
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    // Calculate beat position from click
    final beatPosition = calculateBeatPosition(localPosition);
    final snappedBeat = snapToGrid(beatPosition);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        if (isMidiTrack)
          PopupMenuItem<String>(
            value: 'create_clip',
            child: Row(
              children: [
                Icon(Icons.add_box, size: 18, color: context.colors.textSecondary),
                const SizedBox(width: 8),
                const Text('Create MIDI Clip Here'),
                const Spacer(),
                Text('Double-click', style: TextStyle(fontSize: 12, color: context.colors.textMuted)),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'paste',
          enabled: clipboardMidiClip != null,
          child: Row(
            children: [
              Icon(Icons.paste, size: 18, color: clipboardMidiClip != null ? context.colors.textSecondary : context.colors.textMuted),
              const SizedBox(width: 8),
              Text('Paste', style: TextStyle(color: clipboardMidiClip != null ? null : context.colors.textMuted)),
              const Spacer(),
              Text('⌘V', style: TextStyle(fontSize: 12, color: context.colors.textMuted)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'select_all',
          child: Row(
            children: [
              Icon(Icons.select_all, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              const Text('Select All Clips'),
              const Spacer(),
              Text('⌘A', style: TextStyle(fontSize: 12, color: context.colors.textMuted)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;

      switch (value) {
        case 'create_clip':
          // Create a 1-bar MIDI clip at the clicked position
          widget.onCreateClipOnTrack?.call(track.id, snappedBeat, 4.0);
          break;
        case 'paste':
          if (clipboardMidiClip != null) {
            pasteMidiClip(track.id);
          }
          break;
        case 'select_all':
          selectAllClips();
          break;
      }
    });
  }

  /// Show track type selection popup after drag-to-create
  void showTrackTypePopup(BuildContext ctx, Offset globalPosition, double startBeats, double durationBeats) {
    final RenderBox overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: ctx,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'midi',
          child: Row(
            children: [
              Icon(Icons.piano, size: 18, color: this.context.colors.textSecondary),
              const SizedBox(width: 8),
              const Text('MIDI Track'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'audio',
          child: Row(
            children: [
              Icon(Icons.audiotrack, size: 18, color: this.context.colors.textSecondary),
              const SizedBox(width: 8),
              const Text('Audio Track'),
            ],
          ),
        ),
      ],
      color: this.context.colors.elevated,
    ).then((value) {
      if (value != null) {
        widget.onCreateTrackWithClip?.call(value, startBeats, durationBeats);
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
    widget.onAudioClipCopied?.call(clip, newStartTime);
  }

  /// Duplicate a MIDI clip
  void duplicateMidiClip(MidiClipData clip) {
    final newStartTime = clip.startTime + clip.duration;
    widget.onMidiClipCopied?.call(clip, newStartTime);
  }

  /// Quantize a MIDI clip
  void quantizeMidiClip(MidiClipData clip) {
    const gridSizeBeats = 1.0; // 1 beat
    final quantizedStart = (clip.startTime / gridSizeBeats).round() * gridSizeBeats;

    if ((quantizedStart - clip.startTime).abs() < 0.001) {
      return;
    }

    final quantizedClip = clip.copyWith(startTime: quantizedStart);
    widget.onMidiClipUpdated?.call(quantizedClip);
  }

  /// Split MIDI clip at playhead position
  void splitMidiClipAtPlayhead(MidiClipData clip) {
    // Convert playhead from seconds to beats
    final beatsPerSecond = widget.tempo / 60.0;
    final playheadBeats = widget.playheadPosition * beatsPerSecond;

    // Check if playhead is within clip bounds
    if (playheadBeats <= clip.startTime || playheadBeats >= clip.endTime) {
      return;
    }

    // Split point in beats relative to clip start
    final splitPointBeats = playheadBeats - clip.startTime;

    // Split notes into two groups
    final leftNotes = <MidiNoteData>[];
    final rightNotes = <MidiNoteData>[];

    for (final note in clip.notes) {
      if (note.endTime <= splitPointBeats) {
        leftNotes.add(note);
      } else if (note.startTime >= splitPointBeats) {
        rightNotes.add(note.copyWith(
          startTime: note.startTime - splitPointBeats,
          id: '${note.note}_${note.startTime - splitPointBeats}_${DateTime.now().microsecondsSinceEpoch}',
        ));
      } else {
        // Note straddles split - truncate to left
        leftNotes.add(note.copyWith(
          duration: splitPointBeats - note.startTime,
        ));
      }
    }

    // Create left and right clips
    final leftClipId = DateTime.now().millisecondsSinceEpoch;
    final rightClipId = leftClipId + 1;

    final leftClip = clip.copyWith(
      clipId: leftClipId,
      duration: splitPointBeats,
      loopLength: splitPointBeats.clamp(0.25, clip.loopLength),
      notes: leftNotes,
      name: '${clip.name} (L)',
    );

    final rightClip = clip.copyWith(
      clipId: rightClipId,
      startTime: clip.startTime + splitPointBeats,
      duration: clip.duration - splitPointBeats,
      loopLength: (clip.duration - splitPointBeats).clamp(0.25, clip.loopLength),
      notes: rightNotes,
      name: '${clip.name} (R)',
    );

    // Delete original and add both new clips via callbacks
    widget.onMidiClipDeleted?.call(clip.clipId, clip.trackId);

    // Add both new clips
    widget.onMidiClipCopied?.call(leftClip, leftClip.startTime);
    widget.onMidiClipCopied?.call(rightClip, rightClip.startTime);
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
    widget.onMidiClipDeleted?.call(clip.clipId, clip.trackId);
  }

  /// Paste a MIDI clip from clipboard to track
  void pasteMidiClip(int trackId) {
    if (clipboardMidiClip == null) {
      return;
    }

    // Paste at playhead position (convert from seconds to beats)
    final beatsPerSecond = widget.tempo / 60.0;
    final pastePosition = widget.playheadPosition * beatsPerSecond;
    widget.onMidiClipCopied?.call(clipboardMidiClip!, pastePosition);
  }

  // ========================================================================
  // MIDI CLIP PROPERTY TOGGLES
  // ========================================================================

  /// Toggle mute state of a MIDI clip
  void toggleMidiClipMute(MidiClipData clip) {
    final mutedClip = clip.copyWith(isMuted: !clip.isMuted);
    widget.onMidiClipUpdated?.call(mutedClip);
  }

  /// Toggle loop state of a MIDI clip (controls if content can repeat when stretched)
  void toggleMidiClipLoop(MidiClipData clip) {
    final loopedClip = clip.copyWith(canRepeat: !clip.canRepeat);
    widget.onMidiClipUpdated?.call(loopedClip);
  }

  // ========================================================================
  // MIDI CLIP DIALOGS
  // ========================================================================

  /// Show color picker for a MIDI clip
  void showColorPicker(MidiClipData clip) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.pink,
      Colors.amber,
    ];

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
                widget.onMidiClipUpdated?.call(coloredClip);
                Navigator.of(context).pop();
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: clip.color == color ? this.context.colors.textPrimary : this.context.colors.dark,
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
              widget.onMidiClipUpdated?.call(renamedClip);
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
                widget.onMidiClipUpdated?.call(renamedClip);
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
