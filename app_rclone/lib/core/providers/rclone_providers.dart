import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../rclone/rclone_service.dart';
import '../rclone/rclone_api.dart';
import '../models/remote.dart';
import '../models/job.dart';
import '../models/file_item.dart';

// ── Singleton services ────────────────────────────────────────────────────────

final rcloneServiceProvider = Provider<RcloneService>((_) => RcloneService());
final rcloneApiProvider = Provider<RcloneApi>((_) => RcloneApi());

// ── Binary availability ───────────────────────────────────────────────────────

enum BinaryStatus { checking, notInstalled, ready }

class BinaryStatusNotifier extends StateNotifier<BinaryStatus> {
  final RcloneService _service;

  BinaryStatusNotifier(this._service) : super(BinaryStatus.checking) {
    _check();
  }

  Future<void> _check() async {
    final ok = await _service.initialize();
    state = ok ? BinaryStatus.ready : BinaryStatus.notInstalled;
  }

  void markReady(String binaryPath) {
    _service.setBinaryPath(binaryPath);
    state = BinaryStatus.ready;
  }
}

final binaryStatusProvider =
    StateNotifierProvider<BinaryStatusNotifier, BinaryStatus>((ref) {
  return BinaryStatusNotifier(ref.watch(rcloneServiceProvider));
});

// ── Auto-start preference ─────────────────────────────────────────────────────

class AutoStartNotifier extends StateNotifier<bool> {
  static const _key = 'auto_start_daemon';

  AutoStartNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_key) ?? true;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, state);
  }
}

final autoStartProvider =
    StateNotifierProvider<AutoStartNotifier, bool>((_) => AutoStartNotifier());

// ── Daemon state ──────────────────────────────────────────────────────────────

enum DaemonStatus { stopped, starting, running, error }

class DaemonState {
  final DaemonStatus status;
  final String? errorMessage;

  const DaemonState({required this.status, this.errorMessage});

  bool get isRunning => status == DaemonStatus.running;
  bool get isBusy => status == DaemonStatus.starting;
}

class DaemonNotifier extends StateNotifier<DaemonState> {
  final RcloneService _service;
  final RcloneApi _api;

  DaemonNotifier(this._service, this._api)
      : super(const DaemonState(status: DaemonStatus.stopped));

  Future<void> start() async {
    if (state.status == DaemonStatus.starting) return;
    state = const DaemonState(status: DaemonStatus.starting);
    try {
      await _service.startDaemon();
      // Poll until the daemon responds or we time out
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(deadline)) {
        if (await _api.ping()) {
          state = const DaemonState(status: DaemonStatus.running);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      state = const DaemonState(
        status: DaemonStatus.error,
        errorMessage: 'Daemon did not respond within 15 seconds',
      );
    } catch (e) {
      state = DaemonState(
        status: DaemonStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> stop() async {
    await _service.stopDaemon();
    state = const DaemonState(status: DaemonStatus.stopped);
  }

  Future<void> checkRunning() async {
    final alive = await _api.ping();
    if (alive && !state.isRunning) {
      state = const DaemonState(status: DaemonStatus.running);
    } else if (!alive && state.isRunning) {
      state = const DaemonState(status: DaemonStatus.stopped);
    }
  }
}

final daemonProvider =
    StateNotifierProvider<DaemonNotifier, DaemonState>((ref) {
  return DaemonNotifier(
    ref.watch(rcloneServiceProvider),
    ref.watch(rcloneApiProvider),
  );
});

// ── Remotes ───────────────────────────────────────────────────────────────────

final remotesProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return ref.watch(rcloneApiProvider).listRemotes();
});

final remoteDetailProvider =
    FutureProvider.autoDispose.family<Remote, String>((ref, name) {
  return ref.watch(rcloneApiProvider).getRemote(name);
});

final providersListProvider =
    FutureProvider.autoDispose<List<RemoteProvider>>((ref) {
  return ref.watch(rcloneApiProvider).listProviders();
});

// ── Jobs (polled every 2 s) ───────────────────────────────────────────────────

final jobsProvider = StreamProvider.autoDispose<List<RcloneJob>>((ref) async* {
  final api = ref.watch(rcloneApiProvider);
  while (true) {
    try {
      yield await api.listJobs();
    } catch (_) {
      yield [];
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
});

// ── Transfer stats (polled every 1 s) ────────────────────────────────────────

final transferStatsProvider =
    StreamProvider.autoDispose<TransferStats>((ref) async* {
  final api = ref.watch(rcloneApiProvider);
  while (true) {
    try {
      yield await api.getStats();
    } catch (_) {
      yield TransferStats.fromJson({});
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
});

// ── rclone version ────────────────────────────────────────────────────────────

final rcloneVersionProvider = FutureProvider.autoDispose<String>((ref) {
  return ref.watch(rcloneApiProvider).getVersion();
});

// ── Bandwidth limit ───────────────────────────────────────────────────────────

final bandwidthLimitProvider = FutureProvider.autoDispose<String>((ref) {
  return ref.watch(rcloneApiProvider).getBandwidthLimit();
});

// ── File listing ──────────────────────────────────────────────────────────────

final directoryListingProvider =
    FutureProvider.autoDispose.family<List<FileItem>, String>((
  ref,
  remotePath,
) {
  return ref.watch(rcloneApiProvider).listDirectory(remotePath);
});

// ── Daemon logs (polled every 1 s) ────────────────────────────────────────────

final logsProvider = StreamProvider.autoDispose<List<String>>((ref) async* {
  final service = ref.watch(rcloneServiceProvider);
  while (true) {
    try {
      yield await service.getLogs();
    } catch (_) {
      yield [];
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
});
