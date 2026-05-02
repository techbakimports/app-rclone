import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/remote.dart';
import '../models/job.dart';
import '../models/file_item.dart';

class RcloneApiException implements Exception {
  final String message;
  final int? statusCode;
  RcloneApiException(this.message, {this.statusCode});
  @override
  String toString() => 'RcloneApiException: $message';
}

class RcloneApi {
  final String _base;
  final String? _username;
  final String? _password;
  final http.Client _client;

  RcloneApi({
    String baseUrl = 'http://127.0.0.1:5572',
    String? username,
    String? password,
    http.Client? client,
  })  : _base = baseUrl,
        _username = username,
        _password = password,
        _client = client ?? http.Client();

  Map<String, String> get _headers {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (_username != null && _password != null) {
      final creds = base64Encode(utf8.encode('$_username:$_password'));
      h['Authorization'] = 'Basic $creds';
    }
    return h;
  }

  Future<Map<String, dynamic>> _post(
    String endpoint, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = Uri.parse('$_base/$endpoint');
    final response = await _client
        .post(
          uri,
          headers: _headers,
          body: body != null ? jsonEncode(body) : '{}',
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode >= 400) {
      final err = _tryParseError(response.body);
      throw RcloneApiException(err, statusCode: response.statusCode);
    }

    final decoded = jsonDecode(response.body);
    return decoded as Map<String, dynamic>;
  }

