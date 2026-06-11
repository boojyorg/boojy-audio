import 'package:flutter/material.dart';
import '../../../audio_engine.dart';
import '../../../services/commands/command.dart';
import '../../../services/commands/effect_commands.dart';
import '../../../services/undo_redo_manager.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/boojy_icons.dart';
import '../../../theme/theme_extension.dart';
import '../../../theme/tokens.dart';
import '../../effect_parameter_panel.dart';
import '../../shared/mini_knob.dart';
import 'eq_curve_painter.dart';

/// The graph-based body of the Graphic EQ device card (spec §2):
/// a draggable frequency-response graph on top, a row of knobs editing the
/// selected band, and a bottom utility line (Add Band / Low Cut / High Cut /
/// Output). Whole-EQ on/off + meter live in the surrounding DeviceBox shell.
class EqDeviceBody extends StatefulWidget {
  final EffectData effect;
  final AudioEngine? engine;

  /// Reload the parent's effect state from the engine (after a committed change).
  final VoidCallback onChanged;

  /// Suppress the parent's periodic poll while a drag is in progress, so live
  /// values aren't snapped back mid-gesture.
  final ValueChanged<bool> onDragStateChanged;

  const EqDeviceBody({
    super.key,
    required this.effect,
    required this.engine,
    required this.onChanged,
    required this.onDragStateChanged,
  });

  @override
  State<EqDeviceBody> createState() => _EqDeviceBodyState();
}

class _EqDeviceBodyState extends State<EqDeviceBody> {
  // The engine forces 48 kHz; the curve mirrors that (see C12 scope note).
  static const double _sr = 48000.0;
  static const int _maxBands = 8;

  int? _selected;
  final Map<String, double> _live = {};
  final Map<String, double> _knobStart = {};

  int? _dragBand;
  double _dragFreq0 = 0;
  double _dragGain0 = 0;
  Size _graphSize = Size.zero;

  @override
  void didUpdateWidget(EqDeviceBody old) {
    super.didUpdateWidget(old);
    // Fresh engine truth arrived → drop optimistic overrides.
    if (!identical(old.effect, widget.effect)) {
      _live.clear();
      if (_selected != null && _selected! >= _count) _selected = null;
    }
  }

  // ---- state reads (optimistic override → engine value → default) ----
  double? _raw(String k) => _live[k] ?? widget.effect.parameters[k];
  int get _count => (_raw('band_count') ?? 0).round();
  bool get _lowCut => (_raw('low_cut_on') ?? 0) >= 0.5;
  bool get _highCut => (_raw('high_cut_on') ?? 0) >= 0.5;
  double get _output => _raw('output_gain') ?? 0;

  List<EqBandView> _bands() {
    final out = <EqBandView>[];
    for (var i = 0; i < _count; i++) {
      out.add(
        EqBandView(
          index: i,
          freq: _raw('band_${i}_freq') ?? 1000,
          gainDb: _raw('band_${i}_gain') ?? 0,
          focus: _raw('band_${i}_focus') ?? 0.4,
          shape: (_raw('band_${i}_shape') ?? EqShape.bell).round(),
          on: (_raw('band_${i}_on') ?? 1) >= 0.5,
        ),
      );
    }
    return out;
  }

  /// Effective selection: falls back to band 0 so the Freq/Gain/Focus knobs
  /// are never in a dead "–" state while bands exist (a knob row that looks
  /// disabled reads as broken, especially to beginners).
  int? get _effectiveSelected {
    if (_count == 0) return null;
    final s = _selected;
    if (s == null || s < 0 || s >= _count) return 0;
    return s;
  }

  EqBandView? _selectedBand(List<EqBandView> bands) {
    final s = _effectiveSelected;
    if (s == null || s >= bands.length) return null;
    return bands[s];
  }

  void _refresh() {
    if (mounted) widget.onChanged();
  }

