import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../audio_engine.dart';
import '../../models/instrument_data.dart';
import '../../services/undo_redo_manager.dart';
import '../../services/commands/effect_commands.dart';
import '../../services/vst3_editor_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/boojy_icons.dart';
import '../../theme/theme_extension.dart';
import '../../theme/tokens.dart';
import '../effect_parameter_panel.dart';
import '../vst3_instrument_view.dart';
import '../synthesizer_panel.dart';
import 'device_box.dart';
import 'device_dropdown.dart';
import 'signal_flow_arrow.dart';

/// Combined instrument + effects chain view.
///
/// Shows the instrument device first (if present), then effects,
/// in a horizontally scrollable row. Replaces the separate
/// Instrument and Effects tabs with a single unified chain.
class DeviceChainView extends StatefulWidget {
  final int? selectedTrackId;
  final AudioEngine? audioEngine;
  final InstrumentData? instrumentData;
  final bool isFloated;
  final String? trackName;
  final Future<bool?> Function(int effectId, String pluginName)? onFloatPlugin;
  final Future<bool?> Function(int effectId)? onEmbedPlugin;
  final void Function(VoidCallback resetFn)? onResetRegistered;
  final Function(InstrumentData)? onInstrumentParameterChanged;
  final Function(double volumeDb)? onTrackVolumeChanged;

  const DeviceChainView({
    super.key,
    required this.selectedTrackId,
    required this.audioEngine,
    this.instrumentData,
    this.isFloated = false,
    this.trackName,
    this.onFloatPlugin,
    this.onEmbedPlugin,
    this.onResetRegistered,
    this.onInstrumentParameterChanged,
    this.onTrackVolumeChanged,
  });

  @override
  State<DeviceChainView> createState() => _DeviceChainViewState();
}

