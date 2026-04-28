import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/job.dart';
import '../../core/providers/rclone_providers.dart';
import '../../app.dart';

class TransfersScreen extends ConsumerWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobsAsync = ref.watch(jobsProvider);
    final statsAsync = ref.watch(transferStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TRANSFERS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, size: 20),
            tooltip: 'Reset stats',
            onPressed: () => ref.read(rcloneApiProvider).resetStats(),
          ),
        ],
      ),
      body: Column(
        children: [
          statsAsync.when(
            data: (s) => _GlobalStatsBar(stats: s),
            loading: () => const SizedBox(
              height: 3,
              child: LinearProgressIndicator(),
            ),
            error: (_, _) => const SizedBox.shrink(),
          ),
          Expanded(
            child: jobsAsync.when(
              data: (jobs) => _JobList(jobs: jobs),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text(e.toString())),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewJobDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New Job'),
      ),
    );
  }

  void _showNewJobDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewJobSheet(ref: ref),
    );
  }
}

// ── Global stats bar ──────────────────────────────────────────────────────────

class _GlobalStatsBar extends StatelessWidget {
  final TransferStats stats;
  const _GlobalStatsBar({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Stat(label: 'SPEED', value: stats.speedFormatted),
          _Stat(label: 'TRANSFERRED', value: stats.bytesFormatted),
          _Stat(label: 'FILES', value: '${stats.transfers}'),
          _Stat(label: 'ERRORS', value: '${stats.errors}',
              error: stats.errors > 0),
          _Stat(label: 'ELAPSED', value: stats.elapsedTime),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final bool error;
  const _Stat({required this.label, required this.value, this.error = false});

  @override
  Widget build(BuildContext context) {
    final valueColor =
        error ? Theme.of(context).colorScheme.error : AppColors.neonGreen;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: valueColor,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: AppColors.muted,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

// ── Job list ──────────────────────────────────────────────────────────────────

class _JobList extends ConsumerWidget {
  final List<RcloneJob> jobs;
  const _JobList({required this.jobs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (jobs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.swap_horiz, size: 64, color: AppColors.muted),
            SizedBox(height: 8),
            Text(
              'No jobs',
              style: TextStyle(color: AppColors.muted, fontSize: 16),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: jobs.length,
      itemBuilder: (_, i) => _JobCard(job: jobs[i]),
    );
  }
}

// ── Job card ──────────────────────────────────────────────────────────────────

class _JobCard extends ConsumerWidget {
  final RcloneJob job;
  const _JobCard({required this.job});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    Color statusColor;
    IconData statusIcon;
    String statusLabel;

    switch (job.status) {
      case JobStatus.running:
        statusColor = AppColors.neonGreen;
        statusIcon = Icons.sync;
        statusLabel = 'Running';
      case JobStatus.finished:
        statusColor = AppColors.neonGreen;
        statusIcon = Icons.check_circle_outline;
        statusLabel = 'Done';
      case JobStatus.error:
        statusColor = scheme.error;
        statusIcon = Icons.error_outline;
        statusLabel = 'Error';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: job.isActive
              ? AppColors.neonGreen.withAlpha(60)
              : const Color(0xFF2E2E2E),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'Job #${job.id}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: statusColor.withAlpha(80)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (job.isActive) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => ref.read(rcloneApiProvider).stopJob(job.id),
                  child: Icon(
                    Icons.stop_circle_outlined,
                    color: scheme.error,
                    size: 22,
                  ),
                ),
              ],
            ],
          ),
          if (job.stats != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: job.stats!.progressFraction,
                minHeight: 3,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${job.stats!.bytesFormatted} / ${job.stats!.totalBytesFormatted}',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                Text(
                  job.stats!.speedFormatted,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.neonGreen,
                  ),
                ),
              ],
            ),
          ],
          if (job.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                job.error!,
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Started ${_fmt(job.startTime)}',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';
}

// ── New job sheet ─────────────────────────────────────────────────────────────

class _NewJobSheet extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _NewJobSheet({required this.ref});

  @override
  ConsumerState<_NewJobSheet> createState() => _NewJobSheetState();
}

class _NewJobSheetState extends ConsumerState<_NewJobSheet> {
  final _srcCtrl = TextEditingController();
  final _dstCtrl = TextEditingController();
  String _jobType = 'copy';
  bool _submitting = false;

  @override
  void dispose() {
    _srcCtrl.dispose();
    _dstCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'NEW JOB',
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 1.5,
              color: AppColors.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'copy', label: Text('Copy')),
              ButtonSegment(value: 'move', label: Text('Move')),
              ButtonSegment(value: 'sync', label: Text('Sync')),
              ButtonSegment(value: 'bisync', label: Text('Bisync')),
            ],
            selected: {_jobType},
            onSelectionChanged: (v) => setState(() => _jobType = v.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _srcCtrl,
            decoration: const InputDecoration(
              labelText: 'Source',
              hintText: 'remote:path or /local/path',
              prefixIcon: Icon(Icons.arrow_upward, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dstCtrl,
            decoration: const InputDecoration(
              labelText: 'Destination',
              hintText: 'remote:path or /local/path',
              prefixIcon: Icon(Icons.arrow_downward, size: 18),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _startJob,
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Start ${_jobType[0].toUpperCase()}${_jobType.substring(1)}',
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _startJob() async {
    final src = _srcCtrl.text.trim();
    final dst = _dstCtrl.text.trim();
    if (src.isEmpty || dst.isEmpty) return;

    setState(() => _submitting = true);
    final api = ref.read(rcloneApiProvider);
    try {
      final int jobId;
      switch (_jobType) {
        case 'copy':
          jobId = await api.startCopy(src, dst);
        case 'move':
          jobId = await api.startMove(src, dst);
        case 'sync':
          jobId = await api.startSync(src, dst);
        case 'bisync':
          jobId = await api.startBisync(src, dst);
        default:
          return;
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Job #$jobId started')),
        );
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}