  // ---- commits ----
  void _commit(String name, double oldV, double newV) {
    if ((newV - oldV).abs() < 1e-6) return;
    UndoRedoManager().execute(
      SetEffectParameterCommand(
        effectId: widget.effect.id,
        effectName: 'eq',
        paramIndex: 0,
        paramName: name,
        newValue: newV,
        oldValue: oldV,
        isBuiltIn: true,
        onParameterChanged: (_, __, ___) => _refresh(),
      ),
    );
  }

  // ---- knob live/commit (Freq / Gain / Focus / Output) ----
  void _knobLive(String name, double v) {
    setState(() {
      _knobStart.putIfAbsent(name, () => _raw(name) ?? v);
      _live[name] = v;
    });
    widget.engine?.setEffectParameter(widget.effect.id, name, v);
  }

  void _knobEnd(String name) {
    final old = _knobStart.remove(name);
    final cur = _live[name];
    if (old != null && cur != null) _commit(name, old, cur);
  }

  // ---- toggles (cuts + per-band bypass) ----
  void _toggle(String name) {
    final oldV = (_raw(name) ?? 0) >= 0.5 ? 1.0 : 0.0;
    final newV = oldV >= 0.5 ? 0.0 : 1.0;
    setState(() => _live[name] = newV);
    widget.engine?.setEffectParameter(widget.effect.id, name, newV);
    _commit(name, oldV, newV);
  }

  // ---- structural (add / remove band) ----
  Future<void> _addBand({double? atFreq}) async {
    if (_count >= _maxBands) return;
    final newIndex = _count;
    final Command cmd = atFreq == null
        ? AddEqBandCommand(effectId: widget.effect.id, onChanged: _refresh)
        : CompositeCommand([
            AddEqBandCommand(effectId: widget.effect.id, onChanged: _refresh),
            SetEffectParameterCommand(
              effectId: widget.effect.id,
              effectName: 'eq',
              paramIndex: 0,
              paramName: 'band_${newIndex}_freq',
              newValue: atFreq,
              oldValue: 1000,
              isBuiltIn: true,
              onParameterChanged: (_, __, ___) => _refresh(),
            ),
          ], 'Add EQ Band');
    await UndoRedoManager().execute(cmd);
    if (!mounted) return;
    setState(() => _selected = newIndex);
    widget.onChanged();
  }

  Future<void> _removeBand(int index) async {
    final bands = _bands();
    if (index < 0 || index >= bands.length) return;
    final b = bands[index];
    await UndoRedoManager().execute(
      RemoveEqBandCommand(
        effectId: widget.effect.id,
        index: index,
        freq: b.freq,
        gain: b.gainDb,
        focus: b.focus,
        shape: b.shape.toDouble(),
        on: b.on,
        onChanged: _refresh,
      ),
    );
    if (!mounted) return;
    setState(() => _selected = null);
    widget.onChanged();
  }

  // ---- graph gestures ----
  EqBandView? _hitTest(Offset pos, List<EqBandView> bands) {
    final geo = EqGeometry(_graphSize);
    for (final b in bands) {
      final dx = geo.freqToX(b.freq);
      final dy = geo.gainToY(b.gainDb.clamp(-kEqGainRange, kEqGainRange));
      if ((Offset(dx, dy) - pos).distance <= 12) return b;
    }
    return null;
  }

  void _onPanStart(DragStartDetails d) {
    final bands = _bands();
    final hit = _hitTest(d.localPosition, bands);
    if (hit == null) return;
    setState(() {
      _selected = hit.index;
      _dragBand = hit.index;
      _dragFreq0 = hit.freq;
      _dragGain0 = hit.gainDb;
    });
    widget.onDragStateChanged(true);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final i = _dragBand;
    if (i == null) return;
    final geo = EqGeometry(_graphSize);
    final f = geo.xToFreq(d.localPosition.dx).clamp(kEqFreqMin, kEqFreqMax);
    final g = geo
        .yToGain(d.localPosition.dy)
        .clamp(-kEqGainRange, kEqGainRange);
    setState(() {
      _live['band_${i}_freq'] = f;
      _live['band_${i}_gain'] = g;
    });
    widget.engine?.setEffectParameter(widget.effect.id, 'band_${i}_freq', f);
    widget.engine?.setEffectParameter(widget.effect.id, 'band_${i}_gain', g);
  }

