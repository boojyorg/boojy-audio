import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/state/ui_layout_state.dart';

void main() {
  // ──────────────────────────────────────────────
  // SnapValue enum
  // ──────────────────────────────────────────────

  group('SnapValue', () {
    test('displayName returns correct strings', () {
      expect(SnapValue.off.displayName, 'Off');
      expect(SnapValue.bar.displayName, 'Bar');
      expect(SnapValue.beat.displayName, 'Beat');
      expect(SnapValue.half.displayName, '1/2');
      expect(SnapValue.quarter.displayName, '1/4');
    });

    test('beatsResolution returns correct values', () {
      expect(SnapValue.off.beatsResolution, 0.0);
      expect(SnapValue.bar.beatsResolution, 4.0);
      expect(SnapValue.beat.beatsResolution, 1.0);
      expect(SnapValue.half.beatsResolution, 0.5);
      expect(SnapValue.quarter.beatsResolution, 0.25);
    });
  });

  // ──────────────────────────────────────────────
  // UILayoutState
  // ──────────────────────────────────────────────

  group('UILayoutState', () {
    late UILayoutState layout;

    setUp(() {
      layout = UILayoutState();
    });

    tearDown(() {
      layout.dispose();
    });

    // ── Initial state ──────────────────────────

    group('initial state', () {
      test('has correct default panel sizes', () {
        expect(layout.mixerPanelWidth, 380.0);
        expect(layout.editorPanelHeight, 250.0);
        expect(layout.libraryLeftColumnWidth, 130.0);
        expect(layout.libraryRightColumnWidth, 170.0);
      });

      test('library is open by default', () {
        expect(layout.isLibraryPanelCollapsed, isFalse);
      });

      test('mixer is visible by default', () {
        expect(layout.isMixerVisible, isTrue);
      });

      test('editor is visible by default', () {
        expect(layout.isEditorPanelVisible, isTrue);
      });

      test('virtual piano is disabled by default', () {
        expect(layout.isVirtualPianoVisible, isFalse);
        expect(layout.isVirtualPianoEnabled, isFalse);
      });

      test('arrangement snap defaults to bar', () {
        expect(layout.arrangementSnap, SnapValue.bar);
      });

      test('loop playback enabled by default', () {
        expect(layout.loopPlaybackEnabled, isTrue);
        expect(layout.loopStartBeats, 0.0);
        expect(layout.loopEndBeats, 4.0);
        expect(layout.loopDurationBeats, 4.0);
        expect(layout.loopAutoFollow, isTrue);
      });

      test('punch in/out disabled by default', () {
        expect(layout.punchInEnabled, isFalse);
        expect(layout.punchOutEnabled, isFalse);
      });
    });

    // ── Library panel ──────────────────────────

    group('library panel', () {
      test('libraryPanelWidth is left + divider + right', () {
        // 130 + 8 + 170 = 308
        expect(
          layout.libraryPanelWidth,
          layout.libraryLeftColumnWidth +
              UILayoutState.libraryDividerWidth +
              layout.libraryRightColumnWidth,
        );
        expect(layout.libraryPanelWidth, 308.0);
      });

      test('libraryLeftColumnWidth clamps to min', () {
        layout.libraryLeftColumnWidth = 10.0;
        expect(layout.libraryLeftColumnWidth, UILayoutState.libraryLeftColumnMin);
      });

      test('libraryLeftColumnWidth clamps to max', () {
        layout.libraryLeftColumnWidth = 9999.0;
        expect(layout.libraryLeftColumnWidth, UILayoutState.libraryLeftColumnMax);
      });

      test('libraryRightColumnWidth clamps to min', () {
        layout.libraryRightColumnWidth = 10.0;
        expect(layout.libraryRightColumnWidth, UILayoutState.libraryRightColumnMin);
      });

      test('libraryRightColumnWidth clamps to max', () {
        layout.libraryRightColumnWidth = 9999.0;
        expect(layout.libraryRightColumnWidth, UILayoutState.libraryRightColumnMax);
      });

      test('toggleLibraryPanel collapses when open', () {
        layout.toggleLibraryPanel();
        expect(layout.isLibraryPanelCollapsed, isTrue);
      });

      test('toggleLibraryPanel expands when collapsed', () {
        layout.toggleLibraryPanel(); // collapse
        layout.toggleLibraryPanel(); // expand
        expect(layout.isLibraryPanelCollapsed, isFalse);
      });

      test('collapseLibrary sets collapsed state', () {
        layout.collapseLibrary();
        expect(layout.isLibraryPanelCollapsed, isTrue);
      });

      test('collapseLibrary is idempotent', () {
        layout.collapseLibrary();
        layout.collapseLibrary();
        expect(layout.isLibraryPanelCollapsed, isTrue);
      });

      test('expandLibrary restores saved column widths', () {
        layout.libraryLeftColumnWidth = 200.0;
        layout.libraryRightColumnWidth = 300.0;
        layout.collapseLibrary();

        // Modify widths while collapsed (shouldn't matter)
        layout.expandLibrary();
        expect(layout.libraryLeftColumnWidth, 200.0);
        expect(layout.libraryRightColumnWidth, 300.0);
      });

      test('resizeLeftColumn adjusts left width with clamping', () {
        final initialLeft = layout.libraryLeftColumnWidth;
        layout.resizeLeftColumn(20.0);
        expect(layout.libraryLeftColumnWidth, initialLeft + 20.0);
      });

      test('resizeLeftColumn clamps at min', () {
        layout.resizeLeftColumn(-9999.0);
        expect(layout.libraryLeftColumnWidth, UILayoutState.libraryLeftColumnMin);
      });

      test('resizeLeftColumn clamps at max', () {
        layout.resizeLeftColumn(9999.0);
        expect(layout.libraryLeftColumnWidth, UILayoutState.libraryLeftColumnMax);
      });

      test('resizeRightColumn adjusts total width', () {
        final initialRight = layout.libraryRightColumnWidth;
        layout.resizeRightColumn(30.0);
        expect(layout.libraryRightColumnWidth, initialRight + 30.0);
      });

      test('resizeRightColumn clamps at max', () {
        layout.resizeRightColumn(9999.0);
        expect(layout.libraryRightColumnWidth, UILayoutState.libraryRightColumnMax);
      });

      test('resizeRightColumn collapses when dragged below threshold', () {
        // Drag well below right min - 50
        layout.resizeRightColumn(-9999.0);
        expect(layout.isLibraryPanelCollapsed, isTrue);
      });
    });

    // ── Mixer panel ────────────────────────────

    group('mixer panel', () {
      test('mixerPanelWidth setter clamps to min', () {
        layout.mixerPanelWidth = 10.0;
        expect(layout.mixerPanelWidth, UILayoutState.mixerMinWidth);
      });

      test('mixerPanelWidth setter clamps to hard max', () {
        layout.mixerPanelWidth = 9999.0;
        expect(layout.mixerPanelWidth, UILayoutState.mixerHardMax);
      });

      test('toggleMixer hides when visible', () {
        layout.toggleMixer();
        expect(layout.isMixerVisible, isFalse);
      });

      test('toggleMixer shows when hidden', () {
        layout.toggleMixer(); // hide
        layout.toggleMixer(); // show
        expect(layout.isMixerVisible, isTrue);
      });

      test('collapseMixer hides mixer', () {
        layout.collapseMixer();
        expect(layout.isMixerVisible, isFalse);
      });

      test('collapseMixer is idempotent', () {
        layout.collapseMixer();
        layout.collapseMixer();
        expect(layout.isMixerVisible, isFalse);
      });

      test('expandMixer restores saved width', () {
        layout.mixerPanelWidth = 400.0;
        layout.collapseMixer();
        layout.expandMixer();
        expect(layout.mixerPanelWidth, 400.0);
      });
    });

    // ── Editor panel ───────────────────────────

    group('editor panel', () {
      test('editorPanelHeight setter clamps to min', () {
        layout.editorPanelHeight = 10.0;
        expect(layout.editorPanelHeight, UILayoutState.editorMinHeight);
      });

      test('editorPanelHeight setter clamps to hard max', () {
        layout.editorPanelHeight = 9999.0;
        expect(layout.editorPanelHeight, UILayoutState.editorHardMax);
      });

      test('toggleEditor hides when visible', () {
        layout.toggleEditor();
        expect(layout.isEditorPanelVisible, isFalse);
      });

      test('toggleEditor shows when hidden', () {
        layout.toggleEditor(); // hide
        layout.toggleEditor(); // show
        expect(layout.isEditorPanelVisible, isTrue);
      });

      test('collapseEditor hides editor', () {
        layout.collapseEditor();
        expect(layout.isEditorPanelVisible, isFalse);
      });

      test('collapseEditor is idempotent', () {
        layout.collapseEditor();
        layout.collapseEditor();
        expect(layout.isEditorPanelVisible, isFalse);
      });

      test('expandEditor restores saved height', () {
        layout.editorPanelHeight = 400.0;
        layout.collapseEditor();
        layout.expandEditor();
        expect(layout.editorPanelHeight, 400.0);
      });
    });

    // ── Static helpers ─────────────────────────

    group('static helpers', () {
      test('getLibraryMaxWidth respects percentage cap', () {
        // Small window: percentage is limiting factor
        // 800 * 0.30 = 240, which is < libraryHardMax (600)
        expect(UILayoutState.getLibraryMaxWidth(800), 240.0);
      });

      test('getLibraryMaxWidth respects hard max', () {
        // Large window: hardMax limits
        // 3000 * 0.30 = 900, which is > libraryHardMax (600)
        expect(UILayoutState.getLibraryMaxWidth(3000), UILayoutState.libraryHardMax);
      });

      test('getMixerMaxWidth respects percentage cap', () {
        // 800 * 0.35 = 280, which is < mixerHardMax (500)
        expect(UILayoutState.getMixerMaxWidth(800), 280.0);
      });

      test('getMixerMaxWidth respects hard max', () {
        // 2000 * 0.35 = 700, > mixerHardMax (500)
        expect(UILayoutState.getMixerMaxWidth(2000), UILayoutState.mixerHardMax);
      });

      test('getEditorMaxHeight respects percentage cap', () {
        // 600 * 0.55 = 330, < editorHardMax (600)
        expect(UILayoutState.getEditorMaxHeight(600), 330.0);
      });

      test('getEditorMaxHeight respects hard max', () {
        // 2000 * 0.55 = 1100, > editorHardMax (600)
        expect(UILayoutState.getEditorMaxHeight(2000), UILayoutState.editorHardMax);
      });

      test('getLibraryDefaultWidth respects min on small windows', () {
        // Very small window: 100 * 0.15 = 15, below min 208
        expect(
          UILayoutState.getLibraryDefaultWidth(100),
          UILayoutState.libraryMinWidth,
        );
      });

      test('getLibraryDefaultWidth uses percentage on normal windows', () {
        // 1600 * 0.15 = 240, above min, below hardMax
        expect(UILayoutState.getLibraryDefaultWidth(1600), 240.0);
      });

      test('collapse thresholds are less than min widths', () {
        expect(
          UILayoutState.libraryCollapseThreshold,
          lessThan(UILayoutState.libraryMinWidth),
        );
        expect(
          UILayoutState.mixerCollapseThreshold,
          lessThan(UILayoutState.mixerMinWidth),
        );
        expect(
          UILayoutState.editorCollapseThreshold,
          lessThan(UILayoutState.editorMinHeight),
        );
      });
    });

    // ── Arrangement width helpers ──────────────

    group('arrangement width', () {
      test('getArrangementWidth subtracts visible panels', () {
        const windowWidth = 1600.0;
        final expected = windowWidth - layout.libraryPanelWidth - layout.mixerPanelWidth;
        expect(layout.getArrangementWidth(windowWidth), expected);
      });

      test('getArrangementWidth uses zero for collapsed library', () {
        layout.collapseLibrary();
        const windowWidth = 1600.0;
        final expected = windowWidth - 0.0 - layout.mixerPanelWidth;
        expect(layout.getArrangementWidth(windowWidth), expected);
      });

      test('getArrangementWidth uses zero for hidden mixer', () {
        layout.collapseMixer();
        const windowWidth = 1600.0;
        final expected = windowWidth - layout.libraryPanelWidth - 0.0;
        expect(layout.getArrangementWidth(windowWidth), expected);
      });

      test('canShowLibrary returns true when enough room', () {
        expect(layout.canShowLibrary(2000.0), isTrue);
      });

      test('canShowLibrary returns false when too narrow', () {
        // With mixer visible at 380, library at 308, need arrangement >= 200
        // So window must be >= 888. Use something smaller.
        expect(layout.canShowLibrary(400.0), isFalse);
      });

      test('canShowMixer returns true when enough room', () {
        expect(layout.canShowMixer(2000.0), isTrue);
      });

      test('canShowMixer returns false when too narrow', () {
        expect(layout.canShowMixer(400.0), isFalse);
      });
    });

    // ── Loop/punch state ───────────────────────

    group('loop and punch state', () {
      test('toggleLoopPlayback toggles state', () {
        expect(layout.loopPlaybackEnabled, isTrue);
        layout.toggleLoopPlayback();
        expect(layout.loopPlaybackEnabled, isFalse);
        layout.toggleLoopPlayback();
        expect(layout.loopPlaybackEnabled, isTrue);
      });

      test('setLoopRegion updates start and end', () {
        layout.setLoopRegion(8.0, 16.0);
        expect(layout.loopStartBeats, 8.0);
        expect(layout.loopEndBeats, 16.0);
        expect(layout.loopDurationBeats, 8.0);
      });

      test('setLoopRegion with manual disables auto-follow', () {
        expect(layout.loopAutoFollow, isTrue);
        layout.setLoopRegion(4.0, 12.0, manual: true);
        expect(layout.loopAutoFollow, isFalse);
        expect(layout.loopStartBeats, 4.0);
        expect(layout.loopEndBeats, 12.0);
      });

      test('setLoopRegion without manual keeps auto-follow', () {
        layout.setLoopRegion(4.0, 12.0);
        expect(layout.loopAutoFollow, isTrue);
      });

      test('resetLoopAutoFollow restores defaults', () {
        layout.setLoopRegion(10.0, 20.0, manual: true);
        layout.resetLoopAutoFollow();
        expect(layout.loopAutoFollow, isTrue);
        expect(layout.loopStartBeats, 0.0);
        expect(layout.loopEndBeats, 4.0);
      });

      test('togglePunchIn toggles state', () {
        expect(layout.punchInEnabled, isFalse);
        layout.togglePunchIn();
        expect(layout.punchInEnabled, isTrue);
        layout.togglePunchIn();
        expect(layout.punchInEnabled, isFalse);
      });

      test('togglePunchOut toggles state', () {
        expect(layout.punchOutEnabled, isFalse);
        layout.togglePunchOut();
        expect(layout.punchOutEnabled, isTrue);
        layout.togglePunchOut();
        expect(layout.punchOutEnabled, isFalse);
      });
    });

    // ── Listener notification ──────────────────

    group('listener notification', () {
      test('setting mixerPanelWidth notifies listeners', () {
        var notified = false;
        layout.addListener(() => notified = true);
        layout.mixerPanelWidth = 300.0;
        expect(notified, isTrue);
      });

      test('setting editorPanelHeight notifies listeners', () {
        var notified = false;
        layout.addListener(() => notified = true);
        layout.editorPanelHeight = 300.0;
        expect(notified, isTrue);
      });

      test('toggleLibraryPanel notifies listeners', () {
        var notified = false;
        layout.addListener(() => notified = true);
        layout.toggleLibraryPanel();
        expect(notified, isTrue);
      });

      test('toggleMixer notifies listeners', () {
        var notified = false;
        layout.addListener(() => notified = true);
        layout.toggleMixer();
        expect(notified, isTrue);
      });

      test('toggleEditor notifies listeners', () {
        var notified = false;
        layout.addListener(() => notified = true);
        layout.toggleEditor();
        expect(notified, isTrue);
      });

      test('setLoopRegion notifies listeners', () {
        var notified = false;
        layout.addListener(() => notified = true);
        layout.setLoopRegion(0.0, 8.0);
        expect(notified, isTrue);
      });

      test('toggleLoopPlayback notifies listeners', () {
        var notified = false;
        layout.addListener(() => notified = true);
        layout.toggleLoopPlayback();
        expect(notified, isTrue);
      });

      test('resizeLeftColumn notifies listeners', () {
        var notified = false;
        layout.addListener(() => notified = true);
        layout.resizeLeftColumn(10.0);
        expect(notified, isTrue);
      });

      test('arrangementSnap setter notifies listeners', () {
        var notified = false;
        layout.addListener(() => notified = true);
        layout.arrangementSnap = SnapValue.beat;
        expect(notified, isTrue);
      });
    });

    // ── Virtual piano ──────────────────────────

    group('virtual piano', () {
      test('toggleVirtualPiano enables and shows', () {
        layout.toggleVirtualPiano();
        expect(layout.isVirtualPianoEnabled, isTrue);
        expect(layout.isVirtualPianoVisible, isTrue);
      });

      test('toggleVirtualPiano disables and hides', () {
        layout.toggleVirtualPiano(); // enable
        layout.toggleVirtualPiano(); // disable
        expect(layout.isVirtualPianoEnabled, isFalse);
        expect(layout.isVirtualPianoVisible, isFalse);
      });

      test('closeEditorAndPiano hides everything', () {
        layout.toggleVirtualPiano(); // enable piano
        layout.closeEditorAndPiano();
        expect(layout.isEditorPanelVisible, isFalse);
        expect(layout.isVirtualPianoVisible, isFalse);
        expect(layout.isVirtualPianoEnabled, isFalse);
      });
    });

    // ── resetLayout ────────────────────────────

    group('resetLayout', () {
      test('resets all panels to defaults', () {
        // Change everything
        layout.libraryLeftColumnWidth = 200.0;
        layout.libraryRightColumnWidth = 300.0;
        layout.mixerPanelWidth = 450.0;
        layout.editorPanelHeight = 400.0;
        layout.collapseLibrary();
        layout.collapseMixer();
        layout.collapseEditor();

        layout.resetLayout();

        expect(layout.libraryLeftColumnWidth, UILayoutState.libraryLeftColumnDefault);
        expect(layout.libraryRightColumnWidth, UILayoutState.libraryRightColumnMin);
        expect(layout.mixerPanelWidth, 380.0);
        expect(layout.editorPanelHeight, 250.0);
        expect(layout.isLibraryPanelCollapsed, isFalse);
        expect(layout.isMixerVisible, isTrue);
        expect(layout.isEditorPanelVisible, isTrue);
      });

      test('resetLayout notifies listeners', () {
        var notified = false;
        layout.addListener(() => notified = true);
        layout.resetLayout();
        expect(notified, isTrue);
      });
    });

    // ── applyLayout / getCurrentLayout ─────────

    group('applyLayout and getCurrentLayout', () {
      test('getCurrentLayout captures current state', () {
        layout.mixerPanelWidth = 400.0;
        layout.editorPanelHeight = 300.0;
        layout.collapseLibrary();

        final data = layout.getCurrentLayout();
        expect(data.mixerWidth, 400.0);
        expect(data.bottomHeight, 300.0);
        expect(data.libraryCollapsed, isTrue);
        expect(data.mixerCollapsed, isFalse);
      });

      test('applyLayout restores panel sizes with clamping', () {
        final data = UILayoutData(
          libraryWidth: 350.0,
          mixerWidth: 420.0,
          bottomHeight: 280.0,
          libraryCollapsed: false,
          mixerCollapsed: true,
        );
        layout.applyLayout(data);

        expect(layout.mixerPanelWidth, 420.0);
        expect(layout.editorPanelHeight, 280.0);
        expect(layout.isLibraryPanelCollapsed, isFalse);
        expect(layout.isMixerVisible, isFalse); // mixerCollapsed = true
      });

      test('applyLayout clamps extreme values', () {
        final data = UILayoutData(
          libraryWidth: 9999.0,
          mixerWidth: 9999.0,
          bottomHeight: 9999.0,
          libraryCollapsed: false,
          mixerCollapsed: false,
        );
        layout.applyLayout(data);

        expect(layout.mixerPanelWidth, UILayoutState.mixerHardMax);
        expect(layout.editorPanelHeight, UILayoutState.editorHardMax);
      });
    });
  });
}
