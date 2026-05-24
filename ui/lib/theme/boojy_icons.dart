import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

/// Centralized icon definitions for Boojy Audio.
///
/// Uses Material Icons. (A Phosphor A/B path existed previously but was
/// removed when `phosphor_flutter` became incompatible with Flutter 3.44's
/// `final` `IconData`; re-add behind this facade if a 3.44-compatible icon
/// package is adopted.)
///
/// Usage:
///   Icon(BI.play, size: BT.iconMd)
///   Icon(BI.musicNote, size: BT.iconLg)
///
/// `BI` is a short alias for `BoojyIcons` — use it everywhere.
typedef BI = BoojyIcons;

class BoojyIcons {
  BoojyIcons._();

  // ============================================
  // TRANSPORT
  // ============================================
  static IconData get play => Icons.play_arrow;
  static IconData get pause => Icons.pause;
  static IconData get stop => Icons.stop;
  static IconData get record => Icons.circle;
  static IconData get loop => Icons.loop;
  static IconData get skipBack => Icons.first_page;
  static IconData get skipForward => Icons.last_page;
  static IconData get metronome => Icons.av_timer;

  // ============================================
  // MUSIC & AUDIO
  // ============================================
  static IconData get musicNote => Icons.music_note;
  static IconData get musicNotes => Icons.queue_music;
  static IconData get piano => Icons.piano;
  static IconData get waveform => Icons.waves;
  static IconData get audioFile => Icons.audio_file;
  static IconData get equalizer => Icons.graphic_eq;
  static IconData get speakerHigh => Icons.volume_up;
  static IconData get speakerNone => Icons.volume_off;
  static IconData get speakerSlash => Icons.volume_off;
  static IconData get waveSine => Icons.blur_on;
  static IconData get waveSawtooth => Icons.blur_on;
  static IconData get waveSquare => Icons.blur_on;
  static IconData get waveTriangle => Icons.blur_on;
  static IconData get queue => Icons.queue_music;

  // ============================================
  // NAVIGATION & ACTIONS
  // ============================================
  static IconData get close => Icons.close;
  static IconData get add => Icons.add;
  static IconData get remove => Icons.remove;
  static IconData get addCircle => Icons.add_circle_outline;
  static IconData get delete => Icons.delete;
  static IconData get search => Icons.search;
  static IconData get settings => Icons.settings;
  static IconData get check => Icons.check;
  static IconData get checkCircle => Icons.check_circle;
  static IconData get refresh => Icons.refresh;
  // ignore: non_constant_identifier_names
  static IconData get sync => Icons.sync;
  static IconData get help => Icons.help_outline;
  static IconData get info => Icons.info_outline;
  static IconData get warning => Icons.warning_amber_rounded;
  static IconData get error => Icons.error_outline;
  static IconData get hourglass => Icons.hourglass_empty;

  // ============================================
  // ARROWS & CARETS
  // ============================================
  static IconData get caretDown => Icons.arrow_drop_down;
  static IconData get caretUp => Icons.keyboard_arrow_up;
  static IconData get caretLeft => Icons.chevron_left;
  static IconData get caretRight => Icons.chevron_right;
  static IconData get arrowUp => Icons.arrow_upward;
  static IconData get arrowDown => Icons.arrow_downward;
  static IconData get arrowLeft => Icons.arrow_back;
  static IconData get arrowRight => Icons.arrow_forward;
  static IconData get arrowsHorizontal => Icons.vertical_align_center;
  static IconData get expandLess => Icons.expand_less;
  static IconData get expandMore => Icons.expand_more;

  // ============================================
  // EDITOR
  // ============================================
  static IconData get cut => Icons.content_cut;
  static IconData get copy => Icons.content_copy;
  static IconData get paste => Icons.paste;
  static IconData get selectAll => Icons.select_all;
  static IconData get deselect => Icons.deselect;
  static IconData get gridOn => Icons.grid_on;
  static IconData get pencil => Icons.edit;
  static IconData get eraser => Icons.backspace_outlined;
  static IconData get cursor => Icons.touch_app;
  static IconData get selection => Icons.crop_free;
  static IconData get colorLens => Icons.color_lens;

  // ============================================
  // FILES & FOLDERS
  // ============================================
  static IconData get folder => Icons.folder;
  static IconData get folderOpen => Icons.folder_open;
  static IconData get save => Icons.save;
  static IconData get saveAs => Icons.save_as;
  static IconData get download => Icons.file_download;
  static IconData get file => Icons.description;
  static IconData get fileText => Icons.description;
  static IconData get openInNew => Icons.open_in_new;
  static IconData get history => Icons.history;

  // ============================================
  // UI CONTROLS
  // ============================================
  static IconData get lock => Icons.lock;
  static IconData get lockOpen => Icons.lock_open;
  static IconData get eye => Icons.visibility;
  static IconData get eyeSlash => Icons.visibility_off;
  static IconData get star => Icons.star;
  static IconData get starFilled => Icons.star;
  static IconData get bookmark => Icons.bookmark_add;
  static IconData get layers => Icons.layers;
  static IconData get sliders => Icons.tune;
  static IconData get circle => Icons.circle_outlined;
  static IconData get radioChecked => Icons.radio_button_checked;
  static IconData get checkBox => Icons.check_box;
  static IconData get checkBoxBlank => Icons.check_box_outline_blank;
  static IconData get dotsThree => Icons.more_vert;

  // ============================================
  // PLUGIN & EFFECTS
  // ============================================
  static IconData get plugin => Icons.extension;
  static IconData get pluginOff => Icons.extension_off;
  static IconData get chartLine => Icons.show_chart;
  static IconData get cpu => Icons.memory;
  static IconData get monitor => Icons.computer;
  static IconData get lightning => Icons.bolt;
  static IconData get speed => Icons.speed;

  // ============================================
  // MISC
  // ============================================
  static IconData get keyboard => Icons.keyboard;
  static IconData get rename => Icons.drive_file_rename_outline;
  static IconData get compress => Icons.compress;
  static IconData get expand => Icons.expand;
  static IconData get swap => Icons.swap_horiz;
  static IconData get gesture => Icons.gesture;
  static IconData get linearScale => Icons.linear_scale;
  static IconData get input => Icons.input;
  // ignore: non_constant_identifier_names
  static IconData get list => Icons.photo_library_outlined;
}
