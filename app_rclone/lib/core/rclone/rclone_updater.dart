import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class RcloneRelease {
  final String version;
  final String downloadUrl;
  final int sizeBytes;

  const RcloneRelease({
    required this.version,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  String get sizeMb => '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

class RcloneUpdater {
  static const _githubLatest =
      'https://api.github.com/repos/rclone/rclone/releases/latest';
  static const _downloadBase = 'https://downloads.rclone.org';
  static const _headers = {'Accept': 'application/vnd.github.v3+json'};

  final http.Client _client;

  RcloneUpdater({http.Client? client}) : _client = client ?? http.Client();

  Future<RcloneRelease> fetchLatestRelease() async {
    // Get latest version tag from GitHub
    final res = await _client
        .get(Uri.parse(_githubLatest), headers: _headers)
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception('GitHub API returned ${res.statusCode}');
    }

    final version =
        (jsonDecode(res.body) as Map<String, dynamic>)['tag_name'] as String;

    // Try versioned URL on rclone's download server (consistent naming)
    final versionedUrl =
        '$_downloadBase/$version/rclone-$version-android-arm64.zip';
    final release = await _tryUrl(version, versionedUrl);
    if (release != null) return release;

    // Fallback: "current" alias always points to latest stable android-arm64
    const currentUrl = '$_downloadBase/rclone-current-android-arm64.zip';
    final current = await _tryUrl('latest', currentUrl);
    if (current != null) return current;

    throw Exception('android-arm64 build not available on downloads.rclone.org');
  }

  Future<RcloneRelease?> _tryUrl(String version, String url) async {
    try {
      final res = await _client
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final sizeBytes =
          int.tryParse(res.headers['content-length'] ?? '') ?? 0;
      return RcloneRelease(
        version: version,
        downloadUrl: url,
        sizeBytes: sizeBytes,
      );
    } catch (_) {
      return null;
    }
  }

  /// Downloads and installs the rclone binary.
  /// Returns the absolute path of the installed binary.
  Future<String> downloadAndInstall(
    RcloneRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    final tmpDir = await getTemporaryDirectory();
    final zipPath = '${tmpDir.path}/rclone_update.zip';

    // Stream-download the zip
    final req = http.Request('GET', Uri.parse(release.downloadUrl));
    final streamed =
        await _client.send(req).timeout(const Duration(minutes: 10));

    int received = 0;
    final sink = File(zipPath).openWrite();
    await for (final chunk in streamed.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (release.sizeBytes > 0) {
        onProgress?.call(received / release.sizeBytes);
      }
    }
    await sink.close();

    // Extract the rclone binary from the zip
    final zipBytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(zipBytes);

    final destDir = await getApplicationDocumentsDirectory();
    final binaryPath = '${destDir.path}/rclone';

    ArchiveFile? entry;
    for (final f in archive.files) {
      if (f.isFile && (f.name.endsWith('/rclone') || f.name == 'rclone')) {
        entry = f;
        break;
      }
    }
    if (entry == null) {
      throw Exception('rclone binary not found inside the zip archive');
    }

    await File(binaryPath).writeAsBytes(entry.content as List<int>);

    // Make executable
    await Process.run('chmod', ['755', binaryPath]);

    // Cleanup temp zip
    try {
      await File(zipPath).delete();
    } catch (_) {}

    return binaryPath;
  }

  void dispose() => _client.close();
}