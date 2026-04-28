import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/remote.dart';
import '../../core/providers/rclone_providers.dart';

// Providers that need OAuth (token-based auth)
const _oauthProviders = {
  'drive', 'dropbox', 'onedrive', 'box', 'amazonclouddrive',
  'googlephotos', 'pcloud', 'putio', 'yandex', 'zoho',
  'sharefile', 'jottacloud', 'fichier', 'opendrive', 'premiumizeme',
  'pikpak', 'seafile', 'hidrive', 'internetarchive',
};

bool _needsOAuth(RemoteProvider provider) {
  return _oauthProviders.contains(provider.name.toLowerCase()) ||
      provider.options.any((o) => o.name == 'token');
}

class RemoteFormScreen extends ConsumerStatefulWidget {
  final Remote? existing;
  final VoidCallback? onSaved;

  const RemoteFormScreen({super.key, this.existing, this.onSaved});

  @override
  ConsumerState<RemoteFormScreen> createState() => _RemoteFormScreenState();
}

class _RemoteFormScreenState extends ConsumerState<RemoteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String? _selectedType;
  final Map<String, TextEditingController> _paramControllers = {};
  bool _saving = false;

  // OAuth state
  _OAuthState _oauthState = const _OAuthIdle();
  StreamSubscription<Map<dynamic, dynamic>>? _authSub;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameController.text = widget.existing!.name;
      _selectedType = widget.existing!.type;
      widget.existing!.config.forEach((k, v) {
        _paramControllers[k] = TextEditingController(text: v);
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _authSub?.cancel();
    for (final c in _paramControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(providersListProvider);

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Remote' : 'Add Remote')),
      body: providersAsync.when(
        data: (providers) => _buildForm(context, providers),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('Failed to load providers: $e')),
      ),
    );
  }

  Widget _buildForm(BuildContext context, List<RemoteProvider> providers) {
    final selectedProvider =
        providers.where((p) => p.name == _selectedType).firstOrNull;

    // Sync controllers for the selected provider's options
    if (selectedProvider != null) {
      for (final opt in selectedProvider.options) {
        if (opt.name != 'token') {
          _paramControllers.putIfAbsent(
            opt.name,
            () => TextEditingController(text: opt.defaultValue),
          );
        }
      }
    }

    final showOAuth =
        selectedProvider != null && _needsOAuth(selectedProvider) && !isEdit;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _nameController,
            enabled: !isEdit,
            decoration: const InputDecoration(
              labelText: 'Remote name',
              hintText: 'e.g. mycloud',
              helperText: 'Letters, numbers, hyphens and underscores only',
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Name is required';
              if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(v.trim())) {
                return 'Only letters, numbers, _ and - allowed';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedType,
            decoration: const InputDecoration(labelText: 'Provider type'),
            items: providers
                .map(
                  (p) => DropdownMenuItem(
                    value: p.name,
                    child: Text('${p.name} — ${p.description}'),
                  ),
                )
                .toList(),
            onChanged: isEdit
                ? null
                : (v) {
                    setState(() {
                      _selectedType = v;
                      _paramControllers.clear();
                      _oauthState = const _OAuthIdle();
                    });
                    _authSub?.cancel();
                    ref.read(rcloneServiceProvider).cancelAuth();
                  },
            validator: (v) => v == null ? 'Provider is required' : null,
          ),
          if (selectedProvider != null) ...[
            const SizedBox(height: 24),
            Text('Configuration', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            // Show non-token options
            ...selectedProvider.options
                .where((opt) => opt.name != 'token')
                .map(
                  (opt) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _optionField(opt),
                  ),
                ),
            if (showOAuth) ...[
              const SizedBox(height: 8),
              _OAuthSection(
                providerType: selectedProvider.name,
                state: _oauthState,
                onAuthorize: () => _startOAuth(selectedProvider.name),
                onCancel: _cancelOAuth,
              ),
            ],
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _canSave() ? _save : null,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isEdit ? 'Save Changes' : 'Create Remote'),
          ),
        ],
      ),
    );
  }

  bool _canSave() {
    if (_saving) return false;
    if (_selectedType == null) return false;
    final provider = ref
        .read(providersListProvider)
        .valueOrNull
        ?.firstWhereOrNull((p) => p.name == _selectedType);
    if (provider != null && _needsOAuth(provider) && !isEdit) {
      return _oauthState is _OAuthDone;
    }
    return true;
  }

  TextFormField _optionField(ProviderOption opt) {
    return TextFormField(
      controller: _paramControllers[opt.name],
      obscureText: opt.isPassword,
      decoration: InputDecoration(
        labelText: opt.name,
        helperText: opt.help.length > 80
            ? '${opt.help.substring(0, 80)}…'
            : opt.help,
        helperMaxLines: 2,
        suffixIcon: opt.isPassword ? const Icon(Icons.lock_outline) : null,
      ),
      validator: opt.required
          ? (v) =>
              (v == null || v.isEmpty) ? '${opt.name} is required' : null
          : null,
    );
  }

  void _startOAuth(String type) {
    if (_oauthState is _OAuthInProgress) return;

    // Stop daemon temporarily to avoid config file conflicts
    final notifier = ref.read(daemonProvider.notifier);
    final wasDaemonRunning = ref.read(daemonProvider).isRunning;
    if (wasDaemonRunning) notifier.stop();

    setState(() => _oauthState = const _OAuthInProgress());

    final stream = ref.read(rcloneServiceProvider).startAuthFlow(type);
    _authSub = stream.listen(
      (event) {
        final eventType = event['type'] as String?;
        if (eventType == 'url') {
          final url = event['url'] as String? ?? '';
          setState(() => _oauthState = _OAuthAwaitingBrowser(url: url));
          _openBrowser(url);
        } else if (eventType == 'token') {
          final token = event['token'] as String? ?? '';
          _paramControllers['token'] =
              TextEditingController(text: token);
          setState(() => _oauthState = _OAuthDone(token: token));
          // Restart daemon if it was running
          if (wasDaemonRunning) notifier.start();
        }
      },
      onError: (Object e) {
        setState(() => _oauthState = _OAuthError(message: e.toString()));
        if (wasDaemonRunning) notifier.start();
      },
    );
  }

  void _cancelOAuth() {
    _authSub?.cancel();
    ref.read(rcloneServiceProvider).cancelAuth();
    setState(() => _oauthState = const _OAuthIdle());
  }

  Future<void> _openBrowser(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot open browser: $url')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final name = _nameController.text.trim();
    final type = _selectedType!;
    final params = Map<String, String>.fromEntries(
      _paramControllers.entries
          .where((e) => e.value.text.isNotEmpty)
          .map((e) => MapEntry(e.key, e.value.text)),
    );

    final api = ref.read(rcloneApiProvider);
    try {
      if (isEdit) {
        await api.updateRemote(name, params);
      } else {
        await api.createRemote(name, type, params);
      }
      widget.onSaved?.call();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// ── OAuth state machine ───────────────────────────────────────────────────────

sealed class _OAuthState {
  const _OAuthState();
}

class _OAuthIdle extends _OAuthState {
  const _OAuthIdle();
}

class _OAuthInProgress extends _OAuthState {
  const _OAuthInProgress();
}

class _OAuthAwaitingBrowser extends _OAuthState {
  final String url;
  const _OAuthAwaitingBrowser({required this.url});
}

class _OAuthDone extends _OAuthState {
  final String token;
  const _OAuthDone({required this.token});
}

class _OAuthError extends _OAuthState {
  final String message;
  const _OAuthError({required this.message});
}

// ── OAuth section widget ──────────────────────────────────────────────────────

class _OAuthSection extends StatelessWidget {
  final String providerType;
  final _OAuthState state;
  final VoidCallback onAuthorize;
  final VoidCallback onCancel;

  const _OAuthSection({
    required this.providerType,
    required this.state,
    required this.onAuthorize,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_open, size: 18, color: cs.secondary),
              const SizedBox(width: 8),
              Text(
                'OAuth Authorization',
                style: TextStyle(
                  color: cs.secondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          switch (state) {
            _OAuthIdle() => _idleContent(context),
            _OAuthInProgress() => _progressContent(context),
            _OAuthAwaitingBrowser(url: final url) =>
              _awaitingContent(context, url),
            _OAuthDone() => _doneContent(context),
            _OAuthError(message: final msg) => _errorContent(context, msg),
          },
        ],
      ),
    );
  }

  Widget _idleContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$providerType requires OAuth authorization. '
          'The daemon will pause briefly while you sign in.',
          style: const TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onAuthorize,
          icon: const Icon(Icons.open_in_browser),
          label: const Text('Authorize in browser'),
        ),
      ],
    );
  }

  Widget _progressContent(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 12),
        Text('Starting authorization…', style: TextStyle(fontSize: 13)),
      ],
    );
  }

  Widget _awaitingContent(BuildContext context, String url) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Browser opened — complete the sign-in and return here.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          url,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    );
  }

  Widget _doneContent(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.check_circle, color: cs.primary, size: 20),
        const SizedBox(width: 8),
        const Text(
          'Authorization successful',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _errorContent(BuildContext context, String message) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.error_outline, color: cs.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: cs.error, fontSize: 13),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onAuthorize,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
