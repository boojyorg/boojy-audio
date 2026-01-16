import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:cross_file/cross_file.dart';

/// Web implementation of PlatformDropTarget using HTML5 drag-drop API
class PlatformDropTarget extends StatefulWidget {
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
  State<PlatformDropTarget> createState() => _PlatformDropTargetState();
}

class _PlatformDropTargetState extends State<PlatformDropTarget> {
  @override
  Widget build(BuildContext context) {
    // Use desktop_drop which has web support
    return DropTarget(
      onDragDone: widget.onDragDone,
      onDragEntered: widget.onDragEntered,
      onDragExited: widget.onDragExited,
      onDragUpdated: widget.onDragUpdated,
      child: widget.child,
    );
  }
}

/// Helper class for reading dropped files on web
class WebFileReader {
  /// Read a web File as bytes
  static Future<Uint8List> readAsBytes(web.File file) async {
    final completer = Completer<Uint8List>();
    final reader = web.FileReader();

    reader.onload = (web.Event event) {
      final arrayBuffer = reader.result as JSArrayBuffer;
      final bytes = arrayBuffer.toDart.asUint8List();
      completer.complete(bytes);
    }.toJS;

    reader.onerror = (web.Event event) {
      completer.completeError('Failed to read file: ${file.name}');
    }.toJS;

    reader.readAsArrayBuffer(file);
    return completer.future;
  }

  /// Read a XFile as bytes (works with file_picker results)
  static Future<Uint8List> readXFileAsBytes(XFile file) async {
    return file.readAsBytes();
  }
}
