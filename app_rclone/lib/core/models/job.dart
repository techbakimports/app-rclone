enum JobStatus { running, finished, error }

class RcloneJob {
  final int id;
  final JobStatus status;
  final String? error;
  final DateTime startTime;
  final DateTime? endTime;
  final double? duration;
  final TransferStats? stats;

  const RcloneJob({
    required this.id,
    required this.status,
    this.error,
    required this.startTime,
    this.endTime,
    this.duration,
    this.stats,
  });

  factory RcloneJob.fromJson(Map<String, dynamic> json) {
    JobStatus status;
    final finished = json['finished'] as bool? ?? false;
    final error = json['error'] as String?;
    if (!finished) {
      status = JobStatus.running;
    } else if (error != null && error.isNotEmpty) {
      status = JobStatus.error;
    } else {
      status = JobStatus.finished;
    }

    return RcloneJob(
      id: json['id'] as int? ?? 0,
      status: status,
      error: error?.isNotEmpty == true ? error : null,
      startTime: DateTime.tryParse(json['startTime'] as String? ?? '') ??
          DateTime.now(),
      endTime: json['endTime'] != null
          ? DateTime.tryParse(json['endTime'] as String)
          : null,
      duration: (json['duration'] as num?)?.toDouble(),
      stats: json['stats'] != null
          ? TransferStats.fromJson(json['stats'] as Map<String, dynamic>)
          : null,
    );
  }

  bool get isActive => status == JobStatus.running;
}

class TransferStats {
  final int bytes;
  final int errors;
  final int checks;
  final int transfers;
  final double speed;
  final int totalBytes;
  final int totalTransfers;
  final double eta;
  final String elapsedTime;

  const TransferStats({
    required this.bytes,
    required this.errors,
    required this.checks,
    required this.transfers,
    required this.speed,
    required this.totalBytes,
    required this.totalTransfers,
    required this.eta,
    required this.elapsedTime,
  });

  factory TransferStats.fromJson(Map<String, dynamic> json) {
    return TransferStats(
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      errors: (json['errors'] as num?)?.toInt() ?? 0,
      checks: (json['checks'] as num?)?.toInt() ?? 0,
      transfers: (json['transfers'] as num?)?.toInt() ?? 0,
      speed: (json['speed'] as num?)?.toDouble() ?? 0.0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      totalTransfers: (json['totalTransfers'] as num?)?.toInt() ?? 0,
      eta: (json['eta'] as num?)?.toDouble() ?? 0.0,
      elapsedTime: json['elapsedTime'] as String? ?? '0s',
    );
  }

  double get progressFraction {
    if (totalBytes <= 0) return 0.0;
    return (bytes / totalBytes).clamp(0.0, 1.0);
  }

  String get speedFormatted => '${_formatBytes(speed.toInt())}/s';
  String get bytesFormatted => _formatBytes(bytes);
  String get totalBytesFormatted => _formatBytes(totalBytes);

  static String _formatBytes(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}KB';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)}GB';
  }
}
