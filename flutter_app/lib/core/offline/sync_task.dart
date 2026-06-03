/// Tarefa na fila offline — serializada em Hive.
class SyncTask {
  SyncTask({
    required this.id,
    required this.module,
    required this.tenantId,
    required this.operation,
    required this.payload,
    DateTime? createdAt,
    this.retryCount = 0,
    this.lastError,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String module;
  final String tenantId;
  final String operation;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int retryCount;
  final String? lastError;

  SyncTask copyWith({
    int? retryCount,
    String? lastError,
  }) =>
      SyncTask(
        id: id,
        module: module,
        tenantId: tenantId,
        operation: operation,
        payload: payload,
        createdAt: createdAt,
        retryCount: retryCount ?? this.retryCount,
        lastError: lastError,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'module': module,
        'tenantId': tenantId,
        'operation': operation,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'retryCount': retryCount,
        if (lastError != null) 'lastError': lastError,
      };

  static SyncTask fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];
    return SyncTask(
      id: (json['id'] ?? '').toString(),
      module: (json['module'] ?? '').toString(),
      tenantId: (json['tenantId'] ?? '').toString(),
      operation: (json['operation'] ?? '').toString(),
      payload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : <String, dynamic>{},
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      retryCount: json['retryCount'] is int
          ? json['retryCount'] as int
          : int.tryParse('${json['retryCount']}') ?? 0,
      lastError: json['lastError']?.toString(),
    );
  }
}