  void _onPanEnd() {
    final i = _dragBand;
    if (i == null) return;
    final newFreq = _live['band_${i}_freq'] ?? _dragFreq0;
    final newGain = _live['band_${i}_gain'] ?? _dragGain0;
    final cmds = <Command>[];
    if ((newFreq - _dragFreq0).abs() > 1e-6) {
      cmds.add(
        SetEffectParameterCommand(
          effectId: widget.effect.id,
          effectName: 'eq',
          paramIndex: 0,
          paramName: 'band_${i}_freq',
          newValue: newFreq,
          oldValue: _dragFreq0,
          isBuiltIn: true,
          onParameterChanged: (_, __, ___) => _refresh(),
        ),
      );
    }
    if ((newGain - _dragGain0).abs() > 1e-6) {
      cmds.add(
        SetEffectParameterCommand(
          effectId: widget.effect.id,
          effectName: 'eq',
          paramIndex: 0,
          paramName: 'band_${i}_gain',
          newValue: newGain,
          oldValue: _dragGain0,
          isBuiltIn: true,
          onParameterChanged: (_, __, ___) => _refresh(),
        ),
      );
    }
    if (cmds.length == 1) {
      UndoRedoManager().execute(cmds.first);
    } else if (cmds.length > 1) {
      UndoRedoManager().execute(CompositeCommand(cmds, 'Move EQ Band'));
    }
    _dragBand = null;
    widget.onDragStateChanged(false);
  }

  void _onTapUp(TapUpDetails d) {
    final bands = _bands();
    final hit = _hitTest(d.localPosition, bands);
    setState(() => _selected = hit?.index);
  }

  void _onDoubleTapDown(TapDownDetails d) {
    final bands = _bands();
    final hit = _hitTest(d.localPosition, bands);
    if (hit != null) {
      _removeBand(hit.index);
    } else {
      final geo = EqGeometry(_graphSize);
      final f = geo.xToFreq(d.localPosition.dx).clamp(kEqFreqMin, kEqFreqMax);
      _addBand(atFreq: f);
    }
  }

  // ---- build ----
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final bands = _bands();
    final selected = _selectedBand(bands);

