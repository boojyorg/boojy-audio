import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Centralized icon definitions for Boojy Audio.
///
/// Toggle [usePhosphor] to A/B test Phosphor vs Material icons at runtime.
/// Set to `false` to revert to Material Icons for visual comparison.
///
/// Usage:
///   Icon(BI.play, size: BT.iconMd)
///   Icon(BI.musicNote, size: BT.iconLg)
///
/// `BI` is a short alias for `BoojyIcons` — use it everywhere.
typedef BI = BoojyIcons;

class BoojyIcons {
  BoojyIcons._();

  /// Toggle between Phosphor Icons (true) and Material Icons (false).
  /// Change this and hot-reload to A/B test icon sets.
  static bool usePhosphor = false;

  // ============================================
  // TRANSPORT
  // ============================================
  static IconData get play =>
      usePhosphor ? PhosphorIconsRegular.play : Icons.play_arrow;
  static IconData get pause =>
      usePhosphor ? PhosphorIconsRegular.pause : Icons.pause;
  static IconData get stop =>
      usePhosphor ? PhosphorIconsRegular.stop : Icons.stop;
  static IconData get record =>
      usePhosphor ? PhosphorIconsRegular.record : Icons.circle;
  static IconData get loop =>
      usePhosphor ? PhosphorIconsRegular.repeat : Icons.loop;
  static IconData get skipBack =>
      usePhosphor ? PhosphorIconsRegular.caretLineLeft : Icons.first_page;
  static IconData get skipForward =>
      usePhosphor ? PhosphorIconsRegular.caretLineRight : Icons.last_page;
  static IconData get metronome =>
      usePhosphor ? PhosphorIconsRegular.timer : Icons.av_timer;

  // ============================================
  // MUSIC & AUDIO
  // ============================================
  static IconData get musicNote =>
      usePhosphor ? PhosphorIconsRegular.musicNote : Icons.music_note;
  static IconData get musicNotes =>
      usePhosphor ? PhosphorIconsRegular.musicNotes : Icons.queue_music;
  static IconData get piano =>
      usePhosphor ? PhosphorIconsRegular.pianoKeys : Icons.piano;
  static IconData get waveform =>
      usePhosphor ? PhosphorIconsRegular.waveform : Icons.waves;
  static IconData get audioFile =>
      usePhosphor ? PhosphorIconsRegular.fileAudio : Icons.audio_file;
  static IconData get equalizer =>
      usePhosphor ? PhosphorIconsRegular.equalizer : Icons.graphic_eq;
  static IconData get speakerHigh =>
      usePhosphor ? PhosphorIconsRegular.speakerHigh : Icons.volume_up;
  static IconData get speakerNone =>
      usePhosphor ? PhosphorIconsRegular.speakerNone : Icons.volume_off;
  static IconData get speakerSlash =>
      usePhosphor ? PhosphorIconsRegular.speakerSlash : Icons.volume_off;
  static IconData get waveSine =>
      usePhosphor ? PhosphorIconsRegular.waveSine : Icons.blur_on;
  static IconData get waveSawtooth =>
      usePhosphor ? PhosphorIconsRegular.waveSawtooth : Icons.blur_on;
  static IconData get waveSquare =>
      usePhosphor ? PhosphorIconsRegular.waveSquare : Icons.blur_on;
  static IconData get waveTriangle =>
      usePhosphor ? PhosphorIconsRegular.waveTriangle : Icons.blur_on;
  static IconData get queue =>
      usePhosphor ? PhosphorIconsRegular.queue : Icons.queue_music;