class _DeviceChainViewState extends State<DeviceChainView>
    with AutomaticKeepAliveClientMixin {
  List<EffectData> _effects = [];
  int? _selectedDeviceId; // null = no selection, -1 = instrument selected
  Timer? _refreshTimer;
  Timer? _meterTimer;
  // Optimistic local overrides for sliders (instant UI feedback during drag)
  final Map<String, double> _localParamOverrides =
      {}; // "effectId:paramName" → value
  bool _isDraggingSlider = false;

  // Per-effect display levels (after decay smoothing). Key = effectId.
  final Map<int, (double, double)> _displayLevels = {};
  DateTime _lastMeterUpdate = DateTime.now();

  // Track volume for the instrument strip thumb
  double _trackVolumeDb = 0.0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadEffects();
    // Poll effects periodically for parameter updates
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _loadEffects(),
    );
    // Poll effect peak levels at 50ms (~20fps) for responsive meters
    _meterTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _updateMeterLevels(),
    );
  }

  @override
  void didUpdateWidget(DeviceChainView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTrackId != widget.selectedTrackId) {
      _loadEffects();
      _selectedDeviceId = null;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _meterTimer?.cancel();
    super.dispose();
  }

  /// Poll per-effect peak levels, apply decay, and sync track volume.
  void _updateMeterLevels() {
    if (widget.audioEngine == null) return;

    final now = DateTime.now();
    final deltaMs = now.difference(_lastMeterUpdate).inMilliseconds;
    _lastMeterUpdate = now;

    final decayPerFrame = (deltaMs / 1000.0) * 0.33;
    var changed = false;

    // Sync track volume from engine (picks up mixer changes)
    _syncTrackVolume();

    // Collect all effect IDs to poll (instrument + chain effects)
    final effectIds = <int>[];
    final instrumentEffectId = widget.instrumentData?.effectId;
    if (instrumentEffectId != null) effectIds.add(instrumentEffectId);
    for (final e in _effects) {
      effectIds.add(e.id);
    }

    for (final id in effectIds) {
      final levelStr = widget.audioEngine!.getEffectPeakLevels(id);
      final parts = levelStr.split(',');
      final leftDb = double.tryParse(parts[0]) ?? -96.0;
      final rightDb =
          double.tryParse(parts.length > 1 ? parts[1] : '') ?? -96.0;

      // Convert dB → normalized: -60dB=0.0, 0dB=1.0
      final rawLeft = ((leftDb + 60.0) / 60.0).clamp(0.0, 1.0);
      final rawRight = ((rightDb + 60.0) / 60.0).clamp(0.0, 1.0);

      final prev = _displayLevels[id] ?? (0.0, 0.0);

      final displayLeft = rawLeft > prev.$1
          ? rawLeft
          : (prev.$1 - decayPerFrame).clamp(0.0, 1.0);
      final displayRight = rawRight > prev.$2
          ? rawRight
          : (prev.$2 - decayPerFrame).clamp(0.0, 1.0);

      if (displayLeft != prev.$1 || displayRight != prev.$2) {
        _displayLevels[id] = (displayLeft, displayRight);
        changed = true;
      }
    }

    if (changed) setState(() {});
  }

  /// Read track volume from engine so mixer slider changes appear here.
  void _syncTrackVolume() {
    if (widget.selectedTrackId == null || widget.audioEngine == null) return;
    final info = widget.audioEngine!.getTrackInfo(widget.selectedTrackId!);
    final match = RegExp(r'volume:([-\d.]+)').firstMatch(info);
    if (match != null) {
      final engineDb = double.tryParse(match.group(1)!) ?? 0.0;
      if ((engineDb - _trackVolumeDb).abs() > 0.01) {
        _trackVolumeDb = engineDb;
      }
    }
  }

  void _loadEffects() {
    // Skip polling while user is dragging a slider to avoid value snapping
    if (_isDraggingSlider) return;

    if (widget.audioEngine == null || widget.selectedTrackId == null) {
      if (_effects.isNotEmpty) setState(() => _effects = []);
      return;
    }

    try {
      final effectIds = widget.audioEngine!.getTrackEffects(
        widget.selectedTrackId!,
      );
      if (effectIds.isEmpty) {
        if (_effects.isNotEmpty) setState(() => _effects = []);
        return;
      }

      final effects = <EffectData>[];
      for (final idStr in effectIds.split(',')) {
        if (idStr.isEmpty) continue;
        final id = int.tryParse(idStr);
        if (id == null) continue;

        final info = widget.audioEngine!.getEffectInfo(id);
        final effect = EffectData.fromInfo(id, info);
        if (effect != null) {
          effects.add(effect);
        }
      }

      // Read track volume for instrument strip thumb
      _loadTrackVolume();

      setState(() {
        _effects = effects;
        _localParamOverrides.clear();
      });
    } catch (e) {
      if (_effects.isNotEmpty) setState(() => _effects = []);
    }
  }

  void _loadTrackVolume() {
    if (widget.audioEngine == null || widget.selectedTrackId == null) return;
    final info = widget.audioEngine!.getTrackInfo(widget.selectedTrackId!);
    // Format: "id:X,name:...,volume:Y,..." — parse volume
    final volumeMatch = RegExp(r'volume:([-\d.]+)').firstMatch(info);
    if (volumeMatch != null) {
      _trackVolumeDb = double.tryParse(volumeMatch.group(1)!) ?? 0.0;
    }
  }

  // --- Effect operations ---

  Future<void> _toggleBypass(int effectId) async {
    final effect = _effects.firstWhere((e) => e.id == effectId);
    final command = BypassEffectCommand(
      effectId: effectId,
      effectName: _getEffectDisplayName(effect.type),
      newBypassed: !effect.bypassed,
      oldBypassed: effect.bypassed,
    );
    await UndoRedoManager().execute(command);
    _loadEffects();
  }

  Future<void> _removeEffect(int effectId) async {
    if (widget.selectedTrackId == null) return;

    final effect = _effects.firstWhere((e) => e.id == effectId);
    final effectIndex = _effects.indexOf(effect);
    final command = RemoveEffectCommand(
      trackId: widget.selectedTrackId!,
      trackName: widget.trackName ?? 'Track',
      effectId: effectId,
      effectName: _getEffectDisplayName(effect.type),
      effectType: effect.type,
      isVst3: effect.type.startsWith('vst3:'),
      effectIndex: effectIndex,
      onEffectRemoved: (_) {
        if (mounted) _loadEffects();
      },
      onEffectAdded: (_) {
        if (mounted) _loadEffects();
      },
    );
    await UndoRedoManager().execute(command);
  }

  Future<void> _addEffect(String type) async {
    if (widget.selectedTrackId == null) return;

    final command = AddEffectCommand(
      trackId: widget.selectedTrackId!,
      trackName: widget.trackName ?? 'Track',
      effectType: type,
      effectName: _getEffectDisplayName(type),
      isVst3: false,
      onEffectAdded: (_) {
        if (mounted) _loadEffects();
      },
      onEffectRemoved: (_) {
        if (mounted) _loadEffects();
      },
    );
    await UndoRedoManager().execute(command);
  }

  void _setEffectParameter(int effectId, String paramName, double value) {
    widget.audioEngine?.setEffectParameter(effectId, paramName, value);
  }

  String _getEffectDisplayName(String type) {
    if (type.startsWith('vst3:')) return type.substring(5);
    switch (type) {
      case 'reverb':
        return 'Reverb';
      case 'delay':
        return 'Delay';
      case 'chorus':
        return 'Chorus';
      case 'compressor':
        return 'Comp';
      case 'eq':
        return 'EQ';
      case 'limiter':
        return 'Limiter';
      default:
        return type;
    }
  }

  IconData _getEffectIcon(String type) {
    if (type.startsWith('vst3:')) return BI.plugin;
    return BI.lightning;
  }

  // --- Dropdown handlers ---

  Future<void> _showInstrumentDropdown(BuildContext ctx, String name) async {
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final position = box.localToGlobal(Offset.zero);

    final action = await DeviceDropdown.showForInstrument(
      ctx,
      position,
      currentName: name,
    );
    if (action == null || !mounted) return;

    switch (action) {
      case ResetAction():
        _resetPluginToDefault?.call();
      case SwapAction():
        // Future: swap instrument implementation
        break;
      case DeleteAction():
        // Future: remove instrument from track
        break;
    }
  }

  Future<void> _showEffectDropdown(
    BuildContext ctx,
    EffectData effect,
    String name,
  ) async {
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final position = box.localToGlobal(Offset.zero);

    setState(() => _selectedDeviceId = effect.id);

    final action = await DeviceDropdown.showForEffect(
      ctx,
      position,
      currentName: name,
    );
    if (action == null || !mounted) return;

    switch (action) {
      case ResetAction():
        // Reset effect parameters to defaults — reload from engine
        break;
      case SwapAction(:final type):
        // Remove old, add new at same position
        await _removeEffect(effect.id);
        await _addEffect(type);
      case DeleteAction():
        await _removeEffect(effect.id);
    }
  }

  VoidCallback? _resetPluginToDefault;

  // --- Keyboard ---

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Escape → deselect
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_selectedDeviceId != null) {
        setState(() => _selectedDeviceId = null);
        return KeyEventResult.handled;
      }
    }

    // Cmd+D → duplicate selected effect
    if (event.logicalKey == LogicalKeyboardKey.keyD &&
        HardwareKeyboard.instance.isMetaPressed) {
      _duplicateSelectedEffect();
      return KeyEventResult.handled;
    }

    // Delete/Backspace → delete selected effect
    if ((event.logicalKey == LogicalKeyboardKey.delete ||
            event.logicalKey == LogicalKeyboardKey.backspace) &&
        _selectedDeviceId != null &&
        _selectedDeviceId != -1) {
      _removeEffect(_selectedDeviceId!);
      setState(() => _selectedDeviceId = null);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // --- Duplicate ---

  Future<void> _duplicateSelectedEffect() async {
    if (_selectedDeviceId == null || _selectedDeviceId == -1) return;
    final effect = _effects.firstWhere(
      (e) => e.id == _selectedDeviceId,
      orElse: () => _effects.first,
    );
    if (effect.id != _selectedDeviceId) return;

    // Add same type of effect
    await _addEffect(effect.type);
  }

  // --- Reorder ---

  Future<void> _reorderEffect(int effectId, int newIndex) async {
    if (widget.selectedTrackId == null) return;

    final oldOrder = _effects.map((e) => e.id).toList();
    final newOrderList = List<int>.from(oldOrder);
    newOrderList.remove(effectId);
    if (newIndex > newOrderList.length) newIndex = newOrderList.length;
    newOrderList.insert(newIndex, effectId);

    final command = ReorderEffectsCommand(
      trackId: widget.selectedTrackId!,
      trackName: widget.trackName ?? 'Track',
      newOrder: newOrderList,
      oldOrder: oldOrder,
    );
    await UndoRedoManager().execute(command);
    _loadEffects();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.colors;

    if (widget.selectedTrackId == null) {
      return ColoredBox(
        color: colors.darkest,
        child: Center(
          child: Text(
            'Select a track to start editing',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: BT.fontBody,
              fontWeight: BT.weightMedium,
            ),
          ),
        ),
      );
    }

    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: () => setState(() => _selectedDeviceId = null),
        child: ColoredBox(
          color: colors.darkest,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final chainHeight = constraints.maxHeight;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildChainItems(colors, chainHeight),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildChainItems(BoojyColors colors, double chainHeight) {
    final items = <Widget>[];
    final hasInstrument = widget.instrumentData != null;

    // Instrument device box (MIDI/Sampler tracks only)
    if (hasInstrument) {
      items.add(_buildInstrumentDevice(colors, chainHeight));
      items.add(_buildArrow(colors, chainHeight));
    }

    // Effect device boxes (draggable for reorder)
    for (var i = 0; i < _effects.length; i++) {
      final effect = _effects[i];
      items.add(
        DragTarget<int>(
          onWillAcceptWithDetails: (details) => details.data != effect.id,
          onAcceptWithDetails: (details) {
            _reorderEffect(details.data, i);
          },
          builder: (context, candidateData, rejectedData) {
            final isDropTarget = candidateData.isNotEmpty;
            return Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDropTarget)
                  Container(
                    width: 2,
                    color: colors.accent,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                  ),
                LongPressDraggable<int>(
                  data: effect.id,
                  axis: Axis.horizontal,
                  feedback: Material(
                    color: Colors.transparent,
                    child: Opacity(
                      opacity: 0.75,
                      child: SizedBox(
                        width: _getEffectWidth(effect.type),
                        height: 120,
                        child: _buildEffectDevice(colors, effect),
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.3,
                    child: _buildEffectDevice(colors, effect),
                  ),
                  child: _buildEffectDevice(colors, effect),
                ),
              ],
            );
          },
        ),
      );
      items.add(_buildArrow(colors, chainHeight));
    }

    // Effect hint placeholder (no effects yet) — replaces [+] button
    if (_effects.isEmpty) {
      items.add(_buildEffectHintPlaceholder(colors, chainHeight));
    } else {
      // [+] Add effect button (only when effects already exist)
      items.add(_buildAddButton(colors, chainHeight));
    }

    return items;
  }

  // --- Instrument device ---

  Widget _buildInstrumentDevice(BoojyColors colors, double chainHeight) {
    final instrument = widget.instrumentData!;
    final isVst3 = instrument.isVst3;
    final name = isVst3
        ? (instrument.pluginName ?? 'VST3 Instrument')
        : (instrument.type == 'synthesizer' ? 'Synth' : instrument.type);
    final icon = isVst3 ? BI.plugin : BI.piano;

    final headerMode = isVst3 ? HeaderMode.none : HeaderMode.mini16;

    final instrumentLevels = instrument.effectId != null
        ? (_displayLevels[instrument.effectId!] ?? (0.0, 0.0))
        : (0.0, 0.0);

    return SizedBox(
      height: chainHeight,
      child: DeviceBox(
        deviceType: DeviceType.instrument,
        deviceKind: isVst3 ? DeviceKind.vst3Plugin : DeviceKind.builtIn,
        headerMode: headerMode,
        name: name,
        icon: icon,
        isEnabled: true,
        isSelected: _selectedDeviceId == -1,
        isFloated: widget.isFloated,
        width: _getInstrumentWidth(chainHeight),
        leftLevel: instrumentLevels.$1,
        rightLevel: instrumentLevels.$2,
        showVolumeThumb: true,
        volumeDb: _trackVolumeDb,
        onVolumeChanged: (db) {
          setState(() => _trackVolumeDb = db);
          widget.audioEngine?.setTrackVolume(widget.selectedTrackId!, db);
          widget.onTrackVolumeChanged?.call(db);
        },
        onToggleEnabled: null, // Instrument on/off: future
        onFloat: isVst3 && widget.onFloatPlugin != null
            ? () => widget.onFloatPlugin!(instrument.effectId!, name)
            : null,
        onEmbed: isVst3 && widget.onEmbedPlugin != null
            ? () => widget.onEmbedPlugin!(instrument.effectId!)
            : null,
        onNameTap: () => _showInstrumentDropdown(context, name),
        child: _buildInstrumentContent(chainHeight),
      ),
    );
  }

  double _getInstrumentWidth(double chainHeight) {
    final instrument = widget.instrumentData;
    if (instrument == null) return 322; // 300 + 22 strip

    if (instrument.isVst3) {
      final preferred =
          VST3EditorService.preferredEditorSize[instrument.effectId ?? -1];
      if (preferred != null) {
        final nativeW = preferred.$1.toDouble();
        final nativeH = preferred.$2.toDouble();
        if (nativeH > 0) {
          // VST3: no header, full chain height available for plugin GUI
          final scale = (chainHeight / nativeH).clamp(0.1, 1.0);
          return nativeW * scale + 22; // +22 for right strip
        }
      }
      return 622; // 600 + 22 strip
    }

    return 322; // 300 + 22 strip (built-in: 16px mini header + 1px divider)
  }

  Widget _buildInstrumentContent(double chainHeight) {
    final instrument = widget.instrumentData!;

    if (instrument.isVst3) {
      if (widget.isFloated) {
        return ColoredBox(
          color: context.colors.standard,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(BI.openInNew, size: 24, color: context.colors.textMuted),
                const SizedBox(height: BT.sm),
                Text(
                  '${instrument.pluginName ?? "Plugin"} is floating',
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: BT.fontLabel,
                  ),
                ),
                const SizedBox(height: BT.xs),
                Text(
                  'Click Embed to show here',
                  style: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: BT.fontCaption,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // Show fallback when panel is too short for a usable plugin GUI.
      // Use a fixed 100px threshold — the plugin scales down via
      // _getInstrumentWidth, so native size isn't the right metric.
      if (chainHeight < 100) {
        return _buildPluginFallback(instrument.pluginName ?? 'Plugin');
      }

      // Embedded VST3 plugin
      return Vst3InstrumentView(
        effectId: instrument.effectId!,
        pluginName: instrument.pluginName ?? 'VST3 Instrument',
        audioEngine: widget.audioEngine,
        isFloated: false,
        onResetRegistered: (resetFn) {
          _resetPluginToDefault = resetFn;
          widget.onResetRegistered?.call(resetFn);
        },
      );
    }

    // Built-in instrument
    return SynthesizerPanel(
      audioEngine: widget.audioEngine,
      trackId: widget.selectedTrackId!,
      instrumentData: widget.instrumentData,
      onParameterChanged: (instrumentData) {
        widget.onInstrumentParameterChanged?.call(instrumentData);
      },
      onClose: () {},
    );
  }

  /// Fallback message when the editor panel is too short for the plugin GUI.
  Widget _buildPluginFallback(String pluginName) {
    return ColoredBox(
      color: context.colors.standard,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Press Float to open',
              style: TextStyle(color: context.colors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 2),
            Text(
              pluginName,
              style: TextStyle(
                color: context.colors.textMuted,
                fontSize: 13,
                fontWeight: BT.weightMedium,
              ),
            ),
            const SizedBox(height: BT.sm),
            Text(
              'Or increase editor\npanel height',
              style: TextStyle(color: context.colors.textMuted, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // --- Effect devices ---

  Widget _buildEffectDevice(BoojyColors colors, EffectData effect) {
    final levels = _displayLevels[effect.id] ?? (0.0, 0.0);
    return DeviceBox(
      deviceType: DeviceType.effect,
      deviceKind: effect.type.startsWith('vst3:')
          ? DeviceKind.vst3Plugin
          : DeviceKind.builtIn,
      headerMode: HeaderMode.full24,
      name: _getEffectDisplayName(effect.type),
      icon: _getEffectIcon(effect.type),
      isEnabled: !effect.bypassed,
      isSelected: _selectedDeviceId == effect.id,
      width: _getEffectWidth(effect.type),
      expandContent: false,
      leftLevel: levels.$1,
      rightLevel: levels.$2,
      onToggleEnabled: () => _toggleBypass(effect.id),
      onNameTap: () => _showEffectDropdown(
        context,
        effect,
        _getEffectDisplayName(effect.type),
      ),
      child: _buildEffectContent(effect),
    );
  }

  double _getEffectWidth(String type) {
    // Widths include 24px right strip
    switch (type) {
      case 'compressor':
        return 192; // 170 + 22
      case 'eq':
        return 192; // 170 + 22
      default:
        return 172; // 150 + 22
    }
  }

  Widget _buildEffectContent(EffectData effect) {
    return Opacity(
      opacity: effect.bypassed ? 0.5 : 1.0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 100),
        child: Container(
          color: context.colors.standard,
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _buildParameterSliders(effect),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildParameterSliders(EffectData effect) {
    switch (effect.type) {
      case 'eq':
        return [
          _paramSlider(effect, 'Low', 'low_gain', -12, 12, 'dB'),
          _paramSlider(effect, 'Mid1', 'mid1_gain', -12, 12, 'dB'),
          _paramSlider(effect, 'Mid2', 'mid2_gain', -12, 12, 'dB'),
          _paramSlider(effect, 'High', 'high_gain', -12, 12, 'dB'),
          _paramSlider(effect, 'Mix', 'wet_dry', 0, 1, ''),
        ];
      case 'compressor':
        return [
          _paramSlider(effect, 'Thresh', 'threshold', -60, 0, 'dB'),
          _paramSlider(effect, 'Ratio', 'ratio', 1, 20, ':1'),
          _paramSlider(effect, 'Attack', 'attack', 1, 100, 'ms'),
          _paramSlider(effect, 'Release', 'release', 10, 1000, 'ms'),
          _paramSlider(effect, 'Mix', 'wet_dry', 0, 1, ''),
        ];
      case 'reverb':
        return [
          _paramSlider(effect, 'Size', 'room_size', 0, 1, ''),
          _paramSlider(effect, 'Damp', 'damping', 0, 1, ''),
          _paramSlider(effect, 'Mix', 'wet_dry', 0, 1, ''),
        ];
      case 'delay':
        return [
          _paramSlider(effect, 'Time', 'time', 10, 2000, 'ms'),
          _paramSlider(effect, 'Fdbk', 'feedback', 0, 0.99, ''),
          _paramSlider(effect, 'Mix', 'wet_dry', 0, 1, ''),
        ];
      case 'chorus':
        return [
          _paramSlider(effect, 'Rate', 'rate', 0.1, 10, 'Hz'),
          _paramSlider(effect, 'Depth', 'depth', 0, 1, ''),
          _paramSlider(effect, 'Mix', 'wet_dry', 0, 1, ''),
        ];
      case 'limiter':
        return [
          _paramSlider(effect, 'Thresh', 'threshold', -24, 0, 'dB'),
          _paramSlider(effect, 'Release', 'release', 10, 1000, 'ms'),
          _paramSlider(effect, 'Mix', 'wet_dry', 0, 1, ''),
        ];
      default:
        return [
          Center(
            child: Text(
              effect.type,
              style: TextStyle(
                color: context.colors.textMuted,
                fontSize: BT.fontLabel,
              ),
            ),
          ),
        ];
    }
  }

  Widget _paramSlider(
    EffectData effect,
    String label,
    String paramName,
    double min,
    double max,
    String unit,
  ) {
    final paramKey = '${effect.id}:$paramName';
    final value =
        (_localParamOverrides[paramKey] ?? effect.parameters[paramName] ?? min)
            .clamp(min, max);
    final displayValue = max >= 100
        ? value.round().toString()
        : value.toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(
              label,
              style: TextStyle(color: context.colors.textMuted, fontSize: 10),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
                activeTrackColor: context.colors.accent,
                inactiveTrackColor: context.colors.surface,
                thumbColor: context.colors.textSecondary,
              ),
              child: Slider(
                value: value,
                min: min,
                max: max,
                onChangeStart: effect.bypassed
                    ? null
                    : (_) => _isDraggingSlider = true,
                onChanged: effect.bypassed
                    ? null
                    : (v) {
                        setState(() => _localParamOverrides[paramKey] = v);
                        _setEffectParameter(effect.id, paramName, v);
                      },
                onChangeEnd: effect.bypassed
                    ? null
                    : (_) {
                        _isDraggingSlider = false;
                        _localParamOverrides.remove(paramKey);
                      },
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '$displayValue$unit',
              style: TextStyle(
                color: context.colors.textMuted,
                fontSize: 9,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // --- Empty state placeholders ---

  Widget _buildEffectHintPlaceholder(BoojyColors colors, double chainHeight) {
    return Builder(
      builder: (placeholderContext) => GestureDetector(
        onTap: () {
          _showAddEffectMenu(placeholderContext, colors);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 150,
            height: chainHeight.clamp(80, 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: colors.divider,
                style: BorderStyle.solid,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(BI.lightning, size: 20, color: colors.textMuted),
                  const SizedBox(height: BT.xs),
                  Text(
                    'Add an effect',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: BT.fontCaption,
                    ),
                  ),
                  Text(
                    'Drag from library\nor click here',
                    style: TextStyle(color: colors.textMuted, fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- Signal flow arrow ---

  Widget _buildArrow(BoojyColors colors, double chainHeight) {
    return SizedBox(
      height: chainHeight,
      child: const Center(child: SignalFlowArrow()),
    );
  }

  // --- Add effect button ---

  Widget _buildAddButton(BoojyColors colors, double chainHeight) {
    return GestureDetector(
      onTap: () => _showAddEffectMenu(context, colors),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 40,
          height: chainHeight.clamp(60, 80),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: colors.divider, style: BorderStyle.solid),
          ),
          child: Center(child: Icon(BI.add, size: 16, color: colors.textMuted)),
        ),
      ),
    );
  }

  void _showAddEffectMenu(BuildContext menuContext, BoojyColors colors) {
    final RenderBox button = menuContext.findRenderObject()! as RenderBox;
    final position = button.localToGlobal(Offset.zero);

    showMenu<String>(
      context: menuContext,
      position: RelativeRect.fromLTRB(
        position.dx + button.size.width - 150,
        position.dy,
        position.dx + button.size.width,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'eq',
          child: Row(
            children: [
              Icon(BI.lightning, size: 14, color: colors.textPrimary),
              const SizedBox(width: 8),
              Text('EQ', style: TextStyle(color: colors.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'compressor',
          child: Row(
            children: [
              Icon(BI.lightning, size: 14, color: colors.textPrimary),
              const SizedBox(width: 8),
              Text('Compressor', style: TextStyle(color: colors.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'reverb',
          child: Row(
            children: [
              Icon(BI.lightning, size: 14, color: colors.textPrimary),
              const SizedBox(width: 8),
              Text('Reverb', style: TextStyle(color: colors.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delay',
          child: Row(
            children: [
              Icon(BI.lightning, size: 14, color: colors.textPrimary),
              const SizedBox(width: 8),
              Text('Delay', style: TextStyle(color: colors.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'chorus',
          child: Row(
            children: [
              Icon(BI.lightning, size: 14, color: colors.textPrimary),
              const SizedBox(width: 8),
              Text('Chorus', style: TextStyle(color: colors.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'limiter',
          child: Row(
            children: [
              Icon(BI.lightning, size: 14, color: colors.textPrimary),
              const SizedBox(width: 8),
              Text('Limiter', style: TextStyle(color: colors.textPrimary)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) _addEffect(value);
    });
  }
}
