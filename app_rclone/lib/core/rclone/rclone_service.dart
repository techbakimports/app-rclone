import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

class RcloneService {
  static const _ch = MethodChannel('com.apprclone.app_rclone/rclone');
  static const _authCh = EventChannel('com.apprclone.app_rclone/auth');

  static const _termuxPaths = [
    '/data/data/com.termux/files/usr/bin/rclone',
    '/data/user/0/com.termux/files/usr/bin/rclone',
  ];

  String? _binaryPath;
  String? _configPath;

  String? get binaryPath => _binaryPath;
  String? get configPath => _configPath;

  /// Looks for rclone installed via Termux (apt/pkg). Returns path or null.
  static Future<String?> detectTermuxRclone() async {
    for (final path in _termuxPaths) {
      if (await File(path).exists()) return path;
    }
    return null;
  }

  /// Returns true when the binary is available and ready to use.
  Future<bool> initialize() async {
    _configPath = await _ch.invokeMethod<String>('getConfigPath');
    try {
      _binaryPath = await _ch.invokeMethod<String>('extractBinary');
      return _binaryPath != null;
    } on PlatformException catch (e) {
      if (e.code == 'BINARY_NOT_FOUND') {
        final termuxPath = await detectTermuxRclone();
        if (termuxPath != null) {
          _binaryPath = termuxPath;
          return true;
        }
        return false;
      }
      rethrow;
    }
  }

  /// Sets a known binary path after a successful download (no native call needed).
  void setBinaryPath(String path) => _binaryPath = path;

  Future<void> startDaemon() async {
    if (_binaryPath == null || _configPath == null) {
      final ok = await initialize();
      if (!ok) throw Exception('rclone binary not installed');
    }
    await _ch.invokeMethod<void>('startDaemon', {
      'binaryPath': _binaryPath,
      'configPath': _configPath,
    });
    // Small grace period for daemon to bind on 5572
    await Future<void>.delayed(const Duration(seconds: 2));
  }

  Future<void> stopDaemon() async {
    await _ch.invokeMethod<void>('stopDaemon');
  }

  Future<bool> isDaemonRunning() async {
    return await _ch.invokeMethod<bool>('isDaemonRunning') ?? false;
  }

  Future<List<String>> getLogs() async {
    final raw = await _ch.invokeMethod<List<Object?>>('getLogs') ?? [];
    return raw.whereType<String>().toList();
  }

  Future<void> clearLogs() async {
    await _ch.invokeMethod<void>('clearLogs');
  }

  /// Starts an OAuth authorization for [remoteType].
  /// Events arrive on the returned broadcast stream:
  ///   `{'type': 'url', 'url': '...'}` — open this URL in a browser
  ///   `{'type': 'token', 'token': '{...}'}` — JSON token string
  Stream<Map<dynamic, dynamic>> startAuthFlow(String remoteType) {
    _ch.invokeMethod<void>('startAuth', {'type': remoteType});
    return _authCh
        .receiveBroadcastStream()
        .cast<Map<dynamic, dynamic>>();
  }

  Future<void> cancelAuth() async {
    await _ch.invokeMethod<void>('cancelAuth');
  }
}
