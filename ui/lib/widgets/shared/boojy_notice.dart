import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/animation_constants.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import '../../utils/logger.dart';

/// Boojy's one way to tell the user something. Two levels only:
///
///   Info:    a hint after an action that did nothing ("Select a clip
///            first"). Fades after [Notices.infoDuration],
///            hovering pauses the fade. One at a time; a new one replaces it.
///   Problem: something went wrong or needs the user ("Couldn't save the
///            project"). A small amber ⚠, stays until closed or cleared by
///            [Notices.clear]. Up to [Notices.maxProblems]; the oldest drops.
///
/// Never post success ("Project saved"): silence means it worked.
///
/// Look (Tyr, 2026-09-30: "clean and simple"): both levels share one quiet
/// pill, neutral outline, no shadow; the ⚠ is the only colour and the action
/// is plain accent text. Don't add coloured outlines or fills.
///
/// Posting needs no BuildContext, so it is safe from event handlers:
///   Notices.info('Select a clip first');
///   Notices.problem("Couldn't save the project", error: e,
///       action: NoticeAction('Save As…', saveProjectAs));
///   Notices.problem('Boojy can't hear your input', id: 'audio-input');
///   Notices.clear('audio-input'); // once it's fixed
///
/// [NoticeHost] (mounted once in `main.dart`) draws them at the bottom-centre
/// of whatever wraps itself in [NoticeAnchor] (the arrangement), or of the
/// window when no anchor is on screen.
enum NoticeLevel { info, problem }

/// The one optional button on a notice.
class NoticeAction {
  final String label;
  final VoidCallback onTap;

  const NoticeAction(this.label, this.onTap);
}

class Notice {
  /// Unique per post, so a re-posted notice animates in again.
  final int serial;

  /// Optional stable id: a problem with the same id replaces the old one and
  /// can be removed with [Notices.clear].
  final String? id;
  final String text;
  final NoticeLevel level;
  final NoticeAction? action;

  const Notice._({
    required this.serial,
    required this.id,
    required this.text,
    required this.level,
    required this.action,
  });
}

class Notices extends ChangeNotifier {
  Notices._();

  static final Notices instance = Notices._();

  static const Duration infoDuration = Duration(seconds: 3);
  static const int maxProblems = 3;

  /// The arrangement registers this through [NoticeAnchor].
  final LayerLink anchorLink = LayerLink();

  Notice? _info;
  final List<Notice> _problems = [];
  Timer? _infoTimer;
  int _serial = 0;

  Notice? get currentInfo => _info;
  List<Notice> get problems => List.unmodifiable(_problems);

  /// Show a hint that fades on its own. Replaces any current info.
  static void info(String text) => instance._postInfo(text);

  /// Show a problem that stays until closed or [clear]ed. [error] goes to the
  /// log only: the on-screen text should be plain words.
  static void problem(
    String text, {
    String? id,
    NoticeAction? action,
    Object? error,
  }) => instance._postProblem(text, id: id, action: action, error: error);

  /// Remove the problem posted with [id], if it is showing.
  static void clear(String id) => instance._clearId(id);

  void _postInfo(String text) {
    _info = Notice._(
      serial: ++_serial,
      id: null,
      text: text,
      level: NoticeLevel.info,
      action: null,
    );
    _startInfoTimer();
    notifyListeners();
  }

  void _postProblem(
    String text, {
    String? id,
    NoticeAction? action,
    Object? error,
  }) {
    Log.e(error == null ? text : '$text: $error');
    _problems.removeWhere(
      (p) => id != null ? p.id == id : (p.id == null && p.text == text),
    );
    _problems.add(
      Notice._(
        serial: ++_serial,
        id: id,
        text: text,
        level: NoticeLevel.problem,
        action: action,
      ),
    );
    while (_problems.length > maxProblems) {
      _problems.removeAt(0);
    }
    notifyListeners();
  }

  void _clearId(String id) {
    final before = _problems.length;
    _problems.removeWhere((p) => p.id == id);
    if (_problems.length != before) notifyListeners();
  }

  /// Close one notice (the ✕ button, or the info timer).
  void dismiss(Notice notice) {
    if (identical(notice, _info)) {
      _infoTimer?.cancel();
      _info = null;
    } else if (!_problems.remove(notice)) {
      return;
    }
    notifyListeners();
  }

  /// Hovering the info notice holds it on screen.
  void pauseInfo() => _infoTimer?.cancel();

  /// Leaving it starts a fresh fade countdown.
  void resumeInfo() {
    if (_info != null) _startInfoTimer();
  }

  void _startInfoTimer() {
    _infoTimer?.cancel();
    final shown = _info;
    _infoTimer = Timer(infoDuration, () {
      if (shown != null) dismiss(shown);
    });
  }

  @visibleForTesting
  void reset() {
    _infoTimer?.cancel();
    _info = null;
    _problems.clear();
    notifyListeners();
  }
}

/// Marks the area notices centre on (the arrangement).
class NoticeAnchor extends StatelessWidget {
  final Widget child;

