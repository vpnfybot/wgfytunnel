import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AppLogService {
  static const int maxLogFileBytes = 256 * 1024;
  static const String _logDirectoryName = 'logs';
  static const String _logFileName = 'app_errors.log';

  static Future<File>? _logFileFuture;
  static Future<void> _writeQueue = Future<void>.value();

  static Future<void> initialize() async {
    await _ensureLogFile();
  }

  static Future<void> logError(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String origin = 'app',
  }) {
    return _enqueueWrite(() async {
      final file = await _ensureLogFile();
      final buffer = StringBuffer()
        ..writeln(
          '[${DateTime.now().toIso8601String()}] ERROR ${origin.toUpperCase()}',
        )
        ..writeln(message);

      if (error != null) {
        buffer.writeln('error: $error');
      }
      if (stackTrace != null) {
        buffer.writeln(stackTrace.toString().trimRight());
      }
      buffer.writeln();

      await _appendAndTrim(file, buffer.toString());
    });
  }

  static Future<void> logFlutterError(
    FlutterErrorDetails details, {
    String origin = 'flutter',
  }) {
    final context = details.context?.toDescription();
    final message = context == null
        ? details.exceptionAsString()
        : '$context\n${details.exceptionAsString()}';
    return logError(
      message,
      error: details.exception,
      stackTrace: details.stack,
      origin: origin,
    );
  }

  static Future<String> readLogs() async {
    try {
      await _writeQueue;
    } catch (_) {
      // A failed write must not prevent the logs page from opening.
    }

    final file = await _ensureLogFile();
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  static Future<void> clearLogs() {
    return _enqueueWrite(() async {
      final file = await _ensureLogFile();
      await file.writeAsString('', flush: true);
    });
  }

  static Future<String> logFilePath() async {
    final file = await _ensureLogFile();
    return file.path;
  }

  static Future<File> _ensureLogFile() {
    _logFileFuture ??= () async {
      final appSupportDirectory = await getApplicationSupportDirectory();
      final logDirectory = Directory(
        '${appSupportDirectory.path}${Platform.pathSeparator}$_logDirectoryName',
      );
      if (!await logDirectory.exists()) {
        await logDirectory.create(recursive: true);
      }

      final file = File(
        '${logDirectory.path}${Platform.pathSeparator}$_logFileName',
      );
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      return file;
    }();
    return _logFileFuture!;
  }

  static Future<void> _appendAndTrim(File file, String entry) async {
    final existingBytes = await file.readAsBytes();
    final updatedBytes = <int>[...existingBytes, ...utf8.encode(entry)];
    final trimmedBytes = _trimToMaxBytes(updatedBytes);
    await file.writeAsBytes(trimmedBytes, flush: true);
  }

  static List<int> _trimToMaxBytes(List<int> bytes) {
    if (bytes.length <= maxLogFileBytes) {
      return bytes;
    }

    final tailBytes = bytes.sublist(bytes.length - maxLogFileBytes);
    final firstNewlineIndex = tailBytes.indexOf(10);
    if (firstNewlineIndex <= 0 || firstNewlineIndex >= tailBytes.length - 1) {
      return tailBytes;
    }

    return tailBytes.sublist(firstNewlineIndex + 1);
  }

  static Future<void> _enqueueWrite(Future<void> Function() action) {
    _writeQueue = _writeQueue.catchError((_) {}).then((_) => action());
    return _writeQueue;
  }
}
