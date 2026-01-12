import 'package:flutter/material.dart';
import '../../theme/theme_extension.dart';

/// Dialog asking user to opt-in to crash reporting on first launch
class CrashReportingDialog extends StatelessWidget {
  const CrashReportingDialog({super.key});

  /// Show the dialog and return true if user opted in, false otherwise
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const CrashReportingDialog(),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.elevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      title: Text(
        'Help Improve Boojy Audio',
        style: TextStyle(
          color: colors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Would you like to send anonymous crash reports when something goes wrong?',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This helps me fix bugs faster and improve the app for everyone.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'You can change this anytime in Settings > Privacy.',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'No thanks',
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.accent,
            foregroundColor: Colors.white,
          ),
          child: const Text('Yes, send reports'),
        ),
      ],
    );
  }
}
