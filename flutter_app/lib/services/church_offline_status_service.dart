import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gestao_yahweh/core/offline/hive_local_store.dart';
import 'package:gestao_yahweh/core/offline/offline_modules.dart';
import 'package:gestao_yahweh/core/offline/sync_engine.dart';
import 'package:gestao_yahweh/services/app_connectivity_service.dart';
import 'package:gestao_yahweh/services/church_tenant_offline_warmup_service.dart';

/// Fase visível no painel (faixa offline / sincronização).
enum ChurchOfflineUiPhase {
  hidden,
  offline,
  syncing,
  caching,
}

class ChurchOfflineStatusSnapshot {
  const ChurchOfflineStatusSnapshot({
    required this.phase,
    this.pendingQueueCount = 0,
    this.title = '',
    this.subtitle = '',
  });

  final ChurchOfflineUiPhase phase;
  final int pendingQueueCount;
  final String title;
  final String subtitle;

  bool get isVisible => phase != ChurchOfflineUiPhase.hidden;
}

/// Estado unificado para UX offline-first no painel igreja / master.
abstract final class ChurchOfflineStatusService {
  ChurchOfflineStatusService._();

  static const _offlineModulesLabel =
      'Membros, escalas, avisos, visitantes, oração e mais';

  static ChurchOfflineStatusSnapshot resolve({
    required bool online,
    required bool flushing,
    required bool warmingCache,
    required int pendingQueue,
    bool compact = false,
  }) {
    if (!online) {
      return ChurchOfflineStatusSnapshot(
        phase: ChurchOfflineUiPhase.offline,
        pendingQueueCount: pendingQueue,
        title: 'Modo offline',
        subtitle: compact
            ? 'Dados locais — sincroniza ao voltar a internet'
            : 'Você está vendo dados já salvos no aparelho ($_offlineModulesLabel). '
                'Edições ficam na fila e sincronizam quando a internet voltar.',
      );
    }

    if (flushing || pendingQueue > 0) {
      final queueHint = pendingQueue > 0
          ? (compact
              ? ' · $pendingQueue na fila'
              : ' $pendingQueue alteração(ões) na fila local.')
          : '';
      return ChurchOfflineStatusSnapshot(
        phase: ChurchOfflineUiPhase.syncing,
        pendingQueueCount: pendingQueue,
        title: 'Sincronizando…',
        subtitle: compact
            ? 'Enviando para a nuvem$queueHint'
            : 'Enviando alterações para a nuvem.$queueHint',
      );
    }

    if (warmingCache) {
      return ChurchOfflineStatusSnapshot(
        phase: ChurchOfflineUiPhase.caching,
        title: compact ? 'Atualizando cache' : 'Atualizando cache local',
        subtitle: compact
            ? 'Membros, mural, escalas…'
            : 'Preparando $_offlineModulesLabel para uso sem internet.',
      );
    }

    return const ChurchOfflineStatusSnapshot(phase: ChurchOfflineUiPhase.hidden);
  }

  static Future<int> pendingQueueCount() async {
    try {
      return (await HiveLocalStore.instance.listTasks()).length;
    } catch (_) {
      return 0;
    }
  }

  /// Módulos com fila offline registrada no bootstrap.
  static List<String> supportedModuleLabels() => const [
        'Membros',
        'Escalas',
        'Avisos',
        'Eventos',
        'Visitantes',
        'Oração',
        'Departamentos',
        'Financeiro',
        'Patrimônio',
        'Chat',
        'Mural',
      ];

  static String moduleKeyLabel(String key) {
    switch (key) {
      case OfflineModules.membros:
        return 'Membros';
      case OfflineModules.escalas:
        return 'Escalas';
      case OfflineModules.avisos:
        return 'Avisos';
      case OfflineModules.eventos:
        return 'Eventos';
      case OfflineModules.visitantes:
        return 'Visitantes';
      case OfflineModules.pedidosOracao:
        return 'Oração';
      case OfflineModules.departamentos:
        return 'Departamentos';
      case OfflineModules.financeiro:
        return 'Financeiro';
      case OfflineModules.patrimonio:
        return 'Patrimônio';
      case OfflineModules.chat:
        return 'Chat';
      case OfflineModules.mural:
        return 'Mural';
      default:
        return 'Igreja';
    }
  }
}

/// Escuta rede + fila Hive + warmup e expõe snapshot para a faixa do painel.
class ChurchOfflineStatusScope extends StatefulWidget {
  const ChurchOfflineStatusScope({
    super.key,
    required this.builder,
  });

  final Widget Function(BuildContext context, ChurchOfflineStatusSnapshot snap)
      builder;

  @override
  State<ChurchOfflineStatusScope> createState() =>
      _ChurchOfflineStatusScopeState();
}

class _ChurchOfflineStatusScopeState extends State<ChurchOfflineStatusScope> {
  bool _online = true;
  bool _flushing = false;
  bool _warming = false;
  int _pending = 0;
  Timer? _pollTimer;
  StreamSubscription<bool>? _onlineSub;
  StreamSubscription<bool>? _flushSub;
  StreamSubscription<bool>? _warmupSub;

  @override
  void initState() {
    super.initState();
    _online = AppConnectivityService.instance.isOnline;
    _flushing = SyncEngine.isFlushing;
    _warming = ChurchTenantOfflineWarmupService.instance.isWarmupRunning;
    unawaited(_refreshPending());

    _onlineSub = AppConnectivityService.instance.onlineStream.listen((v) {
      if (!mounted) return;
      setState(() => _online = v);
      if (v) unawaited(_refreshPending());
    });
    _flushSub = SyncEngine.flushingStream.listen((v) {
      if (!mounted) return;
      setState(() => _flushing = v);
      if (!v) unawaited(_refreshPending());
    });
    _warmupSub = ChurchTenantOfflineWarmupService.instance.warmupRunningStream
        .listen((v) {
      if (!mounted) return;
      setState(() => _warming = v);
    });

    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      if (_online && (_flushing || _pending > 0)) {
        unawaited(_refreshPending());
      }
    });
  }

  Future<void> _refreshPending() async {
    final n = await ChurchOfflineStatusService.pendingQueueCount();
    if (!mounted) return;
    if (n != _pending) setState(() => _pending = n);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _onlineSub?.cancel();
    _flushSub?.cancel();
    _warmupSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 400;
    final snap = ChurchOfflineStatusService.resolve(
      online: _online,
      flushing: _flushing,
      warmingCache: _warming,
      pendingQueue: _pending,
      compact: compact,
    );
    return widget.builder(context, snap);
  }
}
