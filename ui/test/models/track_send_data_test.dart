import 'package:boojy_audio/models/track_send_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TrackSendData.parseTrackSendsCsv', () {
    test('parses empty CSV', () {
      expect(TrackSendData.parseTrackSendsCsv(''), isEmpty);
      expect(TrackSendData.parseTrackSendsCsv('Error: foo'), isEmpty);
    });

    test('parses single and multiple sends', () {
      const csv = '10,-20.00,Reverb;11,-10.00,Delay';
      final sends = TrackSendData.parseTrackSendsCsv(
        csv,
        returnEffectTypes: {10: 'reverb', 11: 'delay'},
      );

      expect(sends, hasLength(2));
      expect(sends[0].returnId, 10);
      expect(sends[0].label, 'Reverb');
      expect(sends[0].effectType, 'reverb');
      expect(sends[0].amountLinear, closeTo(0.1, 0.001));
      expect(sends[1].returnId, 11);
      expect(sends[1].amountPercentLabel, '32%');
    });

    test('decodes a percent-encoded return name (C34)', () {
      // A ',' or ';' in the name would shift fields / split entries — the
      // engine escapes them.
      const csv = '10,-20.00,Verb%2C Long%3B Dark;11,-10.00,Delay';
      final sends = TrackSendData.parseTrackSendsCsv(csv);

      expect(sends, hasLength(2));
      expect(sends[0].label, 'Verb, Long; Dark');
      expect(sends[1].returnId, 11);
      expect(sends[1].label, 'Delay');
    });
  });

  group('ReturnTrackData.parseAllReturnsCsv', () {
    test('parses return buses', () {
      const csv = '5,Reverb,reverb;6,Delay,delay';
      final returns = ReturnTrackData.parseAllReturnsCsv(csv);
      expect(returns, hasLength(2));
      expect(returns.first.name, 'Reverb');
      expect(returns.first.effectType, 'reverb');
    });

    test('decodes a percent-encoded return name (C34)', () {
      const csv = '5,Plate%2C Big,reverb;6,Delay,delay';
      final returns = ReturnTrackData.parseAllReturnsCsv(csv);

      expect(returns, hasLength(2));
      expect(returns.first.name, 'Plate, Big');
      expect(returns.first.effectType, 'reverb');
      expect(returns[1].id, 6);
    });
  });
}
