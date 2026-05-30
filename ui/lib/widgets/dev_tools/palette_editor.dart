import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_provider.dart';
import '../../theme/tokens.dart';

/// All editable color tokens with their override keys and display names.
const _bgTokens = [
  ('editor', 'Editor'),
  ('darkest', 'Darkest'),
  ('dark', 'Dark'),
  ('standard', 'Standard'),
  ('elevated', 'Elevated'),
  ('surface', 'Surface'),
  ('divider', 'Divider'),
  ('hover', 'Hover'),
];

const _textTokens = [
  ('text_primary', 'Text Primary'),
  ('text_secondary', 'Text Secondary'),
  ('text_muted', 'Text Muted'),
];

const _accentTokens = [
  ('accent_primary', 'Accent'),
  ('accent_hover', 'Accent Hover'),
];

// Palette ramp A/B presets. The default ("Gunmetal") lives in
// app_colors.dart `_darkBackgrounds`; the "Gunmetal"/Current chip just clears
// overrides. These are alternative ramps to flip between live.

/// Preset: Graphite — flat near-neutral dark grey (no blue undertone).
const Map<String, Color> _graphitePreset = {
  'editor': Color(0xFF0C0D0F),
  'darkest': Color(0xFF131417),
  'dark': Color(0xFF1B1C1F),
  'standard': Color(0xFF202226),
  'elevated': Color(0xFF25272B),
  'surface': Color(0xFF2E3035),
  'divider': Color(0xFF3A3C42),
  'hover': Color(0xFF45474E),
};

/// Preset: Slate — subtle cool blue-grey, between Graphite and Indigo.
const Map<String, Color> _slatePreset = {
  'editor': Color(0xFF0C0E12),
  'darkest': Color(0xFF121419),
  'dark': Color(0xFF1B1E25),
  'standard': Color(0xFF20242C),
  'elevated': Color(0xFF262A33),
  'surface': Color(0xFF2F333D),
  'divider': Color(0xFF3A3F49),
  'hover': Color(0xFF464B56),
};

/// Preset: Indigo deep-space — the cool blue-black ramp (more navy).
const Map<String, Color> _indigoPreset = {
  'editor': Color(0xFF0C0E15),
  'darkest': Color(0xFF10131C),
  'dark': Color(0xFF181C2A),
  'standard': Color(0xFF1D2231),
  'elevated': Color(0xFF222942),
  'surface': Color(0xFF2C3349),
  'divider': Color(0xFF363E58),
  'hover': Color(0xFF424A66),
};

/// A floating dev tool for live-editing the color palette.
/// Toggle with Cmd+Shift+P in debug builds.
class PaletteEditor extends StatefulWidget {
  final VoidCallback onClose;

  const PaletteEditor({super.key, required this.onClose});

  @override
  State<PaletteEditor> createState() => _PaletteEditorState();
}

class _PaletteEditorState extends State<PaletteEditor> {
  Offset _position = const Offset(20, 60);
  String _activePreset = 'current';

  Color _getDefaultColor(ThemeProvider provider, String token) {
    final defaults = BoojyColors(provider.currentTheme);
    switch (token) {
      case 'editor':
        return defaults.editor;
      case 'darkest':
        return defaults.darkest;
      case 'dark':
        return defaults.dark;
      case 'standard':
        return defaults.standard;
      case 'elevated':
        return defaults.elevated;
      case 'surface':
        return defaults.surface;
      case 'divider':
        return defaults.divider;
      case 'hover':
        return defaults.hover;
      case 'text_primary':
        return defaults.textPrimary;
      case 'text_secondary':
        return defaults.textSecondary;
      case 'text_muted':
        return defaults.textMuted;
      case 'accent_primary':
        return defaults.accent;
      case 'accent_hover':
        return defaults.accentHover;
      default:
        return const Color(0xFFFF00FF);
    }
  }

  Color _getCurrentColor(ThemeProvider provider, String token) {
    final override = provider.colorOverrides[token];
    return override ?? _getDefaultColor(provider, token);
  }

