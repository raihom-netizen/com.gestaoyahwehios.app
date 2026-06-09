import 'package:gestao_yahweh/core/data/church_data_paths.dart';
import 'package:gestao_yahweh/core/data/church_data_result.dart';
import 'package:gestao_yahweh/core/data/church_firestore_access.dart';
import 'package:gestao_yahweh/core/data/modules/church_agenda_repository.dart';
import 'package:gestao_yahweh/core/data/modules/church_avisos_repository.dart';
import 'package:gestao_yahweh/core/data/modules/church_cargos_repository.dart';
import 'package:gestao_yahweh/core/data/modules/church_chat_repository.dart';
import 'package:gestao_yahweh/core/data/modules/church_departamentos_repository.dart';
import 'package:gestao_yahweh/core/data/modules/church_doacoes_repository.dart';
import 'package:gestao_yahweh/core/data/modules/church_eventos_repository.dart';
import 'package:gestao_yahweh/core/data/modules/church_financeiro_repository.dart';
import 'package:gestao_yahweh/core/data/modules/church_mercadopago_repository.dart';
import 'package:gestao_yahweh/core/data/modules/church_membros_repository.dart';
import 'package:gestao_yahweh/core/data/modules/church_module_repository_base.dart';
import 'package:gestao_yahweh/core/data/modules/church_patrimonio_repository.dart';

/// **ÚNICA** fachada de dados do Gestão YAHWEH — Web = Android = iOS.
///
/// Telas importam **somente** este arquivo.
/// Proibido `FirebaseFirestore.instance` em `lib/ui/`.
abstract final class ChurchDataRepository {
  ChurchDataRepository._();

  static String churchId([String? hint]) =>
      ChurchFirestoreAccess.resolveChurchId(hint);

  static String firestorePath([String? hint]) {
    final id = churchId(hint);
    return id.isEmpty ? '' : ChurchDataPaths.churchRoot(id);
  }

  // ─── Módulos (repositórios) ───────────────────────────────────────────────
  static const departamentos = ChurchDepartamentosRepository.instance;
  static const cargos = ChurchCargosRepository.instance;
  static const financeiro = ChurchFinanceiroRepository.instance;
  static const eventos = ChurchEventosRepository.instance;
  static const avisos = ChurchAvisosRepository.instance;
  static const chat = ChurchChatRepository.instance;
  static const patrimonio = ChurchPatrimonioRepository.instance;
  static const membros = ChurchMembrosRepository.instance;
  static const doacoes = ChurchDoacoesRepository.instance;
  static const mercadopago = ChurchMercadoPagoRepository.instance;
  static const agenda = ChurchAgendaRepository.instance;

  static final fornecedores = _FornecedoresRepo();
  static final escalas = _EscalasRepo();
  static final pedidosOracao = _PedidosOracaoRepo();
  static final transferencias = _TransferenciasRepo();
  static final certificados = _CertificadosRepo();
  static final cartoes = _CartoesRepo();
  static final lideres = _LideresRepo();
  static final administrativo = _AdministrativoRepo();

  static Future<ChurchDataDocResult> loadChurchRoot({
    String? churchIdHint,
  }) async {
    final id = churchId(churchIdHint);
    if (id.isEmpty) {
      return ChurchDataDocResult(
        churchId: '',
        documentPath: '',
        data: const {},
        exists: false,
        readAt: DateTime.now(),
        error: 'churchId vazio',
      );
    }
    try {
      final snap = await ChurchFirestoreAccess.getChurchRoot(churchId: id);
      return ChurchDataDocResult(
        churchId: id,
        documentPath: snap.reference.path,
        data: snap.data() ?? {},
        exists: snap.exists,
        readAt: DateTime.now(),
        fromCache: snap.metadata.isFromCache,
      );
    } catch (e) {
      return ChurchDataDocResult(
        churchId: id,
        documentPath: ChurchDataPaths.churchRoot(id),
        data: const {},
        exists: false,
        readAt: DateTime.now(),
        error: '$e',
      );
    }
  }

  static void cancelAllListeners() => ChurchFirestoreAccess.cancelAllWatches();
}

final class _FornecedoresRepo extends ChurchModuleRepositoryBase {
  _FornecedoresRepo()
      : super(
          moduleLabel: 'Fornecedores',
          subcollection: ChurchDataPaths.fornecedores,
        );
}

final class _EscalasRepo extends ChurchModuleRepositoryBase {
  _EscalasRepo()
      : super(moduleLabel: 'Escalas', subcollection: ChurchDataPaths.escalas);
}

final class _PedidosOracaoRepo extends ChurchModuleRepositoryBase {
  _PedidosOracaoRepo()
      : super(
          moduleLabel: 'Pedidos Oração',
          subcollection: ChurchDataPaths.pedidosOracao,
        );
}

final class _TransferenciasRepo extends ChurchModuleRepositoryBase {
  _TransferenciasRepo()
      : super(
          moduleLabel: 'Transferências',
          subcollection: ChurchDataPaths.transferencias,
        );
}

final class _CertificadosRepo extends ChurchModuleRepositoryBase {
  _CertificadosRepo()
      : super(
          moduleLabel: 'Certificados',
          subcollection: ChurchDataPaths.certificados,
        );
}

final class _CartoesRepo extends ChurchModuleRepositoryBase {
  _CartoesRepo()
      : super(moduleLabel: 'Cartão Membro', subcollection: ChurchDataPaths.cartoes);
}

final class _LideresRepo extends ChurchModuleRepositoryBase {
  _LideresRepo()
      : super(moduleLabel: 'Líderes', subcollection: ChurchDataPaths.lideres);
}

final class _AdministrativoRepo extends ChurchModuleRepositoryBase {
  _AdministrativoRepo()
      : super(
          moduleLabel: 'Administrativo',
          subcollection: ChurchDataPaths.administrativo,
        );
}
