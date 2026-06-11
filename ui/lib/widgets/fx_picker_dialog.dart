import 'package:flutter/material.dart';

import '../models/library_item.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';

/// Whether the user wants an insert effect or a shared send bus.
enum FxPickerMode { insert, shared }

/// Result from the FX picker dialog.
class FxPickerResult {
  final FxPickerMode mode;
  final String effectType;
  final String effectName;

  const FxPickerResult({
    required this.mode,
    required this.effectType,
    required this.effectName,
  });
}

/// Built-in effects available in the picker.
final List<EffectItem> kBuiltInFxPickerEffects = [
  EffectItem(id: 'fx_reverb', name: 'Reverb', effectType: 'reverb'),
  EffectItem(id: 'fx_delay', name: 'Delay', effectType: 'delay'),
  EffectItem(id: 'fx_eq', name: 'EQ', effectType: 'eq'),
  EffectItem(id: 'fx_compressor', name: 'Compressor', effectType: 'compressor'),
  EffectItem(id: 'fx_chorus', name: 'Chorus', effectType: 'chorus'),
  EffectItem(id: 'fx_limiter', name: 'Limiter', effectType: 'limiter'),
];

/// Dialog for adding an insert effect or shared send from the ⚡ button.
Future<FxPickerResult?> showFxPickerDialog({
  required BuildContext context,
  required String trackName,
  bool insertOnly = false,
}) {
  return showDialog<FxPickerResult>(
    context: context,
    builder: (dialogContext) =>
        _FxPickerDialog(trackName: trackName, insertOnly: insertOnly),
  );
}

class _FxPickerDialog extends StatefulWidget {
  final String trackName;
  final bool insertOnly;

  const _FxPickerDialog({required this.trackName, required this.insertOnly});

  @override
  State<_FxPickerDialog> createState() => _FxPickerDialogState();
}

class _FxPickerDialogState extends State<_FxPickerDialog> {
  FxPickerMode _mode = FxPickerMode.insert;
  String _query = '';

  List<EffectItem> get _filteredEffects {
    final effects = widget.insertOnly || _mode == FxPickerMode.insert
        ? kBuiltInFxPickerEffects
        : _sharedEffectsOrder;

    if (_query.trim().isEmpty) return effects;
    final q = _query.toLowerCase();
    return effects
        .where((e) => e.name.toLowerCase().contains(q))
        .toList(growable: false);
  }

  /// Shared mode: Reverb and Delay first per plan.
  List<EffectItem> get _sharedEffectsOrder {
    const priority = ['reverb', 'delay'];
    final sorted = [...kBuiltInFxPickerEffects];
    sorted.sort((a, b) {
      final ai = priority.indexOf(a.effectType);
      final bi = priority.indexOf(b.effectType);
      if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
      if (ai >= 0) return -1;
      if (bi >= 0) return 1;
      return a.name.compareTo(b.name);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.elevated,
      title: Text(
        'Add effect — ${widget.trackName}',
        style: TextStyle(color: colors.textPrimary, fontSize: 14),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.insertOnly) ...[
              _ModeOptionTile(
                label: 'On this track',
                selected: _mode == FxPickerMode.insert,
                onTap: () => setState(() => _mode = FxPickerMode.insert),
              ),
              _ModeOptionTile(
                label: 'Shared (send)',
                selected: _mode == FxPickerMode.shared,
                onTap: () => setState(() => _mode = FxPickerMode.shared),
              ),
              Divider(color: colors.divider, height: 16),
            ],
            TextField(
              decoration: InputDecoration(
                hintText: 'Search effects...',
                hintStyle: TextStyle(color: colors.textMuted, fontSize: 12),
                prefixIcon: Icon(BI.search, size: 18, color: colors.textMuted),
                isDense: true,
                filled: true,
                fillColor: colors.dark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.hover),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: colors.hover),
                ),
              ),
              style: TextStyle(color: colors.textPrimary, fontSize: 12),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredEffects.length,
                itemBuilder: (context, index) {
                  final effect = _filteredEffects[index];
                  return ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(
                      effect.name,
                      style: TextStyle(color: colors.textPrimary, fontSize: 13),
                    ),
                    onTap: () {
                      Navigator.of(context).pop(
                        FxPickerResult(
                          mode: widget.insertOnly ? FxPickerMode.insert : _mode,
                          effectType: effect.effectType,
                          effectName: effect.name,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
      ],
    );
  }
}

class _ModeOptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeOptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? BI.radioChecked : BI.radioUnchecked,
        size: 18,
        color: selected ? colors.accent : colors.textMuted,
      ),
      title: Text(
        label,
        style: TextStyle(color: colors.textPrimary, fontSize: 13),
      ),
      onTap: onTap,
    );
  }
}