    return ColoredBox(
      color: colors.standard,
      child: Column(
        children: [
          Expanded(child: _buildGraph(colors, textScale, bands)),
          Divider(height: 1, thickness: 1, color: colors.divider),
          _buildBandRow(colors, textScale, selected),
          Divider(height: 1, thickness: 1, color: colors.divider),
          _buildUtilityRow(colors, textScale),
        ],
      ),
    );
  }

  Widget _buildGraph(
    BoojyColors colors,
    double textScale,
    List<EqBandView> bands,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _graphSize = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _onTapUp,
          onDoubleTapDown: _onDoubleTapDown,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: (_) => _onPanEnd(),
          child: CustomPaint(
            size: Size.infinite,
            painter: EqCurvePainter(
              bands: bands,
              selectedBand: _effectiveSelected,
              lowCutOn: _lowCut,
              highCutOn: _highCut,
              sampleRate: _sr,
              colors: colors,
              textScale: textScale,
            ),
          ),
        );
      },
    );
  }

  Widget _buildBandRow(BoojyColors colors, double textScale, EqBandView? band) {
    final hasSel = band != null;
    final isShelf = band?.isShelf ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _knob(
            colors,
            textScale,
            name: 'Freq',
            enabled: hasSel,
            value: band == null ? 0 : eqFreqToNorm(band.freq),
            display: band == null ? '—' : _fmtFreq(band.freq),
            onChanged: (v) =>
                _knobLive('band_${band!.index}_freq', eqNormToFreq(v)),
            onEnd: () => _knobEnd('band_${band!.index}_freq'),
          ),
          _knob(
            colors,
            textScale,
            name: 'Gain',
            enabled: hasSel,
            min: -kEqGainRange,
            max: kEqGainRange,
            value: band?.gainDb ?? 0,
            display: band == null ? '—' : _fmtDb(band.gainDb),
            onChanged: (v) => _knobLive('band_${band!.index}_gain', v),
            onEnd: () => _knobEnd('band_${band!.index}_gain'),
          ),
          _knob(
            colors,
            textScale,
            name: 'Focus',
            // Shelves use a fixed slope (spec §6.2) → Focus disabled with a tag.
            enabled: hasSel && !isShelf,
            value: band?.focus ?? 0,
            display: !hasSel
                ? '—'
                : (isShelf ? 'Shelf' : '${(band.focus * 100).round()}%'),
            onChanged: (v) => _knobLive('band_${band!.index}_focus', v),
            onEnd: () => _knobEnd('band_${band!.index}_focus'),
          ),
          const Spacer(),
          // Per-band power/bypass cut for v0.6 (design_recs_2026_06_10.md §4):
          // a bare ⏻ next to a trash can reads as "off vs delete" ambiguity;
          // delete + undo covers beginners. The engine band_*_on param stays.
          _iconButton(
            colors,
            icon: BI.delete,
            tooltip: 'Delete band',
            enabled: hasSel,
            onTap: () => _removeBand(band!.index),
          ),
        ],
      ),
    );
  }

  Widget _buildUtilityRow(BoojyColors colors, double textScale) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          _textButton(
            colors,
            label: '+ Add Band',
            enabled: _count < _maxBands,
            onTap: _addBand,
          ),
          const SizedBox(width: 6),
          _toggleChip(
            colors,
            label: 'Low Cut',
            on: _lowCut,
            onTap: () => _toggle('low_cut_on'),
          ),
          const SizedBox(width: 6),
          _toggleChip(
            colors,
            label: 'High Cut',
            on: _highCut,
            onTap: () => _toggle('high_cut_on'),
          ),
          const Spacer(),
          _knob(
            colors,
            textScale,
            name: 'Out',
            enabled: true,
            min: -kEqGainRange,
            max: kEqGainRange,
            value: _output,
            display: _fmtDb(_output),
            onChanged: (v) => _knobLive('output_gain', v),
            onEnd: () => _knobEnd('output_gain'),
          ),
        ],
      ),
    );
  }

  // ---- small UI helpers ----
  Widget _knob(
    BoojyColors colors,
    double textScale, {
    required String name,
    required bool enabled,
    required double value,
    required String display,
    required ValueChanged<double> onChanged,
    required VoidCallback onEnd,
    double min = 0,
    double max = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.4,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: BT.fontCaption * textScale,
                ),
              ),
              const SizedBox(height: 2),
              MiniKnob(
                value: value.clamp(min, max),
                min: min,
                max: max,
                size: 32,
                label: display,
                arcColor: enabled ? colors.accent : colors.divider,
                onChanged: onChanged,
                onChangeEnd: onEnd,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconButton(
    BoojyColors colors, {
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final color = !enabled
        ? colors.textMuted.withValues(alpha: 0.4)
        : (active ? colors.accent : colors.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          iconSize: 18,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: Icon(icon, color: color),
          onPressed: enabled ? onTap : null,
        ),
      ),
    );
  }

  Widget _textButton(
    BoojyColors colors, {
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: enabled ? colors.accent : colors.divider),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? colors.accent : colors.textMuted,
            fontSize: BT.fontLabel,
          ),
        ),
      ),
    );
  }

  Widget _toggleChip(
    BoojyColors colors, {
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: on
              ? colors.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          border: Border.all(color: on ? colors.accent : colors.divider),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? colors.accent : colors.textSecondary,
            fontSize: BT.fontLabel,
          ),
        ),
      ),
    );
  }

  String _fmtFreq(double f) =>
      f < 1000 ? '${f.round()} Hz' : '${(f / 1000).toStringAsFixed(1)} kHz';
  String _fmtDb(double g) => '${g >= 0 ? '+' : ''}${g.toStringAsFixed(1)} dB';
}
