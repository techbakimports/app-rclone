class Remote {
  final String name;
  final String type;
  final Map<String, String> config;

  const Remote({
    required this.name,
    required this.type,
    required this.config,
  });

  factory Remote.fromApi(String name, Map<String, dynamic> config) {
    final type = config['type'] as String? ?? '';
    final params = Map<String, String>.fromEntries(
      config.entries
          .where((e) => e.key != 'type')
          .map((e) => MapEntry(e.key, e.value.toString())),
    );
    return Remote(name: name, type: type, config: params);
  }

  String get displayName => name;
  String get remotePath => '$name:';
}

class RemoteProvider {
  final String name;
  final String description;
  final List<ProviderOption> options;

  const RemoteProvider({
    required this.name,
    required this.description,
    required this.options,
  });

  factory RemoteProvider.fromJson(Map<String, dynamic> json) {
    return RemoteProvider(
      name: json['Name'] as String? ?? '',
      description: json['Description'] as String? ?? '',
      options: (json['Options'] as List<dynamic>? ?? [])
          .map((o) => ProviderOption.fromJson(o as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ProviderOption {
  final String name;
  final String help;
  final bool required;
  final bool isPassword;
  final String defaultValue;
  final List<String> examples;

  const ProviderOption({
    required this.name,
    required this.help,
    required this.required,
    required this.isPassword,
    required this.defaultValue,
    required this.examples,
  });

  factory ProviderOption.fromJson(Map<String, dynamic> json) {
    return ProviderOption(
      name: json['Name'] as String? ?? '',
      help: json['Help'] as String? ?? '',
      required: json['Required'] as bool? ?? false,
      isPassword: json['IsPassword'] as bool? ?? false,
      defaultValue: json['DefaultStr'] as String? ?? '',
      examples: (json['Examples'] as List<dynamic>? ?? [])
          .map((e) => (e as Map<String, dynamic>)['Value']?.toString() ?? '')
          .toList(),
    );
  }
}
