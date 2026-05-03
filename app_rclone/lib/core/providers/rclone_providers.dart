import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../rclone/rclone_service.dart';
import '../rclone/rclone_api.dart';
import '../models/remote.dart';
import '../models/job.dart';
import '../models/file_item.dart';

// ── Singleton services ────────────────────────────────────────────────────────

final rcloneServiceProvider = Provider<RcloneService>((_) => RcloneService());

// ── Daemon credentials (port + auth) ─────────────────────────────────────────
// Null until the daemon starts and credentials are resolved.
// When updated, rcloneApiProvider rebuilds automatically.

final daemonCredentialsProvider =
    StateProvider<DaemonCredentials?>((_) => null);

// ── HTTP API client ───────────────────────────────────────────────────────────
// Rebuilt whenever credentials change (new port / new session).

final rcloneApiProvider = Provider<RcloneApi>((ref) {
  final creds = ref.watch(daemonCredentialsProvider);
  return RcloneApi(
    baseUrl: creds != null ? creds.baseUrl : 'http://127.0.0.1:5572',
    username: creds?.user,
    password: creds?.pass,
  );
});

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
  final Ref _ref;

  DaemonNotifier(this._service, this._ref)
      : super(const DaemonState(status: DaemonStatus.stopped));

  // Read the fresh API instance each time (rebuilds when credentials change).
  RcloneApi get _api => _ref.read(rcloneApiProvider);

  Future<void> start() async {
    if (state.status == DaemonStatus.starting) return;
    state = const DaemonState(status: DaemonStatus.starting);
    try {
      await _service.startDaemon();

      // Poll until the daemon responds or we time out.
      // Credentials are loaded as soon as they're available so the API
      // can authenticate before the daemon is fully ready.
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(deadline)) {
        // Load credentials as soon as the service allocates them.
        if (_ref.read(daemonCredentialsProvider) == null) {
          final creds = await _service.getDaemonCredentials();
          if (creds != null) {
            _ref.read(daemonCredentialsProvider.notifier).state = creds;
          }
        }
        if (await _api.ping()) {
          state = const DaemonState(status: DaemonStatus.running);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      state = const DaemonState(
        status: DaemonStatus.error,
        errorMessage: 'Daemon did not respond within 20 seconds',
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
    _ref.read(daemonCredentialsProvider.notifier).state = null;
    state = const DaemonState(status: DaemonStatus.stopped);
  }

  Future<void> checkRunning() async {
    final alive = await _api.ping();
    if (alive && !state.isRunning) {
      // Daemon recovered or was started externally — refresh credentials.
      final creds = await _service.getDaemonCredentials();
      if (creds != null) {
        _ref.read(daemonCredentialsProvider.notifier).state = creds;
      }
      state = const DaemonState(status: DaemonStatus.running);
    } else if (!alive && state.isRunning) {
      _ref.read(daemonCredentialsProvider.notifier).state = null;
      state = const DaemonState(status: DaemonStatus.stopped);
    }
  }
}

final daemonProvider =
    StateNotifierProvider<DaemonNotifier, DaemonState>((ref) {
  return DaemonNotifier(ref.watch(rcloneServiceProvider), ref);
});

// ── SAF bridge ────────────────────────────────────────────────────────────────

final safBridgeProvider = StateProvider<SafBridgeInfo?>((_) => null);

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
    await Future<void>.delayed(const Duration(seconds: 3));
  }
});

// ── Transfer stats (polled every 2 s) ────────────────────────────────────────

final transferStatsProvider =
    StreamProvider.autoDispose<TransferStats>((ref) async* {
  final api = ref.watch(rcloneApiProvider);
  while (true) {
    try {
      yield await api.getStats();
    } catch (_) {
      yield TransferStats.fromJson({});
    }
    await Future<void>.delayed(const Duration(seconds: 2));
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

// ── Daemon logs (polled every 3 s) ────────────────────────────────────────────

final logsProvider = StreamProvider.autoDispose<List<String>>((ref) async* {
  final service = ref.watch(rcloneServiceProvider);
  while (true) {
    try {
      yield await service.getLogs();
    } catch (_) {
      yield [];
    }
    await Future<void>.delayed(const Duration(seconds: 3));
  }
});
