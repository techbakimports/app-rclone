import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/file_item.dart';
import '../../core/providers/rclone_providers.dart';
import '../../app.dart';

// ── File type descriptor ──────────────────────────────────────────────────────

class _FType {
  final Color color;
  final IconData icon;
  const _FType(this.color, this.icon);
}

_FType _typeFor(FileItem item) {
  if (item.isDir) return const _FType(AppColors.neonGreen, Icons.folder);
  switch (item.extension) {
    case 'pdf':
      return const _FType(Color(0xFFE53935), Icons.picture_as_pdf);
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'heic':
    case 'bmp':
    case 'svg':
      return const _FType(Color(0xFFAA00FF), Icons.image);
    case 'mp4':
    case 'mkv':
    case 'avi':
    case 'mov':
    case 'wmv':
    case 'webm':
      return const _FType(Color(0xFF1565C0), Icons.movie);
    case 'mp3':
    case 'flac':
    case 'aac':
    case 'ogg':
    case 'wav':
    case 'm4a':
      return const _FType(Color(0xFFE91E63), Icons.music_note);
    case 'zip':
    case 'tar':
    case 'gz':
    case '7z':
    case 'rar':
    case 'bz2':
    case 'xz':
      return const _FType(Color(0xFFFF6F00), Icons.folder_zip);
    case 'txt':
    case 'md':
    case 'log':
      return const _FType(Color(0xFF5C6BC0), Icons.article);
    case 'dart':
    case 'py':
    case 'js':
    case 'ts':
    case 'kt':
    case 'java':
    case 'c':
    case 'cpp':
    case 'h':
    case 'go':
    case 'rs':
    case 'sh':
    case 'json':
    case 'yaml':
    case 'yml':
    case 'xml':
    case 'toml':
      return const _FType(Color(0xFF00ACC1), Icons.code);
    case 'xlsx':
    case 'xls':
    case 'csv':
    case 'ods':
      return const _FType(Color(0xFF388E3C), Icons.bar_chart);
    case 'pptx':
    case 'ppt':
    case 'odp':
      return const _FType(Color(0xFFF4511E), Icons.slideshow);
    case 'docx':
    case 'doc':
    case 'odt':
    case 'rtf':
      return const _FType(Color(0xFF1976D2), Icons.description);
    case 'apk':
      return const _FType(Color(0xFF43A047), Icons.android);
    default:
      return const _FType(Color(0xFF546E7A), Icons.insert_drive_file);
  }
}

// ── Circular file-type icon ───────────────────────────────────────────────────

class _FileTypeIcon extends StatelessWidget {
  final FileItem item;
  const _FileTypeIcon({required this.item});

  @override
  Widget build(BuildContext context) {
    final ft = _typeFor(item);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ft.color.withAlpha(28),
        border: Border.all(color: ft.color.withAlpha(150), width: 1.5),
      ),
      child: Icon(ft.icon, color: ft.color, size: 22),
    );
  }
}

// ── Breadcrumb bar ────────────────────────────────────────────────────────────

class _BreadcrumbBar extends StatefulWidget {
  final String path;
  final void Function(String) onNavigate;
  const _BreadcrumbBar({required this.path, required this.onNavigate});

  @override
  State<_BreadcrumbBar> createState() => _BreadcrumbBarState();
}