  void _applyPreset(ThemeProvider provider, String name) {
    setState(() => _activePreset = name);
    switch (name) {
      case 'current':
        provider.clearOverrides();
        break;
      case 'graphite':
        provider.applyPreset(_graphitePreset);
        break;
      case 'slate':
        provider.applyPreset(_slatePreset);
        break;
      case 'indigo':
        provider.applyPreset(_indigoPreset);
        break;
    }
  }

  void _copyCode(ThemeProvider provider) {
    final buf = StringBuffer();
    buf.writeln('// Palette overrides (paste into app_colors.dart)');
    for (final (token, label) in [
      ..._bgTokens,
      ..._textTokens,
      ..._accentTokens,
    ]) {
      final color = _getCurrentColor(provider, token);
      final hex = color
          .toARGB32()
          .toRadixString(16)
          .padLeft(8, '0')
          .toUpperCase();
      buf.writeln("  '$token': Color(0x$hex), // $label");
    }
    Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Palette copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ThemeProvider>(context);
    final colors = provider.colors;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _position += d.delta),
        child: Material(
          elevation: 16,
          borderRadius: BorderRadius.circular(8),
          color: colors.elevated,
          child: Container(
            width: 280,
            constraints: const BoxConstraints(maxHeight: 500),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.divider),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(colors),
                _buildPresetBar(provider, colors),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      _buildSection('Background', _bgTokens, provider, colors),
                      _buildSection('Text', _textTokens, provider, colors),
                      _buildSection('Accent', _accentTokens, provider, colors),
                    ],
                  ),
                ),
                _buildFooter(provider, colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BoojyColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          Icon(Icons.palette_outlined, size: 16, color: colors.textSecondary),
          const SizedBox(width: 8),
          Text(
            'Palette Editor',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: widget.onClose,
            child: Icon(Icons.close, size: 16, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetBar(ThemeProvider provider, BoojyColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.divider)),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          _presetChip('Gunmetal', 'current', provider, colors),
          _presetChip('Graphite', 'graphite', provider, colors),
          _presetChip('Slate', 'slate', provider, colors),
          _presetChip('Indigo', 'indigo', provider, colors),
        ],
      ),
    );
  }

  Widget _presetChip(
    String label,
    String name,
    ThemeProvider provider,
    BoojyColors colors,
  ) {
    final isActive = _activePreset == name;
    return GestureDetector(
      onTap: () => _applyPreset(provider, name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? colors.accent : colors.dark,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isActive ? colors.accent : colors.divider),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : colors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    String title,
    List<(String, String)> tokens,
    ThemeProvider provider,
    BoojyColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Text(
            title,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
        ),
        ...tokens.map((t) => _buildColorRow(t.$1, t.$2, provider, colors)),
      ],
    );
  }

  Widget _buildColorRow(
    String token,
    String label,
    ThemeProvider provider,
    BoojyColors colors,
  ) {
    final color = _getCurrentColor(provider, token);
    final hex = color
        .toARGB32()
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
    final isOverridden = provider.colorOverrides.containsKey(token);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: colors.divider),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isOverridden ? colors.accent : colors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          SizedBox(
            width: 70,
            height: 24,
            child: TextField(
              controller: TextEditingController(text: hex),
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 11,
                fontFamily: BT.fontFamilyMono,
                fontFamilyFallback: const ['SF Mono', 'Menlo', 'monospace'],
              ),
              decoration: InputDecoration(
                prefixText: '#',
                prefixStyle: TextStyle(color: colors.textMuted, fontSize: 11),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 4,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide: BorderSide(color: colors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide: BorderSide(color: colors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(3),
                  borderSide: BorderSide(color: colors.accent),
                ),
                filled: true,
                fillColor: colors.darkest,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                LengthLimitingTextInputFormatter(6),
              ],
              onSubmitted: (value) {
                if (value.length == 6) {
                  final parsed = int.tryParse('FF$value', radix: 16);
                  if (parsed != null) {
                    setState(() => _activePreset = 'custom');
                    provider.setColorOverride(token, Color(parsed));
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeProvider provider, BoojyColors colors) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.divider)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              setState(() => _activePreset = 'current');
              provider.clearOverrides();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colors.dark,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.divider),
              ),
              child: Text(
                'Reset',
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _copyCode(provider),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Copy Code',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
