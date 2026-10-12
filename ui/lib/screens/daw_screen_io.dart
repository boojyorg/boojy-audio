// Native platform IO utilities for DAW screen
// This file is used on native platforms (iOS, macOS, Windows, Linux, Android)

import 'dart:io';

export 'dart:io' show Platform, Directory, File, Process;

/// Get the path separator for the current platform
String get pathSeparator => Platform.pathSeparator;