  String _tryParseError(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return m['error'] as String? ?? body;
    } catch (_) {
      return body;
    }
  }

  // ── Health ────────────────────────────────────────────────────────────────

  Future<bool> ping() async {
    try {
      await _post('rc/noop');
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Version ───────────────────────────────────────────────────────────────

  Future<String> getVersion() async {
    final r = await _post('core/version');
    return r['version'] as String? ?? '';
  }

  // ── Config ────────────────────────────────────────────────────────────────

  Future<List<String>> listRemotes() async {
    final r = await _post('config/listremotes');
    return List<String>.from(r['remotes'] as List? ?? []);
  }

  Future<Remote> getRemote(String name) async {
    final r = await _post('config/get', {'name': name});
    return Remote.fromApi(name, r);
  }

  Future<void> createRemote(
    String name,
    String type,
    Map<String, String> params,
  ) async {
    await _post('config/create', {
      'name': name,
      'type': type,
      'parameters': params,
    });
  }

  Future<void> updateRemote(String name, Map<String, String> params) async {
    await _post('config/update', {'name': name, 'parameters': params});
  }

  Future<void> deleteRemote(String name) async {
    await _post('config/delete', {'name': name});
  }

  Future<List<RemoteProvider>> listProviders() async {
    final r = await _post('config/providers');
    final providers = r['providers'] as List? ?? [];
    return providers
        .map((p) => RemoteProvider.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  // ── File Operations ───────────────────────────────────────────────────────

  Future<List<FileItem>> listDirectory(String remotePath) async {
    final r = await _post('operations/list', {
      'fs': _fsFromPath(remotePath),
      'remote': _remoteFromPath(remotePath),
    });
    final items = r['list'] as List? ?? [];
    return items
        .map((i) => FileItem.fromJson(i as Map<String, dynamic>))
        .toList();
  }

  Future<void> createDirectory(String remotePath) async {
    await _post('operations/mkdir', {
      'fs': _fsFromPath(remotePath),
      'remote': _remoteFromPath(remotePath),
    });
  }

  Future<void> deleteFile(String remotePath) async {
    await _post('operations/deletefile', {
      'fs': _fsFromPath(remotePath),
      'remote': _remoteFromPath(remotePath),
    });
  }

  Future<void> purgeDirectory(String remotePath) async {
    await _post('operations/purge', {
      'fs': _fsFromPath(remotePath),
      'remote': _remoteFromPath(remotePath),
    });
  }

  Future<void> copyFile(String srcPath, String dstPath) async {
    await _post('operations/copyfile', {
      'srcFs': _fsFromPath(srcPath),
      'srcRemote': _remoteFromPath(srcPath),
      'dstFs': _fsFromPath(dstPath),
      'dstRemote': _remoteFromPath(dstPath),
    });
  }

  Future<void> moveFile(String srcPath, String dstPath) async {
    await _post('operations/movefile', {
      'srcFs': _fsFromPath(srcPath),
      'srcRemote': _remoteFromPath(srcPath),
      'dstFs': _fsFromPath(dstPath),
      'dstRemote': _remoteFromPath(dstPath),
    });
  }

  Future<Map<String, dynamic>> statPath(String remotePath) async {
    return _post('operations/stat', {
      'fs': _fsFromPath(remotePath),
      'remote': _remoteFromPath(remotePath),
    });
  }

  // ── Async Jobs (copy/move/sync) ───────────────────────────────────────────

  Future<int> startCopy(String srcFs, String dstFs) async {
    final r = await _post('sync/copy', {
      'srcFs': srcFs,
      'dstFs': dstFs,
      '_async': true,
    });
    return r['jobid'] as int? ?? 0;
  }

  Future<int> startMove(String srcFs, String dstFs) async {
    final r = await _post('sync/move', {
      'srcFs': srcFs,
      'dstFs': dstFs,
      '_async': true,
    });
    return r['jobid'] as int? ?? 0;
  }

  Future<int> startSync(String srcFs, String dstFs) async {
    final r = await _post('sync/sync', {
      'srcFs': srcFs,
      'dstFs': dstFs,
      '_async': true,
    });
    return r['jobid'] as int? ?? 0;
  }

  Future<int> startBisync(String path1, String path2) async {
    final r = await _post('sync/bisync', {
      'path1': path1,
      'path2': path2,
      '_async': true,
    });
    return r['jobid'] as int? ?? 0;
  }

  // ── Jobs ──────────────────────────────────────────────────────────────────

  Future<List<RcloneJob>> listJobs() async {
    final r = await _post('job/list');
    final jobs = r['jobids'] as List? ?? [];
    final futures = jobs.map((id) => getJob(id as int)).toList();
    final results = await Future.wait(futures, eagerError: false);
    return results.whereType<RcloneJob>().toList();
  }

  Future<RcloneJob> getJob(int jobId) async {
    final r = await _post('job/status', {'jobid': jobId});
    return RcloneJob.fromJson({...r, 'id': jobId});
  }

  Future<void> stopJob(int jobId) async {
    await _post('job/stop', {'jobid': jobId});
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  Future<TransferStats> getStats({String? group}) async {
    final body = group != null ? {'group': group} : <String, dynamic>{};
    final r = await _post('core/stats', body);
    return TransferStats.fromJson(r);
  }

  Future<void> resetStats() async {
    await _post('core/stats-reset');
  }

  // ── Bandwidth ─────────────────────────────────────────────────────────────

  Future<void> setBandwidthLimit(String rate) async {
    await _post('core/bwlimit', {'rate': rate});
  }

  Future<String> getBandwidthLimit() async {
    final r = await _post('core/bwlimit');
    return r['rate'] as String? ?? 'off';
  }

  // ── Mount ─────────────────────────────────────────────────────────────────

  Future<void> mount(String fs, String mountPoint) async {
    await _post('mount/mount', {'fs': fs, 'mountPoint': mountPoint});
  }

  Future<void> unmount(String mountPoint) async {
    await _post('mount/unmount', {'mountPoint': mountPoint});
  }

  Future<Map<String, dynamic>> listMounts() async {
    return _post('mount/listmounts');
  }

  // ── VFS ───────────────────────────────────────────────────────────────────

  Future<void> vfsForgetAll() async {
    await _post('vfs/forget');
  }

  Future<void> vfsRefresh(String fs) async {
    await _post('vfs/refresh', {'fs': fs});
  }

  // ── Cache ─────────────────────────────────────────────────────────────────

  Future<void> cacheExpire() async {
    await _post('cache/expire');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fsFromPath(String fullPath) {
    final colon = fullPath.indexOf(':');
    if (colon < 0) return fullPath;
    return fullPath.substring(0, colon + 1);
  }

  String _remoteFromPath(String fullPath) {
    final colon = fullPath.indexOf(':');
    if (colon < 0) return '';
    return fullPath.substring(colon + 1);
  }

  void dispose() => _client.close();
}
