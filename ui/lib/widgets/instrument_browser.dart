import 'package:flutter/material.dart';

/// Simple instrument data model
class Instrument {
  final String id;
  final String name;
  final String category;
  final IconData icon;

  const Instrument({
    required this.id,
    required this.name,
    required this.category,
    required this.icon,
  });
}

/// Available instruments (hardcoded for now, can be loaded from audio engine later)
const List<Instrument> availableInstruments = [
  // Keyboards
  Instrument(
    id: 'piano',
    name: 'Piano',
    category: 'Keyboard',
    icon: Icons.piano,
  ),
  Instrument(
    id: 'electric_piano',
    name: 'Electric Piano',
    category: 'Keyboard',
    icon: Icons.piano,
  ),
  // Editable Synthesizer (user can customize parameters)
  Instrument(
    id: 'synthesizer',
    name: 'Synthesizer',
    category: 'Synthesizer',
    icon: Icons.graphic_eq,
  ),
  Instrument(
    id: 'synth_lead',
    name: 'Synth Lead',
    category: 'Synthesizer',
    icon: Icons.music_note,
  ),
  Instrument(
    id: 'synth_pad',
    name: 'Synth Pad',
    category: 'Synthesizer',
    icon: Icons.music_note,
  ),

  // Bass
  Instrument(
    id: 'synth_bass',
    name: 'Synth Bass',
    category: 'Bass',
    icon: Icons.speaker,
  ),
  Instrument(
    id: 'electric_bass',
    name: 'Electric Bass',
    category: 'Bass',
    icon: Icons.speaker,
  ),

  // Strings
  Instrument(
    id: 'strings',
    name: 'Strings',
    category: 'Orchestral',
    icon: Icons.queue_music,
  ),
  Instrument(
    id: 'violin',
    name: 'Violin',
    category: 'Orchestral',
    icon: Icons.queue_music,
  ),

  // Brass
  Instrument(
    id: 'trumpet',
    name: 'Trumpet',
    category: 'Brass',
    icon: Icons.music_note_outlined,
  ),
  Instrument(
    id: 'trombone',
    name: 'Trombone',
    category: 'Brass',
    icon: Icons.music_note_outlined,
  ),

  // Drums (for completeness)
  Instrument(
    id: 'drums',
    name: 'Drums',
    category: 'Percussion',
    icon: Icons.album,
  ),
];

/// Shows instrument browser dialog and returns selected instrument
Future<Instrument?> showInstrumentBrowser(BuildContext context) async {
  return await showDialog<Instrument>(
    context: context,
    builder: (context) => const InstrumentBrowserDialog(),
  );
}

/// Instrument browser dialog widget
class InstrumentBrowserDialog extends StatefulWidget {
  const InstrumentBrowserDialog({super.key});

  @override
  State<InstrumentBrowserDialog> createState() => _InstrumentBrowserDialogState();
}

class _InstrumentBrowserDialogState extends State<InstrumentBrowserDialog> {
  String? _selectedCategory;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    // Get unique categories
    final categories = availableInstruments
        .map((i) => i.category)
        .toSet()
        .toList()
      ..sort();

    // Filter instruments based on category and search
    final filteredInstruments = availableInstruments.where((instrument) {
      final matchesCategory =
          _selectedCategory == null || instrument.category == _selectedCategory;
      final matchesSearch = _searchQuery.isEmpty ||
          instrument.name.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();

    return Dialog(
      backgroundColor: const Color(0xFF656565),
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  Icons.library_music,
                  color: Color(0xFFA0A0A0),
                  size: 24,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Instrument Browser',
                  style: TextStyle(
                    color: Color(0xFFA0A0A0),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  color: const Color(0xFFA0A0A0),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Search bar
            TextField(
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search instruments...',
                hintStyle: const TextStyle(color: Color(0xFF808080)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF808080)),
                filled: true,
                fillColor: const Color(0xFF505050),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              style: const TextStyle(color: Color(0xFFA0A0A0)),
            ),

            const SizedBox(height: 16),

            // Category filter chips
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildCategoryChip('All', null),
                  ...categories.map((category) => _buildCategoryChip(category, category)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Instruments list
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF505050),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: filteredInstruments.isEmpty
                    ? Center(
                        child: Text(
                          'No instruments found',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredInstruments.length,
                        itemBuilder: (context, index) {
                          final instrument = filteredInstruments[index];
                          return _buildInstrumentTile(instrument);
                        },
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // Footer info
            Text(
              'Double-click an instrument to select it',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String label, String? category) {
    final isSelected = _selectedCategory == category;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedCategory = selected ? category : null;
          });
        },
        backgroundColor: const Color(0xFF606060),
        selectedColor: const Color(0xFF4CAF50),
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFFA0A0A0),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        checkmarkColor: Colors.white,
      ),
    );
  }

  Widget _buildInstrumentTile(Instrument instrument) {
    return Draggable<Instrument>(
      data: instrument,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                instrument.icon,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  instrument.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Color(0xFF606060),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // Instrument icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  instrument.icon,
                  color: const Color(0xFF4CAF50),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      instrument.name,
                      style: const TextStyle(
                        color: Color(0xFFA0A0A0),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      instrument.category,
                      style: const TextStyle(
                        color: Color(0xFF808080),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF808080),
                size: 20,
              ),
            ],
          ),
        ),
      ),
      child: InkWell(
        onTap: () {
          // Single click - select (could show preview)
        },
        onDoubleTap: () {
          // Double click - choose and close
          Navigator.of(context).pop(instrument);
        },
        child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Color(0xFF606060),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            // Instrument icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                instrument.icon,
                color: const Color(0xFF4CAF50),
                size: 24,
              ),
            ),

            const SizedBox(width: 16),

            // Instrument info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    instrument.name,
                    style: const TextStyle(
                      color: Color(0xFFA0A0A0),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    instrument.category,
                    style: const TextStyle(
                      color: Color(0xFF808080),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Arrow icon
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF808080),
              size: 20,
            ),
          ],
        ),
      ),
      ),
    );
  }
}
