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
  static const _githubApi =
      'https://api.github.com/repos/rclone/rclone/releases/latest';

  final http.Client _client;

  RcloneUpdater({http.Client? client}) : _client = client ?? http.Client();

  Future<RcloneRelease> fetchLatestRelease() async {
    final res = await _client
        .get(
          Uri.parse(_githubApi),
          headers: {'Accept': 'application/vnd.github.v3+json'},
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception('GitHub API returned ${res.statusCode}');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final version = data['tag_name'] as String;
    final assets = (data['assets'] as List).cast<Map<String, dynamic>>();

    final asset = assets.firstWhere(
      (a) {
        final name = a['name'] as String;
        return name.endsWith('.zip') &&
            (name.contains('android-arm64') || name.contains('linux-arm64'));
      },
      orElse: () => throw Exception('No ARM64 asset found in $version'),
    );

    return RcloneRelease(
      version: version,
      downloadUrl: asset['browser_download_url'] as String,
      sizeBytes: asset['size'] as int,
    );
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