  // ============================================
  // NAVIGATION & ACTIONS
  // ============================================
  static IconData get close =>
      usePhosphor ? PhosphorIconsRegular.x : Icons.close;
  static IconData get add =>
      usePhosphor ? PhosphorIconsRegular.plus : Icons.add;
  static IconData get addCircle =>
      usePhosphor ? PhosphorIconsRegular.plusCircle : Icons.add_circle_outline;
  static IconData get delete =>
      usePhosphor ? PhosphorIconsRegular.trash : Icons.delete;
  static IconData get search =>
      usePhosphor ? PhosphorIconsRegular.magnifyingGlass : Icons.search;
  static IconData get settings =>
      usePhosphor ? PhosphorIconsRegular.gear : Icons.settings;
  static IconData get check =>
      usePhosphor ? PhosphorIconsRegular.check : Icons.check;
  static IconData get checkCircle =>
      usePhosphor ? PhosphorIconsRegular.checkCircle : Icons.check_circle;
  static IconData get refresh =>
      usePhosphor ? PhosphorIconsRegular.arrowClockwise : Icons.refresh;
  // ignore: non_constant_identifier_names
  static IconData get sync =>
      usePhosphor ? PhosphorIconsRegular.arrowsClockwise : Icons.sync;
  static IconData get help =>
      usePhosphor ? PhosphorIconsRegular.question : Icons.help_outline;
  static IconData get info =>
      usePhosphor ? PhosphorIconsRegular.info : Icons.info_outline;
  static IconData get warning =>
      usePhosphor ? PhosphorIconsRegular.warning : Icons.warning_amber_rounded;
  static IconData get error =>
      usePhosphor ? PhosphorIconsRegular.warningCircle : Icons.error_outline;
  static IconData get hourglass =>
      usePhosphor ? PhosphorIconsRegular.hourglass : Icons.hourglass_empty;

  // ============================================
  // ARROWS & CARETS
  // ============================================
  static IconData get caretDown =>
      usePhosphor ? PhosphorIconsRegular.caretDown : Icons.arrow_drop_down;
  static IconData get caretUp =>
      usePhosphor ? PhosphorIconsRegular.caretUp : Icons.keyboard_arrow_up;
  static IconData get caretLeft =>
      usePhosphor ? PhosphorIconsRegular.caretLeft : Icons.chevron_left;
  static IconData get caretRight =>
      usePhosphor ? PhosphorIconsRegular.caretRight : Icons.chevron_right;
  static IconData get arrowUp =>
      usePhosphor ? PhosphorIconsRegular.arrowUp : Icons.arrow_upward;
  static IconData get arrowDown =>
      usePhosphor ? PhosphorIconsRegular.arrowDown : Icons.arrow_downward;
  static IconData get arrowLeft =>
      usePhosphor ? PhosphorIconsRegular.arrowLeft : Icons.arrow_back;
  static IconData get arrowRight =>
      usePhosphor ? PhosphorIconsRegular.arrowRight : Icons.arrow_forward;
  static IconData get arrowsHorizontal => usePhosphor
      ? PhosphorIconsRegular.arrowsHorizontal
      : Icons.vertical_align_center;
  static IconData get expandLess =>
      usePhosphor ? PhosphorIconsRegular.caretUp : Icons.expand_less;
  static IconData get expandMore =>
      usePhosphor ? PhosphorIconsRegular.caretDown : Icons.expand_more;

  // ============================================
  // EDITOR
  // ============================================
  static IconData get cut =>
      usePhosphor ? PhosphorIconsRegular.scissors : Icons.content_cut;
  static IconData get copy =>
      usePhosphor ? PhosphorIconsRegular.copy : Icons.content_copy;
  static IconData get paste =>
      usePhosphor ? PhosphorIconsRegular.clipboard : Icons.paste;
  static IconData get selectAll =>
      usePhosphor ? PhosphorIconsRegular.selectionAll : Icons.select_all;
  static IconData get deselect =>
      usePhosphor ? PhosphorIconsRegular.selectionSlash : Icons.deselect;
  static IconData get gridOn =>
      usePhosphor ? PhosphorIconsRegular.gridFour : Icons.grid_on;
  static IconData get pencil =>
      usePhosphor ? PhosphorIconsRegular.pencilSimple : Icons.edit;
  static IconData get eraser =>
      usePhosphor ? PhosphorIconsRegular.eraser : Icons.backspace_outlined;
  static IconData get cursor =>
      usePhosphor ? PhosphorIconsRegular.cursor : Icons.touch_app;
  static IconData get selection =>
      usePhosphor ? PhosphorIconsRegular.selection : Icons.crop_free;
  static IconData get colorLens =>
      usePhosphor ? PhosphorIconsRegular.palette : Icons.color_lens;

