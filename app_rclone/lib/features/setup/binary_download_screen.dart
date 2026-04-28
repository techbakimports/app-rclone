import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/rclone_providers.dart';
import '../../core/rclone/rclone_updater.dart';
import '../../app.dart';

class BinaryDownloadScreen extends ConsumerStatefulWidget {
  const BinaryDownloadScreen({super.key});

  @override
  ConsumerState<BinaryDownloadScreen> createState() =>
      _BinaryDownloadScreenState();
}

class _BinaryDownloadScreenState extends ConsumerState<BinaryDownloadScreen> {
  RcloneRelease? _release;
  double _progress = 0;
  String _statusText = 'Checking latest rclone version…';
  bool _hasError = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _fetchRelease();
  }

  Future<void> _fetchRelease() async {
    setState(() {
      _hasError = false;
      _busy = true;
      _statusText = 'Checking latest rclone version…';
    });
    final updater = RcloneUpdater();
    try {
      final release = await updater.fetchLatestRelease();
      if (mounted) {
        setState(() {
          _release = release;
          _busy = false;
          _statusText = 'Ready to download ${release.version} (${release.sizeMb})';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _busy = false;
          _statusText = 'Failed to check: $e';
        });
      }
    } finally {
      updater.dispose();
    }
  }

  Future<void> _download() async {
    if (_release == null || _busy) return;
    setState(() {
      _busy = true;
      _hasError = false;
      _progress = 0;
      _statusText = 'Downloading rclone ${_release!.version}…';
    });
    final updater = RcloneUpdater();
    try {
      final binaryPath = await updater.downloadAndInstall(
        _release!,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
              _statusText =
                  'Downloading… ${(p * 100).toStringAsFixed(0)}%';
            });
          }
        },
      );
      if (mounted) {
        setState(() => _statusText = 'Installing…');
        ref.read(binaryStatusProvider.notifier).markReady(binaryPath);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _busy = false;
          _statusText = 'Download failed: $e';
        });
      }
    } finally {
      updater.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo / icon with neon glow
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.card,
                    border: Border.all(color: AppColors.neonGreen, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.neonGreen.withAlpha(80),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.cloud_sync,
                    size: 48,
                    color: AppColors.neonGreen,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'RCLONEAPP',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    color: AppColors.neonGreen,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'by TechKBak Solutions',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'The rclone binary must be downloaded once before the app can function. '
                  'It will be stored locally and updated independently of the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: 40),
                if (_busy && _progress > 0) ...[
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 12),
                ] else if (_busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                ],
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _statusText,
                    key: ValueKey(_statusText),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _hasError ? cs.error : cs.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                if (!_busy)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _release != null ? _download : _fetchRelease,
                      icon: Icon(
                        _release != null ? Icons.download : Icons.refresh,
                      ),
                      label: Text(
                        _release != null
                            ? 'Download & Install'
                            : 'Retry',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
