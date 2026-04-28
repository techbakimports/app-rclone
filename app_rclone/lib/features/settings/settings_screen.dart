import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/rclone_providers.dart';
import '../../core/rclone/rclone_updater.dart';
import '../logs/logs_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _bwCtrl = TextEditingController();

  @override
  void dispose() {
    _bwCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final versionAsync = ref.watch(rcloneVersionProvider);
    final bwAsync = ref.watch(bandwidthLimitProvider);
    final autoStart = ref.watch(autoStartProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // ── Daemon ────────────────────────────────────────────────────
          _SectionHeader('Daemon'),
          SwitchListTile(
            secondary: const Icon(Icons.play_circle_outline),
            title: const Text('Auto-start daemon'),
            subtitle: const Text('Start rclone when the app opens'),
            value: autoStart,
            onChanged: (_) => ref.read(autoStartProvider.notifier).toggle(),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('rclone version'),
            trailing: versionAsync.when(
              data: (v) => Text(v, style: const TextStyle(color: Colors.grey)),
              loading: () => const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (_, _) => const Text('N/A'),
            ),
          ),
          const Divider(),

          // ── Updates ───────────────────────────────────────────────────
          _SectionHeader('Binary'),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Update rclone binary'),
            subtitle: const Text('Download latest from GitHub Releases'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showUpdateSheet(context),
          ),
          const Divider(),

          // ── Transfer ─────────────────────────────────────────────────
          _SectionHeader('Transfer'),
          bwAsync.when(
            data: (bw) => ListTile(
              leading: const Icon(Icons.speed),
              title: const Text('Bandwidth limit'),
              subtitle: Text(bw),
              onTap: () => _showBandwidthDialog(context, bw),
            ),
            loading: () => const ListTile(
              leading: Icon(Icons.speed),
              title: Text('Bandwidth limit'),
              subtitle: Text('Loading…'),
            ),
            error: (_, _) => const ListTile(
              leading: Icon(Icons.speed),
              title: Text('Bandwidth limit'),
            ),
          ),
          const Divider(),

          // ── Cache & VFS ───────────────────────────────────────────────
          _SectionHeader('Cache & VFS'),
          ListTile(
            leading: const Icon(Icons.cached),
            title: const Text('Forget VFS cache'),
            subtitle: const Text('Force refresh of cached file listings'),
            onTap: () async {
              try {
                await ref.read(rcloneApiProvider).vfsForgetAll();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('VFS cache cleared')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
          ),
          const Divider(),

          // ── Diagnostics ───────────────────────────────────────────────
          _SectionHeader('Diagnostics'),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('View daemon logs'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LogsScreen()),
            ),
          ),
          const Divider(),

          // ── Config ────────────────────────────────────────────────────
          _SectionHeader('Config'),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Config file path'),
            subtitle: Text(
              ref.watch(rcloneServiceProvider).configPath ?? 'Not initialized',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          const Divider(),

          // ── About ─────────────────────────────────────────────────────
          _SectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About RcloneApp'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAboutDialog(context),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0F0F0F),
                  border: Border.all(color: const Color(0xFF39FF14), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF39FF14).withAlpha(70),
                      blurRadius: 18,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.cloud_sync,
                  size: 34,
                  color: Color(0xFF39FF14),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'RcloneApp',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'v1.0.0',
                style: TextStyle(color: Color(0xFF888888), fontSize: 13),
              ),
              const SizedBox(height: 20),
              const Text(
                'Interface gráfica completa para o rclone no Android. '
                'Gerencie backups e transferências para qualquer nuvem '
                'suportada pelo rclone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFCCCCCC),
                  height: 1.5,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                'Desenvolvido por',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF888888),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'TechKBak Solutions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFAA00FF),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBandwidthDialog(BuildContext context, String current) {
    _bwCtrl.text = current == 'off' ? '' : current;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bandwidth limit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _bwCtrl,
              decoration: const InputDecoration(
                labelText: 'Rate',
                hintText: 'e.g. 10M or 1G or off',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Examples: 10M (10 MB/s), 1G (1 GB/s), off (unlimited)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final rate =
                  _bwCtrl.text.trim().isEmpty ? 'off' : _bwCtrl.text.trim();
              try {
                await ref.read(rcloneApiProvider).setBandwidthLimit(rate);
                ref.invalidate(bandwidthLimitProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _showUpdateSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _UpdateSheet(),
    );
  }
}

// ── Update bottom sheet ───────────────────────────────────────────────────────

class _UpdateSheet extends ConsumerStatefulWidget {
  const _UpdateSheet();

  @override
  ConsumerState<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends ConsumerState<_UpdateSheet> {
  RcloneRelease? _release;
  double _progress = 0;
  String _status = 'Checking for latest version…';
  bool _hasError = false;
  bool _busy = true;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _checkLatest();
  }

  Future<void> _checkLatest() async {
    setState(() {
      _busy = true;
      _hasError = false;
      _status = 'Checking for latest version…';
    });
    final updater = RcloneUpdater();
    try {
      final release = await updater.fetchLatestRelease();
      if (mounted) {
        setState(() {
          _release = release;
          _busy = false;
          _status =
              '${release.version} available (${release.sizeMb})';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _busy = false;
          _status = 'Check failed: $e';
        });
      }
    } finally {
      updater.dispose();
    }
  }

  Future<void> _update() async {
    if (_release == null || _busy) return;
    setState(() {
      _busy = true;
      _hasError = false;
      _progress = 0;
      _status = 'Downloading ${_release!.version}…';
    });

    // Stop daemon before replacing binary
    final wasDaemonRunning = ref.read(daemonProvider).isRunning;
    if (wasDaemonRunning) await ref.read(daemonProvider.notifier).stop();

    final updater = RcloneUpdater();
    try {
      final binaryPath = await updater.downloadAndInstall(
        _release!,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _progress = p;
              _status =
                  'Downloading… ${(p * 100).toStringAsFixed(0)}%';
            });
          }
        },
      );
      ref.read(binaryStatusProvider.notifier).markReady(binaryPath);
      if (mounted) {
        setState(() {
          _busy = false;
          _done = true;
          _status = '${_release!.version} installed successfully';
        });
      }
      // Restart daemon if it was running
      if (wasDaemonRunning) ref.read(daemonProvider.notifier).start();
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _busy = false;
          _status = 'Download failed: $e';
        });
      }
      if (wasDaemonRunning) ref.read(daemonProvider.notifier).start();
    } finally {
      updater.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Update rclone',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          if (_busy && _progress > 0) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 12),
          ] else if (_busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          Text(
            _status,
            style: TextStyle(
              color: _done
                  ? cs.primary
                  : _hasError
                      ? cs.error
                      : cs.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          if (!_busy)
            _done
                ? FilledButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check),
                    label: const Text('Done'),
                  )
                : FilledButton.icon(
                    onPressed: _release != null ? _update : _checkLatest,
                    icon: Icon(
                        _release != null ? Icons.download : Icons.refresh),
                    label:
                        Text(_release != null ? 'Download & Install' : 'Retry'),
                  ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}