  // ============================================
  // FILES & FOLDERS
  // ============================================
  static IconData get folder =>
      usePhosphor ? PhosphorIconsRegular.folder : Icons.folder;
  static IconData get folderOpen =>
      usePhosphor ? PhosphorIconsRegular.folderOpen : Icons.folder_open;
  static IconData get save =>
      usePhosphor ? PhosphorIconsRegular.floppyDisk : Icons.save;
  static IconData get saveAs =>
      usePhosphor ? PhosphorIconsRegular.floppyDiskBack : Icons.save_as;
  static IconData get download =>
      usePhosphor ? PhosphorIconsRegular.download : Icons.file_download;
  static IconData get file =>
      usePhosphor ? PhosphorIconsRegular.file : Icons.description;
  static IconData get fileText =>
      usePhosphor ? PhosphorIconsRegular.fileText : Icons.description;
  static IconData get openInNew =>
      usePhosphor ? PhosphorIconsRegular.arrowSquareOut : Icons.open_in_new;
  static IconData get history =>
      usePhosphor ? PhosphorIconsRegular.clockCounterClockwise : Icons.history;

  // ============================================
  // UI CONTROLS
  // ============================================
  static IconData get lock =>
      usePhosphor ? PhosphorIconsRegular.lock : Icons.lock;
  static IconData get lockOpen =>
      usePhosphor ? PhosphorIconsRegular.lockOpen : Icons.lock_open;
  static IconData get eye =>
      usePhosphor ? PhosphorIconsRegular.eye : Icons.visibility;
  static IconData get eyeSlash =>
      usePhosphor ? PhosphorIconsRegular.eyeSlash : Icons.visibility_off;
  static IconData get star =>
      usePhosphor ? PhosphorIconsRegular.star : Icons.star;
  static IconData get starFilled =>
      usePhosphor ? PhosphorIconsRegular.starHalf : Icons.star;
  static IconData get bookmark =>
      usePhosphor ? PhosphorIconsRegular.bookmark : Icons.bookmark_add;
  static IconData get layers =>
      usePhosphor ? PhosphorIconsRegular.stack : Icons.layers;
  static IconData get sliders =>
      usePhosphor ? PhosphorIconsRegular.slidersHorizontal : Icons.tune;
  static IconData get circle =>
      usePhosphor ? PhosphorIconsRegular.circle : Icons.circle_outlined;
  static IconData get radioChecked => usePhosphor
      ? PhosphorIconsRegular.radioButton
      : Icons.radio_button_checked;
  static IconData get checkBox =>
      usePhosphor ? PhosphorIconsRegular.checkSquare : Icons.check_box;
  static IconData get checkBoxBlank =>
      usePhosphor ? PhosphorIconsRegular.square : Icons.check_box_outline_blank;
  static IconData get dotsThree =>
      usePhosphor ? PhosphorIconsRegular.dotsThreeVertical : Icons.more_vert;

  // ============================================
  // PLUGIN & EFFECTS
  // ============================================
  static IconData get plugin =>
      usePhosphor ? PhosphorIconsRegular.puzzlePiece : Icons.extension;
  static IconData get pluginOff =>
      usePhosphor ? PhosphorIconsRegular.prohibit : Icons.extension_off;
  static IconData get chartLine =>
      usePhosphor ? PhosphorIconsRegular.chartLine : Icons.show_chart;
  static IconData get cpu =>
      usePhosphor ? PhosphorIconsRegular.cpu : Icons.memory;
  static IconData get monitor =>
      usePhosphor ? PhosphorIconsRegular.monitor : Icons.computer;
  static IconData get lightning =>
      usePhosphor ? PhosphorIconsRegular.lightning : Icons.bolt;
  static IconData get speed =>
      usePhosphor ? PhosphorIconsRegular.speedometer : Icons.speed;

  // ============================================
  // MISC
  // ============================================
  static IconData get keyboard =>
      usePhosphor ? PhosphorIconsRegular.keyboard : Icons.keyboard;
  static IconData get rename => usePhosphor
      ? PhosphorIconsRegular.pencilLine
      : Icons.drive_file_rename_outline;
  static IconData get compress =>
      usePhosphor ? PhosphorIconsRegular.arrowsIn : Icons.compress;
  static IconData get expand =>
      usePhosphor ? PhosphorIconsRegular.arrowsOut : Icons.expand;
  static IconData get swap =>
      usePhosphor ? PhosphorIconsRegular.swap : Icons.swap_horiz;
  static IconData get gesture =>
      usePhosphor ? PhosphorIconsRegular.hand : Icons.gesture;
  static IconData get linearScale =>
      usePhosphor ? PhosphorIconsRegular.slidersHorizontal : Icons.linear_scale;
  static IconData get input =>
      usePhosphor ? PhosphorIconsRegular.signIn : Icons.input;
  // ignore: non_constant_identifier_names
  static IconData get list =>
      usePhosphor ? PhosphorIconsRegular.list : Icons.photo_library_outlined;
}
