import 'package:flutter/material.dart';
import '../effect_parameter_panel.dart';
import '../../audio_engine.dart';
import 'effect_card.dart';

/// Horizontal FX chain view for the bottom panel.
/// Shows effects as cards arranged left-to-right with signal flow indication.
class FxChainView extends StatefulWidget {
  final int? selectedTrackId;
  final AudioEngine? audioEngine;
  final String? trackName;
  final Function(int effectId)? onVst3PopOut;
  final Function(int effectId)? onVst3BringBack;

  const FxChainView({
    super.key,
    required this.selectedTrackId,
    required this.audioEngine,
    this.trackName,
    this.onVst3PopOut,
    this.onVst3BringBack,
  });

  @override
  State<FxChainView> createState() => _FxChainViewState();
}

class _FxChainViewState extends State<FxChainView> {
  List<EffectData> _effects = [];
  Set<int> _floatingVst3s = {}; // Effect IDs that are popped out

  @override
  void initState() {
    super.initState();
    _loadEffects();
  }

  @override
  void didUpdateWidget(FxChainView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTrackId != widget.selectedTrackId) {
      _loadEffects();
    }
  }

  void _loadEffects() {
    if (widget.audioEngine == null || widget.selectedTrackId == null) {
      setState(() => _effects = []);
      return;
    }

    try {
      final effectIds = widget.audioEngine!.getTrackEffects(widget.selectedTrackId!);
      if (effectIds.isEmpty) {
        setState(() => _effects = []);
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

      setState(() => _effects = effects);
    } catch (e) {
      debugPrint('❌ Failed to load effects: $e');
      setState(() => _effects = []);
    }
  }

  void _toggleBypass(int effectId) {
    if (widget.audioEngine == null) return;

    final effect = _effects.firstWhere((e) => e.id == effectId);
    final newBypassed = !effect.bypassed;
    widget.audioEngine!.setEffectBypass(effectId, newBypassed);
    _loadEffects();
  }

  void _removeEffect(int effectId) {
    if (widget.audioEngine == null || widget.selectedTrackId == null) return;

    widget.audioEngine!.removeEffectFromTrack(widget.selectedTrackId!, effectId);
    _floatingVst3s.remove(effectId);
    _loadEffects();
  }

  void _addEffect(String type) {
    if (widget.audioEngine == null || widget.selectedTrackId == null) return;

    final effectId = widget.audioEngine!.addEffectToTrack(widget.selectedTrackId!, type);
    if (effectId >= 0) {
      _loadEffects();
    }
  }

  void _popOutVst3(int effectId) {
    setState(() => _floatingVst3s.add(effectId));
    widget.onVst3PopOut?.call(effectId);
  }

  void _bringBackVst3(int effectId) {
    setState(() => _floatingVst3s.remove(effectId));
    widget.onVst3BringBack?.call(effectId);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedTrackId == null) {
      return _buildNoTrackSelected();
    }

    return Container(
      color: const Color(0xFF1E1E1E),
      child: Column(
        children: [
          // Header
          _buildHeader(),

          // Effects chain (horizontal scrollable)
          Expanded(
            child: _effects.isEmpty ? _buildEmptyState() : _buildEffectsChain(),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTrackSelected() {
    return Container(
      color: const Color(0xFF1E1E1E),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.touch_app,
              size: 48,
              color: Colors.grey[700],
            ),
            const SizedBox(height: 16),
            Text(
              'Select a track to view effects',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF252525),
        border: Border(
          bottom: BorderSide(color: Color(0xFF404040)),
        ),
      ),
      child: Row(
        children: [
          // Track name
          Icon(
            Icons.tune,
            size: 16,
            color: Colors.grey[500],
          ),
          const SizedBox(width: 8),
          Text(
            widget.trackName ?? 'Track ${widget.selectedTrackId}',
            style: const TextStyle(
              color: Color(0xFFA0A0A0),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '— Effects',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 13,
            ),
          ),
          const Spacer(),

          // Add effect button
          _buildAddEffectButton(),
        ],
      ),
    );
  }

  Widget _buildAddEffectButton() {
    return PopupMenuButton<String>(
      onSelected: _addEffect,
      tooltip: 'Add effect',
      offset: const Offset(0, 30),
      color: const Color(0xFF2B2B2B),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF404040),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.add, size: 16, color: Color(0xFFA0A0A0)),
            SizedBox(width: 4),
            Text(
              'Add Effect',
              style: TextStyle(
                color: Color(0xFFA0A0A0),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        _buildMenuItem('eq', Icons.equalizer, 'EQ'),
        _buildMenuItem('compressor', Icons.compress, 'Compressor'),
        _buildMenuItem('reverb', Icons.blur_on, 'Reverb'),
        _buildMenuItem('delay', Icons.av_timer, 'Delay'),
        _buildMenuItem('chorus', Icons.graphic_eq, 'Chorus'),
      ],
    );
  }

  PopupMenuItem<String> _buildMenuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF4CAF50)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Color(0xFFA0A0A0), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.graphic_eq,
            size: 48,
            color: Colors.grey[700],
          ),
          const SizedBox(height: 16),
          Text(
            'No effects',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Click "Add Effect" to get started',
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (widget.audioEngine == null || widget.selectedTrackId == null) return;

    // Adjust index when moving down
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    setState(() {
      final effect = _effects.removeAt(oldIndex);
      _effects.insert(newIndex, effect);
    });

    // Update the backend with the new order
    final newOrder = _effects.map((e) => e.id).toList();
    widget.audioEngine!.reorderTrackEffects(widget.selectedTrackId!, newOrder);
  }

  Widget _buildEffectsChain() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Input indicator
          _buildSignalIndicator('IN'),
          const SizedBox(width: 8),

          // Signal flow arrow
          Icon(
            Icons.arrow_forward,
            size: 16,
            color: Colors.grey[600],
          ),
          const SizedBox(width: 8),

          // Reorderable effects chain
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: _effects.length,
              onReorder: _onReorder,
              proxyDecorator: (child, index, animation) {
                return Material(
                  elevation: 4,
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final effect = _effects[index];
                return ReorderableDragStartListener(
                  key: ValueKey(effect.id),
                  index: index,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: EffectCard(
                          effect: effect,
                          audioEngine: widget.audioEngine,
                          isVst3: effect.type == 'vst3',
                          isFloating: _floatingVst3s.contains(effect.id),
                          onBypassToggle: () => _toggleBypass(effect.id),
                          onPopOut: () => _popOutVst3(effect.id),
                          onBringBack: () => _bringBackVst3(effect.id),
                          onDelete: () => _removeEffect(effect.id),
                          onParameterChanged: _loadEffects,
                        ),
                      ),
                      // Signal flow arrow between effects
                      if (index < _effects.length - 1) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(width: 8),
          // Signal flow arrow
          Icon(
            Icons.arrow_forward,
            size: 16,
            color: Colors.grey[600],
          ),
          const SizedBox(width: 8),

          // Output indicator
          _buildSignalIndicator('OUT'),
        ],
      ),
    );
  }

  Widget _buildSignalIndicator(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2B2B2B),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF404040)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF808080),
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
