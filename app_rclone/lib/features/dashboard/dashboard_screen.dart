import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/rclone_providers.dart';
import '../../core/models/job.dart';
import '../../app.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _autoStartTriggered = false;

  @override
  Widget build(BuildContext context) {
    final daemon = ref.watch(daemonProvider);
    final statsAsync = ref.watch(transferStatsProvider);
    final jobsAsync = ref.watch(jobsProvider);
    final versionAsync = ref.watch(rcloneVersionProvider);
    final autoStart = ref.watch(autoStartProvider);

    if (!_autoStartTriggered) {
      _autoStartTriggered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (autoStart && !daemon.isRunning && !daemon.isBusy) {
          ref.read(daemonProvider.notifier).start();
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('DASHBOARD')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(daemonProvider.notifier).checkRunning(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DaemonCard(daemon: daemon),
            const SizedBox(height: 16),
            versionAsync.when(
              data: (v) => _InfoTile(label: 'rclone version', value: v),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            if (daemon.isRunning) ...[
              const SizedBox(height: 16),
              statsAsync.when(
                data: (s) => _StatsCard(stats: s),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorTile(message: e.toString()),
              ),
              const SizedBox(height: 16),
              jobsAsync.when(
                data: (jobs) => _ActiveJobsCard(jobs: jobs),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorTile(message: e.toString()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Daemon card ───────────────────────────────────────────────────────────────

class _DaemonCard extends ConsumerWidget {
  final DaemonState daemon;
  const _DaemonCard({required this.daemon});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (daemon.status) {
      case DaemonStatus.running:
        statusColor = AppColors.neonGreen;
        statusLabel = 'Running';
        statusIcon = Icons.radio_button_checked;
      case DaemonStatus.starting:
        statusColor = AppColors.violet;
        statusLabel = 'Starting…';
        statusIcon = Icons.hourglass_top;
      case DaemonStatus.stopped:
        statusColor = AppColors.muted;
        statusLabel = 'Stopped';
        statusIcon = Icons.radio_button_unchecked;
      case DaemonStatus.error:
        statusColor = scheme.error;
        statusLabel = 'Error';
        statusIcon = Icons.error_outline;
    }

    // Neon glow border when running
    final bool glowing = daemon.status == DaemonStatus.running;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: glowing ? AppColors.neonGreen : const Color(0xFF2E2E2E),
          width: glowing ? 1.5 : 1,
        ),
        boxShadow: glowing
            ? [
                BoxShadow(
                  color: AppColors.neonGreen.withAlpha(50),
                  blurRadius: 14,
                  spreadRadius: 0,
                ),
              ]
            : [],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Pulsing dot
              _StatusDot(color: statusColor, pulsing: daemon.isRunning),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'RCLONE DAEMON',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.5,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Icon(statusIcon, color: statusColor, size: 28),
            ],
          ),
          if (daemon.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              daemon.errorMessage!,
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: daemon.isRunning
                ? OutlinedButton.icon(
                    onPressed: daemon.isBusy
                        ? null
                        : () => ref.read(daemonProvider.notifier).stop(),
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Stop'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(color: scheme.error),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: daemon.isBusy
                        ? null
                        : () => ref.read(daemonProvider.notifier).start(),
                    icon: daemon.isBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow, size: 18),
                    label: Text(daemon.isBusy ? 'Starting…' : 'Start'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  final Color color;
  final bool pulsing;
  const _StatusDot({required this.color, required this.pulsing});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pulsing) {
      _ctrl.stop();
      return _dot(1.0);
    }
    _ctrl.repeat(reverse: true);
    return AnimatedBuilder(
      animation: _scale,
      builder: (_, _) => _dot(_scale.value),
    );
  }

  Widget _dot(double scale) {
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
          boxShadow: widget.pulsing
              ? [
                  BoxShadow(
                    color: widget.color.withAlpha(120),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
      ),
    );
  }
}

// ── Stats card ────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final TransferStats stats;
  const _StatsCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TRANSFER STATS',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.5,
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (stats.totalBytes > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: stats.progressFraction,
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatItem(
                  label: 'SPEED',
                  value: stats.speedFormatted,
                  icon: Icons.speed,
                ),
                _StatItem(
                  label: 'TRANSFERRED',
                  value: stats.bytesFormatted,
                  icon: Icons.swap_horiz,
                ),
                _StatItem(
                  label: 'FILES',
                  value: '${stats.transfers}',
                  icon: Icons.file_copy_outlined,
                ),
                _StatItem(
                  label: 'ERRORS',
                  value: '${stats.errors}',
                  icon: Icons.error_outline,
                  highlight: stats.errors > 0,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool highlight;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? Theme.of(context).colorScheme.error
        : AppColors.neonGreen;
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: color,
            fontSize: 13,
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

// ── Active jobs card ──────────────────────────────────────────────────────────

class _ActiveJobsCard extends StatelessWidget {
  final List<RcloneJob> jobs;
  const _ActiveJobsCard({required this.jobs});

  @override
  Widget build(BuildContext context) {
    final active = jobs.where((j) => j.isActive).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'ACTIVE JOBS',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.5,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                if (active.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.neonGreen.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.neonGreen.withAlpha(80),
                      ),
                    ),
                    child: Text(
                      '${active.length}',
                      style: const TextStyle(
                        color: AppColors.neonGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            if (active.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'No active jobs',
                  style: TextStyle(color: AppColors.muted),
                ),
              )
            else
              ...active.map(
                (j) => Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.sync,
                            size: 14,
                            color: AppColors.neonGreen,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Job #${j.id}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          if (j.stats != null)
                            Text(
                              j.stats!.speedFormatted,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.neonGreen,
                              ),
                            ),
                        ],
                      ),
                      if (j.stats != null) ...[
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: j.stats!.progressFraction,
                            minHeight: 3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Misc ──────────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        dense: true,
        leading:
            const Icon(Icons.terminal, size: 18, color: AppColors.neonGreen),
        title: Text(label, style: const TextStyle(fontSize: 13)),
        trailing: Text(
          value,
          style: const TextStyle(
            color: AppColors.neonGreen,
            fontFamily: 'monospace',
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  final String message;
  const _ErrorTile({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: ListTile(
        leading: const Icon(Icons.error_outline),
        title: Text(message, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}
