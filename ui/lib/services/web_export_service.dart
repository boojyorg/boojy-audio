// Web Export Service - Browser download handling for Boojy Audio Web
//
// Provides audio export functionality using browser download APIs
// since file system access is not available on web.

import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Service for exporting audio files via browser download
class WebExportService {
  WebExportService._();

  /// Download data as a file in the browser
  static void downloadFile({
    required Uint8List data,
    required String filename,
    String mimeType = 'application/octet-stream',
  }) {
    // Create a Blob from the data
    final jsArray = data.toJS;
    final blob = web.Blob(
      [jsArray].toJS,
      web.BlobPropertyBag(type: mimeType),
    );

    // Create a download URL
    final url = web.URL.createObjectURL(blob);

    // Create a temporary anchor element and trigger download
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = filename;
    anchor.style.display = 'none';

    web.document.body?.appendChild(anchor);
    anchor.click();

    // Clean up
    web.document.body?.removeChild(anchor);
    web.URL.revokeObjectURL(url);
  }

  /// Download WAV audio file
  static void downloadWav({
    required Uint8List wavData,
    required String filename,
  }) {
    if (!filename.endsWith('.wav')) {
      filename = '$filename.wav';
    }
    downloadFile(
      data: wavData,
      filename: filename,
      mimeType: 'audio/wav',
    );
  }

  /// Download MP3 audio file
  static void downloadMp3({
    required Uint8List mp3Data,
    required String filename,
  }) {
    if (!filename.endsWith('.mp3')) {
      filename = '$filename.mp3';
    }
    downloadFile(
      data: mp3Data,
      filename: filename,
      mimeType: 'audio/mpeg',
    );
  }

  /// Download JSON file (for project export)
  static void downloadJson({
    required String jsonString,
    required String filename,
  }) {
    if (!filename.endsWith('.json')) {
      filename = '$filename.json';
    }
    final data = Uint8List.fromList(jsonString.codeUnits);
    downloadFile(
      data: data,
      filename: filename,
      mimeType: 'application/json',
    );
  }

  /// Download project file
  static void downloadProject({
    required String projectJson,
    required String projectName,
  }) {
    downloadJson(
      jsonString: projectJson,
      filename: '$projectName.boojy',
    );
  }
}

/// Service for recording audio from microphone on web
class WebRecordingService {
  web.MediaStream? _mediaStream;
  web.MediaRecorder? _mediaRecorder;
  final List<web.Blob> _chunks = [];
  bool _isRecording = false;
  final _recordingController = StreamController<RecordingState>.broadcast();

  /// Stream of recording state changes
  Stream<RecordingState> get onStateChange => _recordingController.stream;

  /// Whether currently recording
  bool get isRecording => _isRecording;

  /// Request microphone access
  Future<bool> requestMicrophoneAccess() async {
    try {
      final constraints = web.MediaStreamConstraints(
        audio: true.toJS,
        video: false.toJS,
      );
      _mediaStream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Start recording from microphone
  Future<bool> startRecording() async {
    if (_mediaStream == null) {
      final hasAccess = await requestMicrophoneAccess();
      if (!hasAccess) return false;
    }

    try {
      _chunks.clear();
      _mediaRecorder = web.MediaRecorder(
        _mediaStream!,
        web.MediaRecorderOptions(mimeType: 'audio/webm'),
      );

      _mediaRecorder!.ondataavailable = (web.BlobEvent event) {
        if (event.data.size > 0) {
          _chunks.add(event.data);
        }
      }.toJS;

      _mediaRecorder!.onstart = (web.Event event) {
        _isRecording = true;
        _recordingController.add(RecordingState.recording);
      }.toJS;

      _mediaRecorder!.onstop = (web.Event event) {
        _isRecording = false;
        _recordingController.add(RecordingState.stopped);
      }.toJS;

      _mediaRecorder!.start();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Stop recording and return the recorded audio as bytes
  Future<Uint8List?> stopRecording() async {
    if (_mediaRecorder == null || !_isRecording) return null;

    final completer = Completer<Uint8List?>();

    _mediaRecorder!.onstop = (web.Event event) async {
      _isRecording = false;
      _recordingController.add(RecordingState.stopped);

      if (_chunks.isEmpty) {
        completer.complete(null);
        return;
      }

      // Combine all chunks into a single blob
      final blob = web.Blob(_chunks.toJS);

      // Read blob as array buffer
      final reader = web.FileReader();
      reader.onload = (web.Event e) {
        final arrayBuffer = reader.result as JSArrayBuffer;
        final bytes = arrayBuffer.toDart.asUint8List();
        completer.complete(bytes);
      }.toJS;
      reader.onerror = (web.Event e) {
        completer.complete(null);
      }.toJS;
      reader.readAsArrayBuffer(blob);
    }.toJS;

    _mediaRecorder!.stop();
    return completer.future;
  }

  /// Release microphone access
  void releaseMicrophone() {
    if (_mediaStream != null) {
      final tracks = _mediaStream!.getTracks().toDart;
      for (final track in tracks) {
        track.stop();
      }
      _mediaStream = null;
    }
    _mediaRecorder = null;
    _chunks.clear();
  }

  /// Dispose of resources
  void dispose() {
    releaseMicrophone();
    _recordingController.close();
  }
}

/// Recording state
enum RecordingState {
  idle,
  recording,
  stopped,
}
