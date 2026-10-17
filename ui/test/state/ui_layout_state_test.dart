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
        expect(layout.mixerPanelWidth, 280.0);
        expect(layout.editorPanelHeight, 250.0);
        expect(layout.libraryPanelWidth, 280.0);
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

      test('loop is off by default with bars 1-4 ready', () {
        expect(layout.loopPlaybackEnabled, isFalse);
        expect(layout.loopStartBeats, 0.0);
        expect(layout.loopEndBeats, 16.0);
        expect(layout.loopDurationBeats, 16.0);
      });
    });

    // ── Library panel ──────────────────────────

    group('library panel', () {
      test('libraryPanelWidth is left + divider + right', () {
        // 60 + 8 + 212 = 280
        expect(
          layout.libraryPanelWidth,
          layout.libraryLeftColumnWidth +
              UILayoutState.libraryDividerWidth +
              layout.libraryRightColumnWidth,
        );
        expect(layout.libraryPanelWidth, 280.0);
      });

      test('libraryLeftColumnWidth clamps to min', () {
        layout.libraryLeftColumnWidth = 10.0;
        expect(
          layout.libraryLeftColumnWidth,
          UILayoutState.libraryLeftColumnMin,
        );
      });

      test('libraryLeftColumnWidth clamps to max', () {
        layout.libraryLeftColumnWidth = 9999.0;
        expect(
          layout.libraryLeftColumnWidth,
          UILayoutState.libraryLeftColumnMax,
        );
      });

      test('libraryRightColumnWidth clamps to min', () {
        layout.libraryRightColumnWidth = 10.0;
        expect(
          layout.libraryRightColumnWidth,
          UILayoutState.libraryRightColumnMin,
        );
      });

      test('libraryRightColumnWidth clamps to max', () {
        layout.libraryRightColumnWidth = 9999.0;
        expect(
          layout.libraryRightColumnWidth,
          UILayoutState.libraryRightColumnMax,
        );
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
        expect(
          layout.libraryLeftColumnWidth,
          UILayoutState.libraryLeftColumnMin,
        );
      });

      test('resizeLeftColumn clamps at max', () {
        layout.resizeLeftColumn(9999.0);
        expect(
          layout.libraryLeftColumnWidth,
          UILayoutState.libraryLeftColumnMax,
        );
      });

      test('resizeRightColumn adjusts total width', () {
        final initialRight = layout.libraryRightColumnWidth;
        layout.resizeRightColumn(30.0);
        expect(layout.libraryRightColumnWidth, initialRight + 30.0);
      });

      test('resizeRightColumn clamps at max', () {
        layout.resizeRightColumn(9999.0);
        expect(
          layout.libraryRightColumnWidth,
          UILayoutState.libraryRightColumnMax,
        );
      });

      test('a widened old left column moves into the right column', () {
        // Saved by the two-column Library: left at its 250 max
        layout.restoreLibraryWidths(250.0, 92.0);
        expect(layout.libraryPanelWidth, 350.0); // same size as before
        layout.resizeRightColumn(-9999.0);
        expect(layout.libraryPanelWidth, UILayoutState.libraryMinWidth);
      });

      test('restored widths stay within the right column max', () {
        layout.restoreLibraryWidths(250.0, 400.0);
        expect(
          layout.libraryRightColumnWidth,
          UILayoutState.libraryRightColumnMax,
        );
      });

      test('resizeRightColumn stops at min and keeps the panel open', () {
        layout.resizeRightColumn(-9999.0);
        expect(layout.isLibraryPanelCollapsed, isFalse);
        expect(
          layout.libraryRightColumnWidth,
          UILayoutState.libraryRightColumnMin,
        );
      });
    });

    // ── Mixer panel ────────────────────────────

    group('mixer panel', () {
      test('mixerPanelWidth setter clamps to min', () {
        layout.mixerPanelWidth = 10.0;
        expect(layout.mixerPanelWidth, UILayoutState.mixerMinWidth);
      });

      test('mixerPanelWidth setter clamps to max', () {
        layout.mixerPanelWidth = 9999.0;
        expect(layout.mixerPanelWidth, UILayoutState.mixerMaxWidth);
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
      test('Library and Mixer share one size range', () {
        expect(UILayoutState.libraryMinWidth, UILayoutState.mixerMinWidth);
        // Library = left column + divider + right column
        const libraryChrome =
            UILayoutState.libraryLeftColumnDefault +
            UILayoutState.libraryDividerWidth;
        expect(
          libraryChrome + UILayoutState.libraryRightColumnMin,
          UILayoutState.sidePanelMinWidth,
        );
        expect(
          libraryChrome + UILayoutState.libraryRightColumnMax,
          UILayoutState.mixerMaxWidth,
        );
      });

      test('getEditorMaxHeight respects percentage cap', () {
        // 600 * 0.65 = 390, < editorHardMax (600)
        expect(UILayoutState.getEditorMaxHeight(600), 390.0);
      });

      test('getEditorMaxHeight respects hard max', () {
        // 2000 * 0.55 = 1100, > editorHardMax (600)
        expect(
          UILayoutState.getEditorMaxHeight(2000),
          UILayoutState.editorHardMax,
        );
      });
    });

    group('resetSizesToDefaults', () {
      test('Library and Mixer open at the same width; editor by window', () {
        final state = UILayoutState();
        state.resetSizesToDefaults(1600, 1000);

        expect(state.mixerPanelWidth, UILayoutState.sidePanelDefaultWidth);
        expect(state.libraryPanelWidth, UILayoutState.sidePanelDefaultWidth);
        // editor: 1000 * 0.32 = 320 (above min, below hardMax)
        expect(state.editorPanelHeight, closeTo(320.0, 0.01));
      });

      test(
        'overrides a previous oversized drag (consistency on new project)',
        () {
          final state = UILayoutState();
          // Simulate a project where the user dragged the editor very tall.
          state.editorPanelHeight = 800.0;
          state.mixerPanelWidth = 500.0;
          expect(state.editorPanelHeight, 800.0);

          state.resetSizesToDefaults(1600, 1000);

          // A new project no longer inherits the stray drag.
          expect(state.editorPanelHeight, closeTo(320.0, 0.01));
          expect(state.mixerPanelWidth, UILayoutState.sidePanelDefaultWidth);
        },
      );

      test('clamps to minimums on a tiny window', () {
        final state = UILayoutState();
        state.resetSizesToDefaults(400, 200);

        expect(
          state.editorPanelHeight,
          greaterThanOrEqualTo(UILayoutState.editorMinHeight),
        );
        expect(
          state.mixerPanelWidth,
          greaterThanOrEqualTo(UILayoutState.mixerMinWidth),
        );
        expect(
          state.libraryPanelWidth,
          greaterThanOrEqualTo(UILayoutState.libraryMinWidth),
        );
      });

      test('notifies listeners', () {
        final state = UILayoutState();
        var notified = false;
        state.addListener(() => notified = true);
        state.resetSizesToDefaults(1600, 1000);
        expect(notified, isTrue);
      });
    });

    // ── Fitting the side panels into the window ──

    group('displayed panel widths', () {
      // Timeline keeps 340 and each divider 4: 1108 leaves 760 for the panels
      const window = 1108.0;

      setUp(() {
        layout.restoreLibraryWidths(60.0, 412.0); // 480
        layout.mixerPanelWidth = 380.0;
      });

      test('chosen widths are drawn when they fit', () {
        final shown = layout.displayedPanelWidths(1920.0);
        expect(shown.library, 480.0);
        expect(shown.mixer, 380.0);
      });

      test('the wider panel gives way first, then both together', () {
        // 480 + 380 = 860, 100 too wide: the Library alone narrows
        var shown = layout.displayedPanelWidths(window);
        expect(shown.library, 380.0);
        expect(shown.mixer, 380.0);
        // 860 in 660: Library down to 380, then 80 more split evenly
        shown = layout.displayedPanelWidths(1008.0);
        expect(shown.library, 330.0);
        expect(shown.mixer, 330.0);
      });

      test('never narrower than the minimum, never hidden', () {
        final shown = layout.displayedPanelWidths(400.0);
        expect(shown.library, UILayoutState.sidePanelMinWidth);
        expect(shown.mixer, UILayoutState.sidePanelMinWidth);
        expect(layout.isLibraryPanelCollapsed, isFalse);
        expect(layout.isMixerVisible, isTrue);
      });

      test('the chosen widths come back when the window grows', () {
        layout.displayedPanelWidths(window);
        final shown = layout.displayedPanelWidths(1920.0);
        expect(shown.library, 480.0);
        expect(shown.mixer, 380.0);
      });

      test('a hidden panel takes no room', () {
        layout.collapseMixer();
        final shown = layout.displayedPanelWidths(704.0);
        expect(shown.mixer, 0.0);
        expect(shown.library, 360.0); // 704 - 340 timeline - 4 divider
      });

      test('a drag starts from the drawn widths', () {
        layout.keepDisplayedWidths(window);
        expect(layout.libraryPanelWidth, 380.0);
        expect(layout.mixerPanelWidth, 380.0);
      });

      test('a drag stops before squeezing the other panel', () {
        layout.keepDisplayedWidths(window);
        // 760 for the panels - 380 Mixer
        expect(layout.libraryDragMax(window), 380.0);
        layout.resizeRightColumn(
          9999.0,
          maxWidth: layout.libraryDragMax(window),
        );
        expect(layout.libraryPanelWidth, 380.0);
        expect(layout.displayedPanelWidths(window).mixer, 380.0);
        expect(layout.mixerDragMax(window), 380.0);
      });

      test('drag limits stay within the shared range', () {
        expect(layout.libraryDragMax(3000.0), UILayoutState.sidePanelMaxWidth);
        expect(layout.mixerDragMax(400.0), UILayoutState.sidePanelMinWidth);
      });
    });

    // ── Loop state ───────────────────────

    group('loop state', () {
      test('toggleLoopPlayback toggles state', () {
        expect(layout.loopPlaybackEnabled, isFalse);
        layout.toggleLoopPlayback();
        expect(layout.loopPlaybackEnabled, isTrue);
        layout.toggleLoopPlayback();
        expect(layout.loopPlaybackEnabled, isFalse);
      });

      test('setLoopRegion updates start and end', () {
        layout.setLoopRegion(8.0, 16.0);
        expect(layout.loopStartBeats, 8.0);
        expect(layout.loopEndBeats, 16.0);
        expect(layout.loopDurationBeats, 8.0);
      });

      test('turning loop on keeps the default region (bars 1-4)', () {
        layout.toggleLoopPlayback();
        expect(layout.loopPlaybackEnabled, isTrue);
        expect(layout.loopStartBeats, 0.0);
        expect(layout.loopEndBeats, 16.0);
      });

      test('resetLoop restores defaults: off, bars 1-4', () {
        layout.setLoopRegion(10.0, 20.0);
        layout.loopPlaybackEnabled = true;
        layout.resetLoop();
        expect(layout.loopPlaybackEnabled, isFalse);
        expect(layout.loopStartBeats, 0.0);
        expect(layout.loopEndBeats, 16.0);
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

        expect(
          layout.libraryLeftColumnWidth,
          UILayoutState.libraryLeftColumnDefault,
        );
        expect(
          layout.libraryRightColumnWidth,
          UILayoutState.sidePanelDefaultWidth -
              UILayoutState.libraryLeftColumnDefault -
              UILayoutState.libraryDividerWidth,
        );
        expect(layout.mixerPanelWidth, UILayoutState.sidePanelDefaultWidth);
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
        const data = UILayoutData(
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

      test('a project saved with a widened old left column can shrink', () {
        const data = UILayoutData(
          libraryWidth: 350.0,
          libraryLeftWidth: 250.0,
          mixerWidth: 420.0,
          bottomHeight: 280.0,
          libraryCollapsed: false,
          mixerCollapsed: false,
        );
        layout.applyLayout(data);
        expect(layout.libraryPanelWidth, 350.0); // same size as saved
        layout.resizeRightColumn(-9999.0);
        expect(layout.libraryPanelWidth, UILayoutState.libraryMinWidth);
      });

      test('applyLayout clamps extreme values', () {
        const data = UILayoutData(
          libraryWidth: 9999.0,
          mixerWidth: 9999.0,
          bottomHeight: 9999.0,
          libraryCollapsed: false,
          mixerCollapsed: false,
        );
        layout.applyLayout(data);

        expect(layout.mixerPanelWidth, UILayoutState.mixerMaxWidth);
        expect(layout.editorPanelHeight, UILayoutState.editorHardMax);
      });
    });
  });
}
