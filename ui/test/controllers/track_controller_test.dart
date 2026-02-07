import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/controllers/track_controller.dart';
import 'package:boojy_audio/models/instrument_data.dart';

void main() {
  late TrackController controller;

  setUp(() {
    controller = TrackController();
  });

  tearDown(() {
    controller.dispose();
  });

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------
  group('Selection', () {
    test('selectedTrackId is null initially', () {
      expect(controller.selectedTrackId, isNull);
    });

    test('selectedTrackIds is empty initially', () {
      expect(controller.selectedTrackIds, isEmpty);
    });

    test('single select sets selectedTrackId and selectedTrackIds', () {
      controller.selectTrack(1);
      expect(controller.selectedTrackId, 1);
      expect(controller.selectedTrackIds, {1});
    });

    test('single select replaces previous selection', () {
      controller.selectTrack(1);
      controller.selectTrack(2);
      expect(controller.selectedTrackId, 2);
      expect(controller.selectedTrackIds, {2});
    });

    test('selecting null clears selection', () {
      controller.selectTrack(1);
      controller.selectTrack(null);
      expect(controller.selectedTrackId, isNull);
      expect(controller.selectedTrackIds, isEmpty);
    });

    test('shift-click adds to multi-selection', () {
      controller.selectTrack(1);
      controller.selectTrack(2, isShiftHeld: true);
      expect(controller.selectedTrackIds, {1, 2});
      // Primary stays as 1 since it was already set
      expect(controller.selectedTrackId, 1);
    });

    test('shift-click on already selected track removes it', () {
      controller.selectTrack(1);
      controller.selectTrack(2, isShiftHeld: true);
      controller.selectTrack(1, isShiftHeld: true);
      expect(controller.selectedTrackIds, {2});
      // Primary updates to next available
      expect(controller.selectedTrackId, 2);
    });

    test('shift-click removing last track sets primary to null', () {
      controller.selectTrack(1);
      controller.selectTrack(1, isShiftHeld: true);
      expect(controller.selectedTrackIds, isEmpty);
      expect(controller.selectedTrackId, isNull);
    });

    test('shift-click with no prior selection sets primary', () {
      controller.selectTrack(3, isShiftHeld: true);
      expect(controller.selectedTrackId, 3);
      expect(controller.selectedTrackIds, {3});
    });

    test('single select after multi-select clears multi-selection', () {
      controller.selectTrack(1);
      controller.selectTrack(2, isShiftHeld: true);
      controller.selectTrack(3, isShiftHeld: true);
      expect(controller.selectedTrackIds, {1, 2, 3});

      controller.selectTrack(5);
      expect(controller.selectedTrackId, 5);
      expect(controller.selectedTrackIds, {5});
    });

    test('selectedTrackIds getter returns unmodifiable set', () {
      controller.selectTrack(1);
      final ids = controller.selectedTrackIds;
      expect(() => ids.add(999), throwsUnsupportedError);
    });
  });

  // ---------------------------------------------------------------------------
  // Clip Heights
  // ---------------------------------------------------------------------------
  group('Clip Heights', () {
    test('getClipHeight returns default when not set', () {
      expect(controller.getClipHeight(1), TrackController.defaultClipHeight);
    });

    test('setClipHeight then getClipHeight returns stored value', () {
      controller.setClipHeight(1, 150.0);
      expect(controller.getClipHeight(1), 150.0);
    });

    test('setClipHeight clamps below minimum', () {
      controller.setClipHeight(1, 10.0);
      expect(controller.getClipHeight(1), TrackController.minClipHeight);
    });

    test('setClipHeight clamps above maximum', () {
      controller.setClipHeight(1, 999.0);
      expect(controller.getClipHeight(1), TrackController.maxClipHeight);
    });

    test('setClipHeight at exactly min is accepted', () {
      controller.setClipHeight(1, TrackController.minClipHeight);
      expect(controller.getClipHeight(1), TrackController.minClipHeight);
    });

    test('setClipHeight at exactly max is accepted', () {
      controller.setClipHeight(1, TrackController.maxClipHeight);
      expect(controller.getClipHeight(1), TrackController.maxClipHeight);
    });

    test('different tracks have independent heights', () {
      controller.setClipHeight(1, 80.0);
      controller.setClipHeight(2, 200.0);
      expect(controller.getClipHeight(1), 80.0);
      expect(controller.getClipHeight(2), 200.0);
    });
  });

  // ---------------------------------------------------------------------------
  // Automation Heights
  // ---------------------------------------------------------------------------
  group('Automation Heights', () {
    test('getAutomationHeight returns default when not set', () {
      expect(
        controller.getAutomationHeight(1),
        TrackController.defaultAutomationHeight,
      );
    });

    test('setAutomationHeight then getAutomationHeight returns stored value',
        () {
      controller.setAutomationHeight(1, 100.0);
      expect(controller.getAutomationHeight(1), 100.0);
    });

    test('setAutomationHeight clamps below minimum', () {
      controller.setAutomationHeight(1, 5.0);
      expect(
        controller.getAutomationHeight(1),
        TrackController.minAutomationHeight,
      );
    });

    test('setAutomationHeight clamps above maximum', () {
      controller.setAutomationHeight(1, 500.0);
      expect(
        controller.getAutomationHeight(1),
        TrackController.maxAutomationHeight,
      );
    });

    test('different tracks have independent automation heights', () {
      controller.setAutomationHeight(1, 50.0);
      controller.setAutomationHeight(2, 150.0);
      expect(controller.getAutomationHeight(1), 50.0);
      expect(controller.getAutomationHeight(2), 150.0);
    });
  });

  // ---------------------------------------------------------------------------
  // Master Track Height
  // ---------------------------------------------------------------------------
  group('Master Track Height', () {
    test('masterTrackHeight has default value of 50', () {
      expect(controller.masterTrackHeight, 50.0);
    });

    test('setMasterTrackHeight updates the value', () {
      controller.setMasterTrackHeight(120.0);
      expect(controller.masterTrackHeight, 120.0);
    });

    test('setMasterTrackHeight clamps below minClipHeight', () {
      controller.setMasterTrackHeight(5.0);
      expect(controller.masterTrackHeight, TrackController.minClipHeight);
    });

    test('setMasterTrackHeight clamps above maxClipHeight', () {
      controller.setMasterTrackHeight(999.0);
      expect(controller.masterTrackHeight, TrackController.maxClipHeight);
    });
  });

  // ---------------------------------------------------------------------------
  // Colors
  // ---------------------------------------------------------------------------
  group('Colors', () {
    test('setTrackColor stores override', () {
      const red = Color(0xFFFF0000);
      controller.setTrackColor(1, red);
      expect(controller.getTrackColor(1, 'Track', 'audio'), red);
    });

    test('color override takes precedence over auto-detection', () {
      const custom = Color(0xFF123456);
      controller.setTrackColor(1, custom);
      // Even with a name that would auto-detect as drums, override wins
      expect(controller.getTrackColor(1, 'Drum Kit', 'audio'), custom);
    });

    test('clearTrackColorOverride reverts to auto-detection', () {
      const custom = Color(0xFF123456);
      controller.setTrackColor(1, custom);
      controller.clearTrackColorOverride(1);
      // After clearing, auto-detection kicks in; result should differ from custom
      final autoColor = controller.getTrackColor(1, 'Track', 'audio');
      expect(autoColor, isNot(equals(custom)));
    });

    test('getTrackColor without override returns auto-detected color', () {
      // 'audio' type with no keywords matches audio category (grey)
      final color = controller.getTrackColor(1, 'Track', 'audio');
      expect(color, isA<Color>());
    });

    test('different tracks can have different overrides', () {
      const red = Color(0xFFFF0000);
      const blue = Color(0xFF0000FF);
      controller.setTrackColor(1, red);
      controller.setTrackColor(2, blue);
      expect(controller.getTrackColor(1, 'Track', 'audio'), red);
      expect(controller.getTrackColor(2, 'Track', 'audio'), blue);
    });
  });

  // ---------------------------------------------------------------------------
  // Icons
  // ---------------------------------------------------------------------------
  group('Icons', () {
    test('getTrackIcon returns null when not set', () {
      expect(controller.getTrackIcon(1), isNull);
    });

    test('setTrackIcon stores the icon', () {
      controller.setTrackIcon(1, 'guitar');
      expect(controller.getTrackIcon(1), 'guitar');
    });

    test('clearTrackIcon removes the override', () {
      controller.setTrackIcon(1, 'guitar');
      controller.clearTrackIcon(1);
      expect(controller.getTrackIcon(1), isNull);
    });

    test('different tracks can have different icons', () {
      controller.setTrackIcon(1, 'guitar');
      controller.setTrackIcon(2, 'piano');
      expect(controller.getTrackIcon(1), 'guitar');
      expect(controller.getTrackIcon(2), 'piano');
    });

    test('setTrackIcon overwrites previous icon', () {
      controller.setTrackIcon(1, 'guitar');
      controller.setTrackIcon(1, 'drums');
      expect(controller.getTrackIcon(1), 'drums');
    });
  });

  // ---------------------------------------------------------------------------
  // Track Name State
  // ---------------------------------------------------------------------------
  group('Track Name State', () {
    test('isTrackNameUserEdited defaults to false', () {
      expect(controller.isTrackNameUserEdited(1), isFalse);
    });

    test('markTrackNameUserEdited sets to true', () {
      controller.markTrackNameUserEdited(1, edited: true);
      expect(controller.isTrackNameUserEdited(1), isTrue);
    });

    test('markTrackNameUserEdited can reset to false', () {
      controller.markTrackNameUserEdited(1, edited: true);
      controller.markTrackNameUserEdited(1, edited: false);
      expect(controller.isTrackNameUserEdited(1), isFalse);
    });

    test('initTrackNameState sets state to false (auto-generated)', () {
      controller.markTrackNameUserEdited(1, edited: true);
      controller.initTrackNameState(1);
      expect(controller.isTrackNameUserEdited(1), isFalse);
    });

    test('different tracks have independent name states', () {
      controller.markTrackNameUserEdited(1, edited: true);
      controller.markTrackNameUserEdited(2, edited: false);
      expect(controller.isTrackNameUserEdited(1), isTrue);
      expect(controller.isTrackNameUserEdited(2), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Track Ordering
  // ---------------------------------------------------------------------------
  group('Track Ordering', () {
    test('trackOrder is empty initially', () {
      expect(controller.trackOrder, isEmpty);
    });

    test('syncTrackOrder sets initial order', () {
      controller.syncTrackOrder([3, 1, 2]);
      expect(controller.trackOrder, [3, 1, 2]);
    });

    test('syncTrackOrder preserves existing order for known tracks', () {
      controller.syncTrackOrder([1, 2, 3]);
      // Re-sync with same IDs (possibly different order from engine)
      // Existing order [1,2,3] is preserved
      controller.syncTrackOrder([3, 2, 1]);
      expect(controller.trackOrder, [1, 2, 3]);
    });

    test('syncTrackOrder appends new tracks at end', () {
      controller.syncTrackOrder([1, 2]);
      controller.syncTrackOrder([1, 2, 3]);
      expect(controller.trackOrder, [1, 2, 3]);
    });

    test('syncTrackOrder removes tracks no longer present', () {
      controller.syncTrackOrder([1, 2, 3]);
      controller.syncTrackOrder([1, 3]);
      expect(controller.trackOrder, [1, 3]);
    });

    test('reorderTrack moves track to new position', () {
      controller.syncTrackOrder([1, 2, 3, 4]);
      controller.reorderTrack(0, 2);
      // Remove index 0 (track 1), insert at index 2: [2,3,1,4]
      expect(controller.trackOrder, [2, 3, 1, 4]);
    });

    test('reorderTrack with out of bounds oldIndex is no-op', () {
      controller.syncTrackOrder([1, 2, 3]);
      controller.reorderTrack(-1, 1);
      expect(controller.trackOrder, [1, 2, 3]);
      controller.reorderTrack(5, 1);
      expect(controller.trackOrder, [1, 2, 3]);
    });

    test('reorderTrack with out of bounds newIndex is no-op', () {
      controller.syncTrackOrder([1, 2, 3]);
      controller.reorderTrack(0, -1);
      expect(controller.trackOrder, [1, 2, 3]);
      controller.reorderTrack(0, 5);
      expect(controller.trackOrder, [1, 2, 3]);
    });

    test('getOrderedTrackIds returns a copy of the order', () {
      controller.syncTrackOrder([1, 2, 3]);
      final ordered = controller.getOrderedTrackIds();
      expect(ordered, [1, 2, 3]);
      // Mutating the returned list does not affect internal state
      ordered.add(99);
      expect(controller.getOrderedTrackIds(), [1, 2, 3]);
    });

    test('trackOrder getter returns unmodifiable list', () {
      controller.syncTrackOrder([1, 2]);
      expect(
        () => controller.trackOrder.add(99),
        throwsUnsupportedError,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Instruments
  // ---------------------------------------------------------------------------
  group('Instruments', () {
    InstrumentData makeInstrument(int trackId) {
      return InstrumentData(
        trackId: trackId,
        type: 'synthesizer',
        parameters: {'osc1_type': 'saw'},
      );
    }

    test('getTrackInstrument returns null when not set', () {
      expect(controller.getTrackInstrument(1), isNull);
    });

    test('hasInstrument returns false when not set', () {
      expect(controller.hasInstrument(1), isFalse);
    });

    test('setTrackInstrument then getTrackInstrument returns it', () {
      final instrument = makeInstrument(1);
      controller.setTrackInstrument(1, instrument);
      expect(controller.getTrackInstrument(1), instrument);
    });

    test('hasInstrument returns true after setting', () {
      controller.setTrackInstrument(1, makeInstrument(1));
      expect(controller.hasInstrument(1), isTrue);
    });

    test('removeTrackInstrument removes the instrument', () {
      controller.setTrackInstrument(1, makeInstrument(1));
      controller.removeTrackInstrument(1);
      expect(controller.getTrackInstrument(1), isNull);
      expect(controller.hasInstrument(1), isFalse);
    });

    test('removeTrackInstrument on non-existent track is safe', () {
      // Should not throw
      controller.removeTrackInstrument(999);
      expect(controller.hasInstrument(999), isFalse);
    });

    test('different tracks can have different instruments', () {
      final inst1 = makeInstrument(1);
      final inst2 = InstrumentData(
        trackId: 2,
        type: 'vst3',
        parameters: {},
        pluginName: 'Diva',
      );
      controller.setTrackInstrument(1, inst1);
      controller.setTrackInstrument(2, inst2);
      expect(controller.getTrackInstrument(1)?.type, 'synthesizer');
      expect(controller.getTrackInstrument(2)?.type, 'vst3');
    });
  });

  // ---------------------------------------------------------------------------
  // onTrackDeleted
  // ---------------------------------------------------------------------------
  group('onTrackDeleted', () {
    test('removes clip height for deleted track', () {
      controller.setClipHeight(1, 200.0);
      controller.onTrackDeleted(1);
      expect(controller.getClipHeight(1), TrackController.defaultClipHeight);
    });

    test('removes automation height for deleted track', () {
      controller.setAutomationHeight(1, 100.0);
      controller.onTrackDeleted(1);
      expect(
        controller.getAutomationHeight(1),
        TrackController.defaultAutomationHeight,
      );
    });

    test('removes color override for deleted track', () {
      const custom = Color(0xFF123456);
      controller.setTrackColor(1, custom);
      controller.onTrackDeleted(1);
      // After deletion, auto-detection should apply (not the custom color)
      expect(controller.getTrackColor(1, 'Track', 'audio'), isNot(custom));
    });

    test('removes instrument for deleted track', () {
      controller.setTrackInstrument(
        1,
        InstrumentData(
          trackId: 1,
          type: 'synthesizer',
          parameters: {},
        ),
      );
      controller.onTrackDeleted(1);
      expect(controller.hasInstrument(1), isFalse);
    });

    test('removes track name user-edited state for deleted track', () {
      controller.markTrackNameUserEdited(1, edited: true);
      controller.onTrackDeleted(1);
      // Defaults to false for unknown track
      expect(controller.isTrackNameUserEdited(1), isFalse);
    });

    test('removes deleted track from selectedTrackIds', () {
      controller.selectTrack(1);
      controller.selectTrack(2, isShiftHeld: true);
      controller.onTrackDeleted(1);
      expect(controller.selectedTrackIds, {2});
    });

    test('clears selectedTrackId when deleted track was primary', () {
      controller.selectTrack(1);
      controller.onTrackDeleted(1);
      expect(controller.selectedTrackId, isNull);
      expect(controller.selectedTrackIds, isEmpty);
    });

    test(
        'updates selectedTrackId to next available when primary is deleted '
        'and others remain', () {
      controller.selectTrack(1);
      controller.selectTrack(2, isShiftHeld: true);
      controller.selectTrack(3, isShiftHeld: true);
      controller.onTrackDeleted(1);
      expect(controller.selectedTrackIds, {2, 3});
      expect(controller.selectedTrackId, 2);
    });

    test('does not affect other tracks', () {
      controller.setClipHeight(1, 200.0);
      controller.setClipHeight(2, 300.0);
      controller.onTrackDeleted(1);
      expect(controller.getClipHeight(2), 300.0);
    });
  });

  // ---------------------------------------------------------------------------
  // onTrackDuplicated
  // ---------------------------------------------------------------------------
  group('onTrackDuplicated', () {
    test('copies instrument from source to new track', () {
      final instrument = InstrumentData(
        trackId: 1,
        type: 'synthesizer',
        parameters: {'osc1_type': 'saw', 'osc1_level': 0.8},
      );
      controller.setTrackInstrument(1, instrument);
      controller.onTrackDuplicated(1, 2);

      final copied = controller.getTrackInstrument(2);
      expect(copied, isNotNull);
      expect(copied!.trackId, 2);
      expect(copied.type, 'synthesizer');
      expect(copied.parameters['osc1_type'], 'saw');
      expect(copied.parameters['osc1_level'], 0.8);
    });

    test('copies clip height from source to new track', () {
      controller.setClipHeight(1, 250.0);
      controller.onTrackDuplicated(1, 2);
      expect(controller.getClipHeight(2), 250.0);
    });

    test('copies automation height from source to new track', () {
      controller.setAutomationHeight(1, 120.0);
      controller.onTrackDuplicated(1, 2);
      expect(controller.getAutomationHeight(2), 120.0);
    });

    test('copies color override from source to new track', () {
      const custom = Color(0xFFABCDEF);
      controller.setTrackColor(1, custom);
      controller.onTrackDuplicated(1, 2);
      expect(controller.getTrackColor(2, 'Track', 'audio'), custom);
    });

    test('copies track name user-edited state from source to new track', () {
      controller.markTrackNameUserEdited(1, edited: true);
      controller.onTrackDuplicated(1, 2);
      expect(controller.isTrackNameUserEdited(2), isTrue);
    });

    test('does not copy when source has no custom state', () {
      controller.onTrackDuplicated(1, 2);
      // New track should have defaults
      expect(controller.getClipHeight(2), TrackController.defaultClipHeight);
      expect(controller.hasInstrument(2), isFalse);
      expect(controller.getTrackIcon(2), isNull);
    });

    test('source track state is preserved after duplication', () {
      controller.setClipHeight(1, 250.0);
      controller.setTrackColor(1, const Color(0xFFABCDEF));
      controller.setTrackInstrument(
        1,
        InstrumentData(trackId: 1, type: 'synthesizer', parameters: {}),
      );

      controller.onTrackDuplicated(1, 2);

      expect(controller.getClipHeight(1), 250.0);
      expect(
        controller.getTrackColor(1, 'Track', 'audio'),
        const Color(0xFFABCDEF),
      );
      expect(controller.hasInstrument(1), isTrue);
    });

    test('duplicated instrument has independent parameters', () {
      final instrument = InstrumentData(
        trackId: 1,
        type: 'synthesizer',
        parameters: {'cutoff': 0.5},
      );
      controller.setTrackInstrument(1, instrument);
      controller.onTrackDuplicated(1, 2);

      // Modify new track instrument -- replace via set
      final newInst = InstrumentData(
        trackId: 2,
        type: 'synthesizer',
        parameters: {'cutoff': 0.9},
      );
      controller.setTrackInstrument(2, newInst);

      // Source should be unaffected
      expect(
        controller.getTrackInstrument(1)!.parameters['cutoff'],
        0.5,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // clear
  // ---------------------------------------------------------------------------
  group('clear', () {
    test('resets selectedTrackId', () {
      controller.selectTrack(1);
      controller.clear();
      expect(controller.selectedTrackId, isNull);
    });

    test('resets selectedTrackIds', () {
      controller.selectTrack(1);
      controller.selectTrack(2, isShiftHeld: true);
      controller.clear();
      expect(controller.selectedTrackIds, isEmpty);
    });

    test('resets clip heights', () {
      controller.setClipHeight(1, 200.0);
      controller.clear();
      expect(controller.getClipHeight(1), TrackController.defaultClipHeight);
    });

    test('resets automation heights', () {
      controller.setAutomationHeight(1, 100.0);
      controller.clear();
      expect(
        controller.getAutomationHeight(1),
        TrackController.defaultAutomationHeight,
      );
    });

    test('resets color overrides', () {
      const custom = Color(0xFFFF0000);
      controller.setTrackColor(1, custom);
      controller.clear();
      expect(controller.getTrackColor(1, 'Track', 'audio'), isNot(custom));
    });

    test('resets instruments', () {
      controller.setTrackInstrument(
        1,
        InstrumentData(trackId: 1, type: 'synthesizer', parameters: {}),
      );
      controller.clear();
      expect(controller.hasInstrument(1), isFalse);
    });

    test('resets track name user-edited state', () {
      controller.markTrackNameUserEdited(1, edited: true);
      controller.clear();
      expect(controller.isTrackNameUserEdited(1), isFalse);
    });

    test('resets track order', () {
      controller.syncTrackOrder([1, 2, 3]);
      controller.clear();
      expect(controller.trackOrder, isEmpty);
    });

    test('resets master track height to default', () {
      controller.setMasterTrackHeight(200.0);
      controller.clear();
      expect(controller.masterTrackHeight, 50.0);
    });
  });

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------
  group('Notifications', () {
    test('selectTrack notifies listeners', () {
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.selectTrack(1);
      expect(callCount, 1);
    });

    test('selectTrack(null) notifies listeners', () {
      int callCount = 0;
      controller.selectTrack(1);
      controller.addListener(() => callCount++);
      controller.selectTrack(null);
      expect(callCount, 1);
    });

    test('setClipHeight notifies listeners', () {
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.setClipHeight(1, 150.0);
      expect(callCount, 1);
    });

    test('setAutomationHeight notifies listeners', () {
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.setAutomationHeight(1, 80.0);
      expect(callCount, 1);
    });

    test('setMasterTrackHeight notifies listeners', () {
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.setMasterTrackHeight(100.0);
      expect(callCount, 1);
    });

    test('setTrackColor notifies listeners', () {
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.setTrackColor(1, const Color(0xFFFF0000));
      expect(callCount, 1);
    });

    test('clearTrackColorOverride notifies listeners', () {
      int callCount = 0;
      controller.setTrackColor(1, const Color(0xFFFF0000));
      controller.addListener(() => callCount++);
      controller.clearTrackColorOverride(1);
      expect(callCount, 1);
    });

    test('setTrackIcon notifies listeners', () {
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.setTrackIcon(1, 'guitar');
      expect(callCount, 1);
    });

    test('clearTrackIcon notifies listeners', () {
      int callCount = 0;
      controller.setTrackIcon(1, 'guitar');
      controller.addListener(() => callCount++);
      controller.clearTrackIcon(1);
      expect(callCount, 1);
    });

    test('markTrackNameUserEdited notifies listeners', () {
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.markTrackNameUserEdited(1, edited: true);
      expect(callCount, 1);
    });

    test('initTrackNameState does not notify listeners', () {
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.initTrackNameState(1);
      expect(callCount, 0);
    });

    test('syncTrackOrder does not notify listeners', () {
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.syncTrackOrder([1, 2, 3]);
      expect(callCount, 0);
    });

    test('reorderTrack notifies listeners', () {
      controller.syncTrackOrder([1, 2, 3]);
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.reorderTrack(0, 2);
      expect(callCount, 1);
    });

    test('reorderTrack out of bounds does not notify', () {
      controller.syncTrackOrder([1, 2, 3]);
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.reorderTrack(-1, 0);
      expect(callCount, 0);
    });

    test('setTrackInstrument notifies listeners', () {
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.setTrackInstrument(
        1,
        InstrumentData(trackId: 1, type: 'synthesizer', parameters: {}),
      );
      expect(callCount, 1);
    });

    test('removeTrackInstrument notifies listeners', () {
      int callCount = 0;
      controller.setTrackInstrument(
        1,
        InstrumentData(trackId: 1, type: 'synthesizer', parameters: {}),
      );
      controller.addListener(() => callCount++);
      controller.removeTrackInstrument(1);
      expect(callCount, 1);
    });

    test('onTrackDeleted notifies listeners', () {
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.onTrackDeleted(1);
      expect(callCount, 1);
    });

    test('onTrackDuplicated notifies listeners', () {
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.onTrackDuplicated(1, 2);
      expect(callCount, 1);
    });

    test('clear notifies listeners', () {
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.clear();
      expect(callCount, 1);
    });

    test('multiple mutations fire multiple notifications', () {
      int callCount = 0;
      controller.addListener(() => callCount++);
      controller.selectTrack(1);
      controller.setClipHeight(1, 200.0);
      controller.setTrackColor(1, const Color(0xFFFF0000));
      expect(callCount, 3);
    });
  });
}
