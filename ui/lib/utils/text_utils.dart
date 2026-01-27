import 'package:flutter/material.dart';

/// Utilities for text formatting and truncation
class TextUtils {
  TextUtils._(); // Prevent instantiation

  /// Truncates a filename from the middle while preserving the extension.
  ///
  /// Examples:
  /// - "VeryLongFileName.wav" -> "VeryLo...Name.wav" (when space is limited)
  /// - "Short.wav" -> "Short.wav" (no truncation needed)
  /// - "NoExtension" -> "NoExte...sion" (handles files without extension)
  ///
  /// Parameters:
  /// - [filename]: The full filename to truncate
  /// - [maxLength]: Maximum number of characters (including ellipsis)
  ///
  /// Returns the truncated filename or original if it fits.
  static String truncateMiddle(String filename, int maxLength) {
    // If it fits, return as-is
    if (filename.length <= maxLength) return filename;

    // Minimum length: we need at least "a...b" = 5 chars
    if (maxLength < 5) return filename.substring(0, maxLength);

    // Find the extension
    final lastDot = filename.lastIndexOf('.');
    final hasExtension = lastDot > 0 && lastDot < filename.length - 1;

    String baseName;
    String extension;

    if (hasExtension) {
      baseName = filename.substring(0, lastDot);
      extension = filename.substring(lastDot); // includes the dot
    } else {
      baseName = filename;
      extension = '';
    }

    // Calculate available space for the base name
    // We need: start + "..." + end + extension
    const ellipsis = '...';
    final availableForBase = maxLength - extension.length - ellipsis.length;

    if (availableForBase < 2) {
      // Not enough space even for "a...b", just truncate normally
      return '${filename.substring(0, maxLength - 3)}...';
    }

    // Split available space: slightly more to start for readability
    final startLength = (availableForBase * 0.6).ceil();
    final endLength = availableForBase - startLength;

    if (endLength < 1) {
      // Edge case: just show start + ellipsis + extension
      return '${baseName.substring(0, availableForBase)}$ellipsis$extension';
    }

    final start = baseName.substring(0, startLength);
    final end = baseName.substring(baseName.length - endLength);

    return '$start$ellipsis$end$extension';
  }

  /// Measures text width and returns a truncated version that fits.
  ///
  /// This is more accurate than character counting as it accounts
  /// for variable-width fonts.
  static String truncateMiddleToFit({
    required String filename,
    required double maxWidth,
    required TextStyle style,
  }) {
    // Quick check: does the full text fit?
    final fullWidth = _measureText(filename, style);
    if (fullWidth <= maxWidth) return filename;

    // Binary search for the right length
    int low = 5;
    int high = filename.length;

    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      final truncated = truncateMiddle(filename, mid);
      final width = _measureText(truncated, style);

      if (width <= maxWidth) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }

    return truncateMiddle(filename, low);
  }

  static double _measureText(String text, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    return textPainter.width;
  }
}
