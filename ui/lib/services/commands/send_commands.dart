import '../../models/track_send_data.dart';
import 'audio_engine_interface.dart';
import 'command.dart';

/// Command to add a send to an existing return at the default level.
class AddSendCommand extends Command {
  final int sourceTrackId;
  final String sourceTrackName;
  final int returnTrackId;
  final String returnLabel;
  final double amountDb;
  final void Function()? onChanged;

  AddSendCommand({
    required this.sourceTrackId,
    required this.sourceTrackName,
    required this.returnTrackId,
    required this.returnLabel,
    this.amountDb = -20.0,
    this.onChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    engine.addSend(sourceTrackId, returnTrackId, amountDb);
    onChanged?.call();
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    engine.removeSend(sourceTrackId, returnTrackId);
    onChanged?.call();
  }

  @override
  String get description => 'Add Send: $returnLabel → $sourceTrackName';
}

/// Command to change a send amount (dB).
class SetSendAmountCommand extends Command {
  final int sourceTrackId;
  final String sourceTrackName;
  final int returnTrackId;
  final String returnLabel;
  final double newAmountDb;
  final double oldAmountDb;
  final void Function(int sourceTrackId, int returnTrackId, double amountDb)?
  onSendAmountChanged;

  SetSendAmountCommand({
    required this.sourceTrackId,
    required this.sourceTrackName,
    required this.returnTrackId,
    required this.returnLabel,
    required this.newAmountDb,
    required this.oldAmountDb,
    this.onSendAmountChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    engine.setSendAmount(sourceTrackId, returnTrackId, newAmountDb);
    onSendAmountChanged?.call(sourceTrackId, returnTrackId, newAmountDb);
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    engine.setSendAmount(sourceTrackId, returnTrackId, oldAmountDb);
    onSendAmountChanged?.call(sourceTrackId, returnTrackId, oldAmountDb);
  }

  @override
  String get description =>
      'Send $returnLabel: $sourceTrackName (${oldAmountDb.toStringAsFixed(0)} → ${newAmountDb.toStringAsFixed(0)} dB)';
}

/// Composite: create return (if needed) + add send at default level.
class AddSharedSendCommand extends Command {
  final int sourceTrackId;
  final String sourceTrackName;
  final String effectType;
  final String effectLabel;
  final void Function()? onChanged;

  int? _returnTrackId;

  AddSharedSendCommand({
    required this.sourceTrackId,
    required this.sourceTrackName,
    required this.effectType,
    required this.effectLabel,
    this.onChanged,
  });

  int? get returnTrackId => _returnTrackId;

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    final result = engine.addSharedSend(sourceTrackId, effectType);
    if (result.startsWith('Error')) {
      throw StateError(result);
    }
    final parts = result.split(',');
    if (parts.isNotEmpty) {
      _returnTrackId = int.tryParse(parts[0]);
    }
    onChanged?.call();
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    if (_returnTrackId == null) return;
    engine.removeSend(sourceTrackId, _returnTrackId!);
    if (engine.countSendsToReturn(_returnTrackId!) == 0) {
      engine.removeReturn(_returnTrackId!);
    }
    onChanged?.call();
  }

  @override
  String get description => 'Add Send: $effectLabel → $sourceTrackName';
}

/// Command to remove a send (bus remains).
class RemoveSendCommand extends Command {
  final int sourceTrackId;
  final String sourceTrackName;
  final int returnTrackId;
  final String returnLabel;
  final double previousAmountDb;
  final void Function()? onChanged;

  RemoveSendCommand({
    required this.sourceTrackId,
    required this.sourceTrackName,
    required this.returnTrackId,
    required this.returnLabel,
    required this.previousAmountDb,
    this.onChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    engine.removeSend(sourceTrackId, returnTrackId);
    onChanged?.call();
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    engine.addSend(sourceTrackId, returnTrackId, previousAmountDb);
    onChanged?.call();
  }

  @override
  String get description => 'Remove Send: $returnLabel from $sourceTrackName';
}

/// Composite: remove return + all sends pointing to it.
class RemoveReturnCommand extends Command {
  final int returnTrackId;
  final String returnLabel;
  final String effectType;
  final List<({int sourceTrackId, double amountDb})> _previousSends = [];
  final void Function()? onChanged;

  RemoveReturnCommand({
    required this.returnTrackId,
    required this.returnLabel,
    required this.effectType,
    this.onChanged,
  });

  @override
  Future<void> execute(AudioEngineInterface engine) async {
    _previousSends.clear();
    for (final trackId in engine.getAllTrackIds()) {
      final csv = engine.getTrackSends(trackId);
      final sends = TrackSendData.parseTrackSendsCsv(csv);
      for (final send in sends) {
        if (send.returnId == returnTrackId) {
          _previousSends.add((
            sourceTrackId: trackId,
            amountDb: TrackSendData.linearToDb(send.amountLinear),
          ));
        }
      }
    }
    engine.removeReturn(returnTrackId);
    onChanged?.call();
  }

  @override
  Future<void> undo(AudioEngineInterface engine) async {
    final recreatedId = engine.createReturnWithEffect(
      effectType,
      name: returnLabel,
    );
    if (recreatedId < 0) return;

    for (final send in _previousSends) {
      engine.addSend(send.sourceTrackId, recreatedId, send.amountDb);
    }
    onChanged?.call();
  }

  @override
  String get description => 'Delete Return: $returnLabel';
}