class _BreadcrumbBarState extends State<_BreadcrumbBar> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_BreadcrumbBar old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  List<({String label, String path})> _segments() {
    final colonIdx = widget.path.indexOf(':');
    if (colonIdx < 0) return [(label: widget.path, path: widget.path)];
    final remote = widget.path.substring(0, colonIdx + 1);
    final rest = widget.path.substring(colonIdx + 1);
    final segs = <({String label, String path})>[(label: remote, path: remote)];
    if (rest.isNotEmpty) {
      final parts = rest.split('/').where((s) => s.isNotEmpty).toList();
      var acc = remote;
      for (final part in parts) {
        acc = '$acc$part/';
        segs.add((label: part, path: acc));
      }
    }
    return segs;
  }

  @override
  Widget build(BuildContext context) {
    final segs = _segments();
    return Container(
      height: 36,
      color: AppColors.surface,
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (var i = 0; i < segs.length; i++) ...[
              if (i > 0)
                const Icon(Icons.chevron_right, size: 14, color: AppColors.muted),
              GestureDetector(
                onTap: i == segs.length - 1
                    ? null
                    : () => widget.onNavigate(segs[i].path),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                  child: Text(
                    segs[i].label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: i == segs.length - 1
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: i == segs.length - 1
                          ? AppColors.neonGreen
                          : AppColors.muted,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Pane state ────────────────────────────────────────────────────────────────

class _PaneState {
  String currentPath;
  final List<String> history = [];

  _PaneState(String path) : currentPath = path;

  void navigate(String path) {
    history.add(currentPath);
    currentPath = path;
  }

  bool goBack() {
    if (history.isEmpty) return false;
    currentPath = history.removeLast();
    return true;
  }

  // Short label for the tab chip
  String get label {
    final colon = currentPath.indexOf(':');
    if (colon < 0) {
      return currentPath.length > 10
          ? currentPath.substring(0, 10)
          : currentPath;
    }
    final tail = currentPath.substring(colon + 1);
    final parts = tail.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return currentPath.substring(0, colon + 1);
    final last = parts.last;
    return last.length > 12 ? '…${last.substring(last.length - 10)}' : last;
  }
}

// ── Tab strip ─────────────────────────────────────────────────────────────────

class _TabStrip extends StatefulWidget {
  final List<_PaneState> panes;
  final int active;
  final void Function(int) onSelect;
  final void Function(int) onClose;
  final VoidCallback onAdd;

  const _TabStrip({
    required this.panes,
    required this.active,
    required this.onSelect,
    required this.onClose,
    required this.onAdd,
  });

  @override
  State<_TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<_TabStrip> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(_TabStrip old) {
    super.didUpdateWidget(old);
    // Scroll active tab into view when it changes.
    if (old.active != widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            (widget.active * 108.0).clamp(0, _scroll.position.maxScrollExtent),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      color: AppColors.bg,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
              child: Row(
                children: [
                  for (var i = 0; i < widget.panes.length; i++)
                    _TabChip(
                      label: widget.panes[i].label,
                      isActive: i == widget.active,
                      canClose: widget.panes.length > 1,
                      onTap: () => widget.onSelect(i),
                      onClose: () => widget.onClose(i),
                    ),
                ],
              ),
            ),
          ),
          // Add-pane button
          InkWell(
            onTap: widget.onAdd,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Icon(Icons.add, size: 18, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool canClose;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _TabChip({
    required this.label,
    required this.isActive,
    required this.canClose,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        constraints: const BoxConstraints(minWidth: 64, maxWidth: 140),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.neonGreen.withAlpha(22)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive
                ? AppColors.neonGreen.withAlpha(100)
                : const Color(0xFF2E2E2E),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      isActive ? FontWeight.w700 : FontWeight.w400,
                  color:
                      isActive ? AppColors.neonGreen : AppColors.muted,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            if (canClose) ...[
              const SizedBox(width: 4),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: isActive
                      ? AppColors.neonGreen.withAlpha(180)
                      : AppColors.muted.withAlpha(120),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Single pane ───────────────────────────────────────────────────────────────

class _SinglePane extends ConsumerWidget {
  final int index;
  final _PaneState pane;
  final void Function(int paneIdx, VoidCallback fn) onSetState;

  const _SinglePane({
    required this.index,
    required this.pane,
    required this.onSetState,
  });

  void _navigate(String path) =>
      onSetState(index, () => pane.navigate(path));

  void _jumpTo(String path) => onSetState(index, () {
        pane.history.add(pane.currentPath);
        pane.currentPath = path;
      });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = pane.currentPath;
    final listAsync = ref.watch(directoryListingProvider(path));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BreadcrumbBar(path: path, onNavigate: _jumpTo),
        const Divider(height: 1, thickness: 1),
        Expanded(
          child: listAsync.when(
            data: (items) {
              if (items.isEmpty) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open,
                          size: 56, color: AppColors.muted),
                      SizedBox(height: 8),
                      Text('Pasta vazia',
                          style: TextStyle(
                              color: AppColors.muted, fontSize: 13)),
                    ],
                  ),
                );
              }
              final sorted = [...items]..sort((a, b) {
                  if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
                  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
                });
              return ListView.separated(
                itemCount: sorted.length,
                separatorBuilder: (context, index) => const Divider(
                  height: 1,
                  indent: 68,
                  thickness: 0.5,
                ),
                itemBuilder: (ctx, i) => _FileTile(
                  item: sorted[i],
                  currentPath: path,
                  onNavigate: _navigate,
                  onRefresh: () =>
                      ref.invalidate(directoryListingProvider(path)),
                ),
              );
            },
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: Color(0xFFFF5252)),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(e.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () =>
                        ref.invalidate(directoryListingProvider(path)),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tentar novamente'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Main screen ───────────────────────────────────────────────────────────────

class FileBrowserScreen extends ConsumerStatefulWidget {
  final String rootPath;
  const FileBrowserScreen({super.key, required this.rootPath});

  @override
  ConsumerState<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends ConsumerState<FileBrowserScreen> {
  late final List<_PaneState> _panes;
  int _active = 0;

  @override
  void initState() {
    super.initState();
    _panes = [_PaneState(widget.rootPath)];
  }

  void _onSetState(int paneIdx, VoidCallback fn) =>
      setState(() { fn(); _active = paneIdx; });

  void _addPane() => setState(() {
        // New pane opens at the same location as the current one.
        _panes.add(_PaneState(_panes[_active].currentPath));
        _active = _panes.length - 1;
      });

  void _closePane(int idx) {
    if (_panes.length == 1) return;
    setState(() {
      _panes.removeAt(idx);
      _active = _active.clamp(0, _panes.length - 1);
    });
  }

  String get _title {
    final path = _panes[_active].currentPath;
    final colon = path.indexOf(':');
    if (colon < 0) return path;
    final parts = path
        .substring(colon + 1)
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? path.substring(0, colon + 1) : parts.last;
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return PopScope(
      canPop: _panes[_active].history.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(() => _panes[_active].goBack());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_title, overflow: TextOverflow.ellipsis),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (!_panes[_active].goBack()) {
                Navigator.pop(context);
              } else {
                setState(() {});
              }
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(
                directoryListingProvider(_panes[_active].currentPath),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: () => _mkdir(context),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(38),
            child: _TabStrip(
              panes: _panes,
              active: _active,
              onSelect: (i) => setState(() => _active = i),
              onClose: _closePane,
              onAdd: _addPane,
            ),
          ),
        ),
        body: landscape ? _buildDual() : _buildSingle(),
      ),
    );
  }

  // Portrait: show only the active pane (IndexedStack preserves scroll state).
  Widget _buildSingle() {
    return IndexedStack(
      index: _active,
      children: [
        for (var i = 0; i < _panes.length; i++)
          _SinglePane(index: i, pane: _panes[i], onSetState: _onSetState),
      ],
    );
  }

  // Landscape: show active pane + the adjacent pane side by side.
  // Falls back to single pane if there is only one.
  Widget _buildDual() {
    if (_panes.length == 1) {
      return _SinglePane(index: 0, pane: _panes[0], onSetState: _onSetState);
    }
    final rightIdx = (_active + 1) % _panes.length;
    return Row(
      children: [
        Expanded(
          child: _SinglePane(
              index: _active, pane: _panes[_active], onSetState: _onSetState),
        ),
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: AppColors.muted.withAlpha(50),
        ),
        Expanded(
          child: _SinglePane(
              index: rightIdx,
              pane: _panes[rightIdx],
              onSetState: _onSetState),
        ),
      ],
    );
  }

  Future<void> _mkdir(BuildContext context) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova pasta'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nome da pasta'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    final path = _panes[_active].currentPath;
    final newPath = path.endsWith('/') ? '$path$name' : '$path/$name';
    try {
      await ref.read(rcloneApiProvider).createDirectory(newPath);
      ref.invalidate(directoryListingProvider(path));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }
}

// ── File tile ─────────────────────────────────────────────────────────────────

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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      leading: _FileTypeIcon(item: item),
      title: Text(
        item.name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: item.isDir
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Text(item.sizeFormatted,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted)),
                  if (item.modTime != null) ...[
                    const Spacer(),
                    Text(
                      _fmtDate(item.modTime!),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.muted),
                    ),
                  ],
                ],
              ),
            ),
      onTap: item.isDir ? () => onNavigate(_fullPath) : null,
      trailing: PopupMenuButton<String>(
        onSelected: (v) => _handleAction(context, ref, v),
        itemBuilder: (_) => [
          if (!item.isDir) ...[
            const PopupMenuItem(
              value: 'copy',
              child: ListTile(
                  dense: true,
                  leading: Icon(Icons.copy),
                  title: Text('Copiar')),
            ),
            const PopupMenuItem(
              value: 'move',
              child: ListTile(
                  dense: true,
                  leading: Icon(Icons.drive_file_move),
                  title: Text('Mover')),
            ),
          ],
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.delete,
                  color: Theme.of(context).colorScheme.error),
              title: Text(
                item.isDir ? 'Excluir pasta' : 'Excluir',
                style:
                    TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(
      BuildContext context, WidgetRef ref, String action) async {
    final api = ref.read(rcloneApiProvider);
    switch (action) {
      case 'copy':
      case 'move':
        final dest = await _promptDest(context);
        if (dest == null || !context.mounted) return;
        try {
          if (action == 'copy') {
            await api.copyFile(_fullPath, dest);
          } else {
            await api.moveFile(_fullPath, dest);
            onRefresh();
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content:
                  Text(action == 'copy' ? 'Cópia concluída' : 'Movido'),
            ));
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Erro: $e'),
              backgroundColor: const Color(0xFFFF5252),
            ));
          }
        }
      case 'delete':
        final ok = await _confirmDelete(context);
        if (ok != true || !context.mounted) return;
        try {
          if (item.isDir) {
            await api.purgeDirectory(_fullPath);
          } else {
            await api.deleteFile(_fullPath);
          }
          onRefresh();
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Erro: $e'),
              backgroundColor: const Color(0xFFFF5252),
            ));
          }
        }
    }
  }

  Future<String?> _promptDest(BuildContext context) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Destino'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: 'remote:pasta/destino'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
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
        title: Text('Excluir ${item.isDir ? "pasta" : "arquivo"}'),
        content:
            Text('Excluir "${item.name}"? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF5252)),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}