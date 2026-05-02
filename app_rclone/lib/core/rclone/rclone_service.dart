import 'dart:async';
import 'package:flutter/services.dart';

class DaemonCredentials {
  final int port;
  final String user;
  final String pass;

  const DaemonCredentials({
    required this.port,
    required this.user,
    required this.pass,
  });

  String get baseUrl => 'http://127.0.0.1:$port';
}

class SafBridgeInfo {
  final int port;
  final String user;
  final String pass;

  const SafBridgeInfo({
    required this.port,
    required this.user,
    required this.pass,
  });

  String get webdavUrl => 'http://127.0.0.1:$port';
}

class RcloneService {
  static const _ch = MethodChannel('com.apprclone.app_rclone/rclone');
  static const _authCh = EventChannel('com.apprclone.app_rclone/auth');

  String? _binaryPath;
  String? _configPath;

  String? get binaryPath => _binaryPath;
  String? get configPath => _configPath;

  Future<bool> initialize() async {
    _configPath = await _ch.invokeMethod<String>('getConfigPath');
    try {
      _binaryPath = await _ch.invokeMethod<String>('extractBinary');
      return _binaryPath != null;
    } on PlatformException catch (e) {
      if (e.code == 'BINARY_NOT_FOUND') return false;
      rethrow;
    }
  }

  Future<void> setExecutable(String path) async {
    await _ch.invokeMethod<void>('setExecutable', {'path': path});
  }

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
    await Future<void>.delayed(const Duration(seconds: 1));
  }

  Future<void> stopDaemon() async {
    await _ch.invokeMethod<void>('stopDaemon');
  }

  Future<bool> isDaemonRunning() async {
    return await _ch.invokeMethod<bool>('isDaemonRunning') ?? false;
  }

  // Returns daemon credentials once the service has allocated a port.
  // Returns null if the daemon hasn't started yet (port == 0).
  Future<DaemonCredentials?> getDaemonCredentials() async {
    final raw = await _ch.invokeMethod<Map>('getDaemonCredentials');
    if (raw == null) return null;
    final port = raw['port'] as int? ?? 0;
    if (port == 0) return null;
    return DaemonCredentials(
      port: port,
      user: raw['user'] as String? ?? 'rcloneapp',
      pass: raw['pass'] as String? ?? '',
    );
  }

  Future<List<String>> getLogs() async {
    final raw = await _ch.invokeMethod<List<Object?>>('getLogs') ?? [];
    return raw.whereType<String>().toList();
  }

  Future<void> clearLogs() async {
    await _ch.invokeMethod<void>('clearLogs');
  }

  // ── OAuth ─────────────────────────────────────────────────────────────────

  Stream<Map<dynamic, dynamic>> startAuthFlow(String remoteType) {
    _ch.invokeMethod<void>('startAuth', {'type': remoteType});
    return _authCh.receiveBroadcastStream().cast<Map<dynamic, dynamic>>();
  }

  Future<void> cancelAuth() async {
    await _ch.invokeMethod<void>('cancelAuth');
  }

  // ── SAF ───────────────────────────────────────────────────────────────────

  /// Opens the Android document-tree picker. Returns the selected URI string,
  /// or null if the user cancelled.
  Future<String?> openDocumentTree() async {
    return _ch.invokeMethod<String?>('openDocumentTree');
  }

  /// Starts the WebDAV bridge for the given SAF tree URI.
  /// Returns the bridge credentials so rclone can connect to it.
  Future<SafBridgeInfo> startSafBridge(String treeUri) async {
    final raw = await _ch.invokeMethod<Map>('startSafBridge', {'treeUri': treeUri});
    if (raw == null) throw Exception('startSafBridge returned null');
    return SafBridgeInfo(
      port: raw['port'] as int,
      user: raw['user'] as String,
      pass: raw['pass'] as String,
    );
  }

  Future<void> stopSafBridge() async {
    await _ch.invokeMethod<void>('stopSafBridge');
  }

  // ── Background sync (WorkManager) ─────────────────────────────────────────

  /// Enqueues a persistent background sync job via WorkManager.
  /// Returns the WorkManager job UUID string.
  Future<String> enqueueSyncJob({
    required String operation,
    required String srcFs,
    required String dstFs,
    String? label,
  }) async {
    final result = await _ch.invokeMethod<String>('enqueueSyncJob', {
      'operation': operation,
      'srcFs': srcFs,
      'dstFs': dstFs,
      'label': ?label,
    });
    return result ?? '';
  }
}
