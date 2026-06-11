import 'package:flutter/material.dart';
import '../theme/boojy_icons.dart';
import '../theme/theme_extension.dart';
import '../theme/tokens.dart';
import 'shared/boojy_wordmark.dart';

// NOTE: This file used to also hold SettingsDialog, a never-shown settings
// UI (with an undo-limit field). It was dead code — the live settings entry
// point is AppSettingsDialog — and was deleted in v0.6 (#45). The undo limit
// stays at the UserSettings default and is deliberately not user-settable.

/// Recovery dialog shown when a crash recovery backup is found
class RecoveryDialog extends StatelessWidget {
  final String backupPath;
  final DateTime backupDate;

  const RecoveryDialog({
    super.key,
    required this.backupPath,
    required this.backupDate,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String backupPath,
    required DateTime backupDate,
  }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: BT.dialogBarrierColor,
      builder: (context) =>
          RecoveryDialog(backupPath: backupPath, backupDate: backupDate),
    );
  }

  String get _friendlyDate {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final month = months[backupDate.month - 1];
    final day = backupDate.day;
    final year = backupDate.year;
    final hour = backupDate.hour > 12
        ? backupDate.hour - 12
        : (backupDate.hour == 0 ? 12 : backupDate.hour);
    final minute = backupDate.minute.toString().padLeft(2, '0');
    final period = backupDate.hour >= 12 ? 'PM' : 'AM';
    return '$month $day, $year at $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: BT.dialogWidthSm,
        decoration: BoxDecoration(
          color: colors.dark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo — the code-drawn lockup (the old PNGs baked the text
              // near-black, so the brand vanished on this dark modal — H13).
              const BoojyWordmarkLockup(scale: 0.75),
              const SizedBox(height: 20),

              // Message
              Text(
                'Your project was not saved before',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                'Boojy Audio closed.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 15),
              ),
              const SizedBox(height: 24),

              // Backup info card — centred content
              FractionallySizedBox(
                widthFactor: 0.8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: colors.darkest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.divider),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(BI.history, color: colors.textMuted, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'Untitled',
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 15,
                              fontWeight: BT.weightSemiBold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _friendlyDate,
                        style: TextStyle(color: colors.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Bottom row — equal-width buttons, centred
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Start Fresh — ghost style, same size as Recover
                  SizedBox(
                    width: 175,
                    height: 36,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: TextButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Start fresh',
                        style: TextStyle(color: colors.textMuted, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Recover Backup — accent pill button
                  SizedBox(
                    width: 175,
                    height: 36,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Recover Backup',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: BT.weightSemiBold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
