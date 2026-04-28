import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/rclone_providers.dart';
import '../../app.dart';

class FileBrowserScreen extends ConsumerStatefulWidget {
  final String rootPath;

  const FileBrowserScreen({super.key, required this.rootPath});

  @override
  ConsumerState<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends ConsumerState<FileBrowserScreen> {
  late String _currentPath;
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _currentPath = widget.rootPath;
  }

  void _navigate(String path) {
    setState(() {
      _history.add(_currentPath);
      _currentPath = path;
    });
  }

  bool _goBack() {
    if (_history.isEmpty) return false;
    setState(() {
      _currentPath = _history.removeLast();
    });
    return true;
  }

  String get _displayPath {
    if (_currentPath.endsWith(':')) return _currentPath;
    return _currentPath;
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(directoryListingProvider(_currentPath));

    return PopScope(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _displayPath,
            overflow: TextOverflow.ellipsis,
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (!_goBack()) Navigator.pop(context);
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () =>
                  ref.invalidate(directoryListingProvider(_currentPath)),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => _handleDirAction(context, v),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'mkdir',
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.create_new_folder),
                    title: Text('New folder'),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: listAsync.when(
          data: (items) {
            final files = items.cast<FileItem>();
            if (files.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.folder_open, size: 64, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('Empty directory', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              );
            }
            final sorted = [...files]..sort((a, b) {
                if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
              });
            return ListView.builder(
              itemCount: sorted.length,
              itemBuilder: (ctx, i) => _FileTile(
                item: sorted[i],
                currentPath: _currentPath,
                onNavigate: _navigate,
                onRefresh: () => ref.invalidate(
                  directoryListingProvider(_currentPath),
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(e.toString(), textAlign: TextAlign.center),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(
                    directoryListingProvider(_currentPath),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleDirAction(BuildContext context, String action) async {
    if (action == 'mkdir') {
      final name = await _promptName(context, 'New folder name');
      if (name == null || name.isEmpty) return;
      final newPath = _currentPath.endsWith('/')
          ? '$_currentPath$name'
          : '$_currentPath/$name';
      try {
        await ref.read(rcloneApiProvider).createDirectory(newPath);
        ref.invalidate(directoryListingProvider(_currentPath));
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  Future<String?> _promptName(BuildContext context, String label) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _FileTile extends ConsumerWidget {
  final FileItem item;
  final String currentPath;
  final void Function(String) onNavigate;
  final VoidCallback onRefresh;

  const _FileTile({
    required this.item,
    required this.currentPath,
    required this.onNavigate,
    required this.onRefresh,
  });

  String get _fullPath {
    final base = currentPath.endsWith('/') ? currentPath : '$currentPath/';
    return '$base${item.name}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(
        item.isDir ? Icons.folder : _fileIcon(item.extension),
        color: item.isDir ? AppColors.neonGreen : AppColors.muted,
      ),
      title: Text(item.name),
      subtitle: item.isDir
          ? null
          : Text(
              '${item.sizeFormatted}'
              '${item.modTime != null ? "  ·  ${_formatDate(item.modTime!)}" : ""}',
              style: const TextStyle(fontSize: 12),
            ),
      onTap: item.isDir ? () => onNavigate(_fullPath) : null,
      trailing: PopupMenuButton<String>(
        onSelected: (action) => _handleAction(context, ref, action),
        itemBuilder: (_) => [
          if (!item.isDir)
            const PopupMenuItem(
              value: 'copy',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.copy),
                title: Text('Copy'),
              ),
            ),
          if (!item.isDir)
            const PopupMenuItem(
              value: 'move',
              child: ListTile(
                dense: true,
                leading: Icon(Icons.drive_file_move),
                title: Text('Move'),
              ),
            ),
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
              title: Text(
                item.isDir ? 'Delete folder' : 'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final api = ref.read(rcloneApiProvider);
    switch (action) {
      case 'copy':
      case 'move':
        final dest = await _promptDestination(context);
        if (dest == null) return;
        try {
          if (action == 'copy') {
            await api.copyFile(_fullPath, dest);
          } else {
            await api.moveFile(_fullPath, dest);
            onRefresh();
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${action == "copy" ? "Copy" : "Move"} complete')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
            );
          }
        }
      case 'delete':
        final confirmed = await _confirmDelete(context);
        if (confirmed != true) return;
        try {
          if (item.isDir) {
            await api.purgeDirectory(_fullPath);
          } else {
            await api.deleteFile(_fullPath);
          }
          onRefresh();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
            );
          }
        }
    }
  }

  Future<String?> _promptDestination(BuildContext context) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Destination path'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'remote:path/to/dest',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${item.isDir ? "folder" : "file"}'),
        content: Text('Delete "${item.name}"? This cannot be undone.'),
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

  IconData _fileIcon(String ext) {
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'heic':
        return Icons.image;
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
        return Icons.video_file;
      case 'mp3':
      case 'flac':
      case 'aac':
      case 'ogg':
        return Icons.audio_file;
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
      case 'rar':
        return Icons.folder_zip;
      case 'txt':
      case 'md':
        return Icons.article;
      case 'dart':
      case 'py':
      case 'js':
      case 'ts':
      case 'kt':
      case 'java':
        return Icons.code;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
