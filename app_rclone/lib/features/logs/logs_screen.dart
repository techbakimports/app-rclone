import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/rclone_providers.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _scrollCtrl = ScrollController();
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_autoScroll && _scrollCtrl.hasClients) {
      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logsAsync = ref.watch(logsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daemon Logs'),
        actions: [
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
              size: 20,
            ),
            tooltip: _autoScroll ? 'Auto-scroll on' : 'Auto-scroll off',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 20),
            tooltip: 'Copy all',
            onPressed: () {
              final lines = logsAsync.valueOrNull ?? [];
              Clipboard.setData(ClipboardData(text: lines.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copied to clipboard')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep, size: 20),
            tooltip: 'Clear logs',
            onPressed: () => ref.read(rcloneServiceProvider).clearLogs(),
          ),
        ],
      ),
      body: logsAsync.when(
        data: (lines) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
          if (lines.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.article_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('No logs yet', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is UserScrollNotification) {
                // User scrolled manually — disable auto-scroll
                final atBottom = _scrollCtrl.position.pixels >=
                    _scrollCtrl.position.maxScrollExtent - 40;
                if (_autoScroll != atBottom) {
                  setState(() => _autoScroll = atBottom);
                }
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: lines.length,
              itemBuilder: (_, i) => _LogLine(line: lines[i]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
      ),
    );
  }
}

class _LogLine extends StatelessWidget {
  final String line;
  const _LogLine({required this.line});

  @override
  Widget build(BuildContext context) {
    Color color;
    if (line.contains('ERROR') || line.contains('FATAL')) {
      color = Colors.red[300]!;
    } else if (line.contains('WARN')) {
      color = Colors.orange[300]!;
    } else if (line.contains('DEBUG')) {
      color = Colors.grey;
    } else {
      color = const Color(0xFFCCCCCC);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        line,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: color,
          height: 1.4,
        ),
      ),
    );
  }
}
