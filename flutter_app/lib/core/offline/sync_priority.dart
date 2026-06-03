import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/sync_task.dart';

/// Prioridade da fila Hive — menor número = processa primeiro.
abstract final class SyncPriority {
  SyncPriority._();

  static const login = 10;
  static const chat = 20;
  static const avisos = 30;
  static const eventos = 40;
  static const financeiro = 50;
  static const patrimonio = 60;
  static const fotos = 70;
  static const videos = 80;
  static const defaultPriority = 90;

  static int forTask(SyncTask task) {
    if (_isLoginTask(task)) return login;

    final mod = task.module.trim().toLowerCase();
    if (mod == OfflineModules.chat || mod == 'chat') return chat;
    if (mod == OfflineModules.avisos || mod == OfflineModules.mural) {
      return _hasVideoPayload(task) ? videos : (_hasPhotoPayload(task) ? fotos : avisos);
    }
    if (mod == OfflineModules.eventos) {
      return _hasVideoPayload(task) ? videos : (_hasPhotoPayload(task) ? fotos : eventos);
    }
    if (mod == OfflineModules.financeiro) return financeiro;
    if (mod == OfflineModules.patrimonio) return patrimonio;
    if (mod == 'storage' || mod == 'mural') {
      return _hasVideoPayload(task) ? videos : fotos;
    }
    return defaultPriority;
  }

  static bool _isLoginTask(SyncTask task) {
    final op = task.operation.toLowerCase();
    final mod = task.module.toLowerCase();
    return mod == 'auth' ||
        mod == 'login' ||
        op.contains('session') ||
        op.contains('token');
  }

  static bool _hasVideoPayload(SyncTask task) {
    final blob = task.payload.toString().toLowerCase();
    return blob.contains('video') ||
        blob.contains('.mp4') ||
        blob.contains('.mov') ||
        blob.contains('videourl');
  }

  static bool _hasPhotoPayload(SyncTask task) {
    final blob = task.payload.toString().toLowerCase();
    return blob.contains('photo') ||
        blob.contains('image') ||
        blob.contains('.jpg') ||
        blob.contains('.jpeg') ||
        blob.contains('.png') ||
        blob.contains('.webp') ||
        blob.contains('foto');
  }

  static int compareTasks(SyncTask a, SyncTask b) {
    final pa = forTask(a);
    final pb = forTask(b);
    if (pa != pb) return pa.compareTo(pb);
    return a.createdAt.compareTo(b.createdAt);
  }

  /// Ordem dos flushers legados (chat antes de storage/mural).
  static const flusherOrder = <String>[
    'auth',
    'login',
    'chat',
    'avisos',
    'eventos',
    'financeiro',
    'patrimonio',
    'membros',
    'escalas',
    'mural',
    'storage',
    'bootstrap',
    'visitantes',
    'pedidos_oracao',
    'departamentos',
    'tenant',
  ];

  static int flusherIndex(String module) {
    final i = flusherOrder.indexOf(module);
    return i >= 0 ? i : flusherOrder.length + 1;
  }
}