  const NoticeAnchor({super.key, required this.child});

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
    link: Notices.instance.anchorLink,
    child: child,
  );
}

/// Draws the notice stack over [child] (the app's Navigator), so notices sit
/// above dialogs too. Mounted once, in `MaterialApp.builder`.
class NoticeHost extends StatelessWidget {
  final Widget child;

  const NoticeHost({super.key, required this.child});

  /// Gap between the notices and the bottom of the anchor.
  static const double _bottomGap = BT.lg;

  @override
  Widget build(BuildContext context) {
    final notices = Notices.instance;
    return Stack(
      children: [
        child,
        ListenableBuilder(
          listenable: notices,
          builder: (context, _) {
            final stack = _NoticeStack(
              problems: notices.problems,
              info: notices.currentInfo,
            );
            if (notices.anchorLink.leader != null) {
              // Follows the arrangement as panels open, close and resize.
              return Positioned(
                left: 0,
                top: 0,
                child: CompositedTransformFollower(
                  link: notices.anchorLink,
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.bottomCenter,
                  followerAnchor: Alignment.bottomCenter,
                  offset: const Offset(0, -_bottomGap),
                  child: stack,
                ),
              );
            }
            return Positioned(
              left: 0,
              right: 0,
              bottom: _bottomGap,
              child: Center(child: stack),
            );
          },
        ),
      ],
    );
  }
}

class _NoticeStack extends StatelessWidget {
  final List<Notice> problems;
  final Notice? info;

  const _NoticeStack({required this.problems, required this.info});

  @override
  Widget build(BuildContext context) {
    // Problems share one width (the widest), so a stack reads as a tidy
    // column; the info pill stays compact and centred under them.
    return Material(
      type: MaterialType.transparency,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final p in problems)
              Padding(
                key: ValueKey(p.serial),
                padding: const EdgeInsets.only(bottom: BT.sm),
                child: _Entrance(child: _NoticePill(notice: p)),
              ),
            AnimatedSwitcher(
              duration: AnimationConstants.hoverDuration,
              reverseDuration: AnimationConstants.slowDuration,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: info == null
                  ? const SizedBox.shrink()
                  : Center(
                      key: ValueKey(info!.serial),
                      child: MouseRegion(
                        onEnter: (_) => Notices.instance.pauseInfo(),
                        onExit: (_) => Notices.instance.resumeInfo(),
                        child: _Entrance(child: _NoticePill(notice: info!)),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet entrance: fade in while rising a few pixels.
class _Entrance extends StatelessWidget {
  final Widget child;

  const _Entrance({required this.child});

  static const double _rise = 6.0;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AnimationConstants.hoverDuration,
      curve: AnimationConstants.standardCurve,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * _rise),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _NoticePill extends StatelessWidget {
  final Notice notice;

  const _NoticePill({required this.notice});

  /// Touch-ready minimum for the ✕ (docs/EDITING.md rule 2).
  static const double _minTap = 32.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isProblem = notice.level == NoticeLevel.problem;
    final action = notice.action;
    final text = Text(
      notice.text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: BT.body(colors.textPrimary),
    );
    final paddedText = Padding(
      padding: const EdgeInsets.symmetric(vertical: BT.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        child: text,
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: BT.dialogWidthMd),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.elevated,
          borderRadius: BT.borderLg,
          border: Border.all(color: colors.divider),
        ),
        // The text's own padding sets the height, so every pill is the same
        // height per line and grows with a second line; the ✕ and the action
        // stretch to that height (big tap areas, no extra height).
        child: Padding(
          padding: EdgeInsets.only(
            left: BT.md,
            right: isProblem ? BT.xxs : BT.md,
          ),
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isProblem) ...[
                  Icon(BI.warning, size: BT.iconMd, color: colors.warning),
                  const SizedBox(width: BT.sm),
                ],
                // Problems stretch to the stack's width (✕ on the right edge);
                // info hugs its text.
                if (isProblem)
                  Expanded(child: paddedText)
                else
                  Flexible(child: paddedText),
                if (action != null) ...[
                  const SizedBox(width: BT.xs),
                  _TextAction(
                    label: action.label,
                    onTap: () {
                      Notices.instance.dismiss(notice);
                      action.onTap();
                    },
                  ),
                ],
                if (isProblem)
                  Semantics(
                    button: true,
                    label: 'Close',
                    child: InkResponse(
                      onTap: () => Notices.instance.dismiss(notice),
                      radius: _minTap / 2,
                      child: SizedBox(
                        width: _minTap,
                        child: Icon(
                          BI.close,
                          size: BT.iconMd,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The notice's one button: plain accent text, no box. The tap area is the
/// full pill height (touch-ready) while the look stays a word.
class _TextAction extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _TextAction({required this.label, required this.onTap});

  @override
  State<_TextAction> createState() => _TextActionState();
}

class _TextActionState extends State<_TextAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: BT.sm),
            child: Center(
              widthFactor: 1,
              child: Text(
                widget.label,
                style: BT.body(
                  _hovered ? colors.accentHover : colors.accent,
                  weight: BT.weightMedium,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
