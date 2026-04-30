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
  static const _githubHeaders = {'Accept': 'application/vnd.github.v3+json'};

  // rclone-current always resolves to the latest stable linux-arm64 build,
  // which is a static Go binary and runs on Android (no glibc dependency).
  static const _currentDownloadUrl =
      'https://downloads.rclone.org/rclone-current-linux-arm64.zip';

  final http.Client _client;

  RcloneUpdater({http.Client? client}) : _client = client ?? http.Client();

  Future<RcloneRelease> fetchLatestRelease() async {
    // Get the version tag to display to the user
    String version = 'latest';
    try {
      final res = await _client
          .get(Uri.parse(_githubLatest), headers: _githubHeaders)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        version = (jsonDecode(res.body) as Map<String, dynamic>)['tag_name']
            as String;
      }
    } catch (_) {
      // Version label is cosmetic; continue with download URL
    }

    // HEAD request to confirm availability and get file size
    final head = await _client
        .head(Uri.parse(_currentDownloadUrl))
        .timeout(const Duration(seconds: 20));

    if (head.statusCode != 200) {
      throw Exception(
        'rclone download server returned ${head.statusCode}',
      );
    }

    final sizeBytes =
        int.tryParse(head.headers['content-length'] ?? '') ?? 0;

    return RcloneRelease(
      version: version,
      downloadUrl: _currentDownloadUrl,
      sizeBytes: sizeBytes,
    );
  }

  /// Downloads and extracts the rclone binary. Returns its absolute path.
  /// Caller is responsible for setting the executable bit via native code.
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

    // Cleanup temp zip
    try {
      await File(zipPath).delete();
    } catch (_) {}

    return binaryPath;
  }

  void dispose() => _client.close();
}