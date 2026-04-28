class FileItem {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final DateTime? modTime;
  final String? mimeType;

  const FileItem({
    required this.name,
    required this.path,
    required this.isDir,
    required this.size,
    this.modTime,
    this.mimeType,
  });

  factory FileItem.fromJson(Map<String, dynamic> json) {
    return FileItem(
      name: json['Name'] as String? ?? '',
      path: json['Path'] as String? ?? '',
      isDir: json['IsDir'] as bool? ?? false,
      size: (json['Size'] as num?)?.toInt() ?? 0,
      modTime: json['ModTime'] != null
          ? DateTime.tryParse(json['ModTime'] as String)
          : null,
      mimeType: json['MimeType'] as String?,
    );
  }

  String get sizeFormatted {
    if (isDir) return '';
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }

  String get extension {
    if (isDir) return '';
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }
}
