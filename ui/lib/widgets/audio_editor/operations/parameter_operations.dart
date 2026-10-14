import 'package:flutter/material.dart';
import '../../../models/clip_group_edit.dart';
import '../audio_editor.dart';
import '../audio_editor_state.dart';

/// Mixin for audio clip parameter operations; the DAW makes each an undo
/// step.
mixin ParameterOperationsMixin on State<AudioEditor>, AudioEditorStateMixin {
  // ============================================
  // EDITS AND UNDO
  // ============================================

  /// True while a control is being dragged: each step updates the editor and
  /// timeline, and the engine and undo history get the result once, on
  /// release (BPM and pitch changes re-render the clip's audio).
  bool liveDragging = false;

  void beginLiveDrag() => liveDragging = true;

  void endLiveDrag(String actionDescription) {
    if (!liveDragging) return;
    liveDragging = false;
    widget.onEditFinished?.call(actionDescription);
  }

  /// Finish one edit: tell the timeline, then (unless mid-drag) the DAW,
  /// which sends the edit to the engine and records it as an undo step.
  void finishEdit(String actionDescription) {
    notifyClipUpdated();
    if (liveDragging) return;
    widget.onEditFinished?.call(actionDescription);
  }

  // ============================================
  // NOTIFICATION
  // ============================================

  /// Notify parent that clip was updated.
  void notifyClipUpdated() {
    if (currentClip == null) return;

    final updatedClip = currentClip!.copyWith(
      editData: editData,
      canRepeat: editData.loopEnabled,
      loopLength: editData.loopLengthSeconds(widget.projectTempo),
    );
    widget.onClipUpdated?.call(updatedClip);
  }

  // ============================================
  // TRANSPOSE OPERATIONS
  // ============================================

  /// Set transpose amount in semitones (-48 to +48).
  void setTranspose(int semitones) {
    setState(() {
      editData = editData.copyWith(
        transposeSemitones: semitones.clamp(-48, 48),
      );
    });
    finishEdit('Set transpose to $semitones semitones');
  }

  /// Set fine pitch adjustment in cents (-50 to +50).
  void setFineCents(int cents) {
    setState(() {
      editData = editData.copyWith(fineCents: cents.clamp(-50, 50));
    });
    finishEdit('Set fine tune to $cents cents');
  }

  // ============================================
  // GAIN OPERATIONS
  // ============================================

  /// Set gain in decibels.
  void setGain(double db) {
    setState(() {
      editData = editData.copyWith(gainDb: db.clamp(-70.0, 24.0));
    });
    finishEdit('Set gain to ${db.toStringAsFixed(1)} dB');
  }

  // ============================================
  // PROCESSING OPERATIONS
  // ============================================

  /// Toggle reverse playback. With several clips selected: reverse them all,
  /// or, when they all are already, none.
  void toggleReverse() {
    final group = widget.group;
    if (group != null) {
      final reversed = !group.allReversed;
      editGroup(
        SetReversed(reversed: reversed),
        '${reversed ? 'Reverse' : 'Un-reverse'} ${group.count} clips',
      );
      return;
    }
    final newValue = !editData.reversed;
    setState(() {
      editData = editData.copyWith(reversed: newValue);
    });
    finishEdit(newValue ? 'Enable reverse' : 'Disable reverse');
  }

  // ============================================
  // SEVERAL CLIPS (widget.group)
  // ============================================

  /// Make [edit] on the open clip and the other selected clips, as one undo
  /// step (one per drag).
  void editGroup(ClipGroupEdit edit, String actionDescription) {
    setState(() => editData = edit.applyTo(editData));
    widget.onGroupEdit?.call(edit);
    finishEdit(actionDescription);
  }

  /// A pitch drag or scroll: every clip moves by [cents], the group stopping
  /// together at the limits.
  void shiftGroupPitch(int cents, {required bool wholeSemitones}) {
    final group = widget.group;
    if (group == null) return;
    final shift = group.clampPitchShift(cents, wholeSemitones: wholeSemitones);
    if (shift == 0) return;
    editGroup(ShiftPitch(shift), 'Change pitch of ${group.count} clips');
  }

  /// Typed semitones: every clip gets them.
  void setGroupSemitones(int semitones) {
    final count = widget.group?.count ?? 1;
    editGroup(
      SetSemitones(semitones),
      'Set pitch of $count clips to $semitones semitones',
    );
  }

  /// Typed cents: every clip gets them.
  void setGroupCents(int cents) {
    final count = widget.group?.count ?? 1;
    editGroup(SetCents(cents), 'Set fine tune of $count clips to $cents cents');
  }

  /// The volume drag started on a silent clip: it moves alone, as there's no
  /// sensible amount to move the others by.
  bool _gainDragFromSilence = false;

  void beginGainDrag() {
    _gainDragFromSilence = editData.gainDb <= minGainDb;
    beginLiveDrag();
  }

  /// The volume slider moved the open clip to [db]: the others move by as
  /// much, the group stopping together at the limits.
  void setGroupGain(double db) {
    final group = widget.group;
    if (group == null || _gainDragFromSilence) {
      setGain(db);
      return;
    }
    final shift = group.clampGainShift(db - editData.gainDb);
    if (shift == 0) return;
    setState(() {
      editData = editData.copyWith(
        gainDb: (editData.gainDb + shift).clamp(minGainDb, maxGainDb),
      );
    });
    widget.onGroupEdit?.call(ShiftGain(shift));
    finishEdit('Change volume of ${group.count} clips');
  }

  /// Double-click on the volume slider: back to 0 dB, every selected clip.
  void resetGain() {
    final group = widget.group;
    if (group == null) {
      setGain(0.0);
      return;
    }
    editGroup(const SetGain(0.0), 'Reset volume of ${group.count} clips');
  }
}
