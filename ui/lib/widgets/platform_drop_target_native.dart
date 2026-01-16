import 'dart:io';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';

/// A platform-aware drop target that only enables drag-drop on desktop platforms.
/// On iOS/Android, it simply renders the child without drop functionality.
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
    // On mobile platforms, just return the child without drop functionality
    if (Platform.isIOS || Platform.isAndroid) {
      return child;
    }

    // On desktop, wrap with DropTarget
    return DropTarget(
      onDragDone: onDragDone,
      onDragEntered: onDragEntered,
      onDragExited: onDragExited,
      onDragUpdated: onDragUpdated,
      child: child,
    );
  }
}
