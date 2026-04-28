import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/rclone_providers.dart';
import '../files/file_browser_screen.dart';
import 'remote_form_screen.dart';

class RemotesScreen extends ConsumerWidget {
  const RemotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remotesAsync = ref.watch(remotesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remotes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(remotesProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddRemote(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add Remote'),
      ),
      body: remotesAsync.when(
        data: (remotes) {
          if (remotes.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No remotes configured',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _openAddRemote(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Add your first remote'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: remotes.length,
            itemBuilder: (ctx, i) =>
                _RemoteTile(name: remotes[i], ref: ref),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 8),
              Text(e.toString()),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(remotesProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openAddRemote(BuildContext context, WidgetRef ref) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RemoteFormScreen(
          onSaved: () => ref.invalidate(remotesProvider),
        ),
      ),
    );
  }
}

class _RemoteTile extends ConsumerWidget {
  final String name;
  final WidgetRef ref;
  const _RemoteTile({required this.name, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef widgetRef) {
    final detailAsync = widgetRef.watch(remoteDetailProvider(name));

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(
            _iconForType(detailAsync.valueOrNull?.type),
          ),
        ),
        title: Text(name),
        subtitle: detailAsync.when(
          data: (r) => Text(r.type),
          loading: () => const Text('Loading…'),
          error: (e, st) => const Text('Unknown type'),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) =>
              _handleAction(context, action, widgetRef),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'browse', child: Text('Browse')),
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: () => _browse(context),
      ),
    );
  }

  void _browse(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileBrowserScreen(rootPath: '$name:'),
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    String action,
    WidgetRef widgetRef,
  ) async {
    switch (action) {
      case 'browse':
        _browse(context);
      case 'edit':
        final detail = widgetRef.read(remoteDetailProvider(name)).valueOrNull;
        if (detail == null) return;
        if (context.mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RemoteFormScreen(
                existing: detail,
                onSaved: () => widgetRef.invalidate(remotesProvider),
              ),
            ),
          );
        }
      case 'delete':
        final confirmed = await _confirmDelete(context);
        if (confirmed == true) {
          try {
            await widgetRef.read(rcloneApiProvider).deleteRemote(name);
            widgetRef.invalidate(remotesProvider);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e')),
              );
            }
          }
        }
    }
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Remote'),
        content: Text('Delete "$name"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  IconData _iconForType(String? type) {
    switch (type?.toLowerCase()) {
      case 'drive':
        return Icons.add_to_drive;
      case 's3':
        return Icons.cloud;
      case 'dropbox':
        return Icons.folder_special;
      case 'onedrive':
        return Icons.cloud_circle;
      case 'sftp':
        return Icons.terminal;
      case 'ftp':
        return Icons.lan;
      case 'local':
        return Icons.folder;
      default:
        return Icons.cloud_queue;
    }
  }
}
