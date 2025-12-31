import 'package:flutter_test/flutter_test.dart';
import 'package:boojy_audio/models/project_view_state.dart';

void main() {
  group('ProjectViewState', () {
    group('constructor', () {
      test('creates state with default values', () {
        const state = ProjectViewState();

        expect(state.horizontalScroll, 0.0);
        expect(state.verticalScroll, 0.0);
        expect(state.zoom, 1.0);
        expect(state.libraryVisible, true);
        expect(state.mixerVisible, false);
        expect(state.editorVisible, true);
        expect(state.virtualPianoVisible, false);
        expect(state.selectedTrackId, isNull);
        expect(state.playheadPosition, 0.0);
      });

      test('creates state with custom values', () {
        const state = ProjectViewState(
          horizontalScroll: 100.0,
          verticalScroll: 50.0,
          zoom: 2.0,
          libraryVisible: false,
          mixerVisible: true,
          editorVisible: false,
          virtualPianoVisible: true,
          selectedTrackId: 5,
          playheadPosition: 16.0,
        );

        expect(state.horizontalScroll, 100.0);
        expect(state.verticalScroll, 50.0);
        expect(state.zoom, 2.0);
        expect(state.libraryVisible, false);
        expect(state.mixerVisible, true);
        expect(state.editorVisible, false);
        expect(state.virtualPianoVisible, true);
        expect(state.selectedTrackId, 5);
        expect(state.playheadPosition, 16.0);
      });
    });

    group('defaultState', () {
      test('returns default state', () {
        final state = ProjectViewState.defaultState();

        expect(state.horizontalScroll, 0.0);
        expect(state.verticalScroll, 0.0);
        expect(state.zoom, 1.0);
        expect(state.libraryVisible, true);
        expect(state.mixerVisible, false);
      });
    });

    group('fromJson', () {
      test('creates state from complete JSON', () {
        final json = {
          'horizontalScroll': 150.0,
          'verticalScroll': 75.0,
          'zoom': 1.5,
          'libraryVisible': false,
          'mixerVisible': true,
          'editorVisible': false,
          'virtualPianoVisible': true,
          'selectedTrackId': 3,
          'playheadPosition': 8.0,
        };

        final state = ProjectViewState.fromJson(json);

        expect(state.horizontalScroll, 150.0);
        expect(state.verticalScroll, 75.0);
        expect(state.zoom, 1.5);
        expect(state.libraryVisible, false);
        expect(state.mixerVisible, true);
        expect(state.editorVisible, false);
        expect(state.virtualPianoVisible, true);
        expect(state.selectedTrackId, 3);
        expect(state.playheadPosition, 8.0);
      });

      test('uses defaults for missing fields', () {
        final json = <String, dynamic>{};

        final state = ProjectViewState.fromJson(json);

        expect(state.horizontalScroll, 0.0);
        expect(state.verticalScroll, 0.0);
        expect(state.zoom, 1.0);
        expect(state.libraryVisible, true);
        expect(state.mixerVisible, false);
        expect(state.editorVisible, true);
        expect(state.virtualPianoVisible, false);
        expect(state.selectedTrackId, isNull);
        expect(state.playheadPosition, 0.0);
      });

      test('handles numeric types correctly', () {
        final json = {
          'horizontalScroll': 100, // int instead of double
          'zoom': 2, // int instead of double
        };

        final state = ProjectViewState.fromJson(json);

        expect(state.horizontalScroll, 100.0);
        expect(state.zoom, 2.0);
      });
    });

    group('toJson', () {
      test('converts state to JSON', () {
        const state = ProjectViewState(
          horizontalScroll: 200.0,
          verticalScroll: 100.0,
          zoom: 1.25,
          libraryVisible: false,
          mixerVisible: true,
          editorVisible: true,
          virtualPianoVisible: false,
          selectedTrackId: 7,
          playheadPosition: 32.0,
        );

        final json = state.toJson();

        expect(json['horizontalScroll'], 200.0);
        expect(json['verticalScroll'], 100.0);
        expect(json['zoom'], 1.25);
        expect(json['libraryVisible'], false);
        expect(json['mixerVisible'], true);
        expect(json['editorVisible'], true);
        expect(json['virtualPianoVisible'], false);
        expect(json['selectedTrackId'], 7);
        expect(json['playheadPosition'], 32.0);
      });

      test('roundtrips through JSON', () {
        const original = ProjectViewState(
          horizontalScroll: 500.0,
          verticalScroll: 250.0,
          zoom: 0.75,
          libraryVisible: true,
          mixerVisible: true,
          editorVisible: false,
          virtualPianoVisible: true,
          selectedTrackId: 42,
          playheadPosition: 64.0,
        );

        final json = original.toJson();
        final restored = ProjectViewState.fromJson(json);

        expect(restored, original);
      });
    });

    group('copyWith', () {
      test('copies with no changes', () {
        const original = ProjectViewState(
          horizontalScroll: 100.0,
          zoom: 2.0,
        );
        final copy = original.copyWith();

        expect(copy.horizontalScroll, 100.0);
        expect(copy.zoom, 2.0);
        expect(copy.libraryVisible, true);
      });

      test('copies with specific changes', () {
        const original = ProjectViewState();
        final copy = original.copyWith(
          zoom: 3.0,
          mixerVisible: true,
          selectedTrackId: 10,
        );

        expect(copy.zoom, 3.0);
        expect(copy.mixerVisible, true);
        expect(copy.selectedTrackId, 10);
        expect(copy.horizontalScroll, 0.0); // Unchanged
        expect(copy.libraryVisible, true); // Unchanged
      });
    });

    group('equality', () {
      test('equal states are equal', () {
        const s1 = ProjectViewState(
          horizontalScroll: 100.0,
          zoom: 1.5,
          libraryVisible: false,
        );
        const s2 = ProjectViewState(
          horizontalScroll: 100.0,
          zoom: 1.5,
          libraryVisible: false,
        );

        expect(s1 == s2, true);
        expect(s1.hashCode, s2.hashCode);
      });

      test('different states are not equal', () {
        const s1 = ProjectViewState(zoom: 1.0);
        const s2 = ProjectViewState(zoom: 2.0);

        expect(s1 == s2, false);
      });

      test('states with different panel visibility are not equal', () {
        const s1 = ProjectViewState(libraryVisible: true);
        const s2 = ProjectViewState(libraryVisible: false);

        expect(s1 == s2, false);
      });
    });

    group('toString', () {
      test('returns readable string', () {
        const state = ProjectViewState(
          horizontalScroll: 50.0,
          verticalScroll: 25.0,
          zoom: 1.5,
        );

        final str = state.toString();

        expect(str, contains('50.0'));
        expect(str, contains('25.0'));
        expect(str, contains('1.5'));
        expect(str, contains('L=true'));
        expect(str, contains('M=false'));
      });
    });
  });
}
