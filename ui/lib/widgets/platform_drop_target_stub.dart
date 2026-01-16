// Stub file for conditional imports - used during static analysis

import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';

/// Stub PlatformDropTarget for static analysis
class PlatformDropTarget extends StatelessWidget {
  final Widget child;
  final void Function(DropDoneDetails)? onDragDone;
  final void Function(DropEventDetails)? onDragEntered;
  final void Function(DropEventDetails)? onDragExited;
  final void Function(DropEventDetails)? onDragUpdated;

  const PlatformDropTarget({
    super.key,
    required this.child,
    this.onDragDone,
    this.onDragEntered,
    this.onDragExited,
    this.onDragUpdated,
  });

  @override
  Widget build(BuildContext context) {
    throw UnsupportedError(
      'PlatformDropTarget stub should not be built. '
      'Use conditional imports to get the correct implementation.',
    );
  }
}
