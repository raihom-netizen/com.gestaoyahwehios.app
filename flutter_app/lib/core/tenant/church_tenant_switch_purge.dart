import 'package:gestao_yahweh/services/certificate_emitido_service.dart';
import 'package:gestao_yahweh/services/church_brand_service.dart';
import 'package:gestao_yahweh/services/church_departments_load_service.dart';
import 'package:gestao_yahweh/services/church_donation_load_service.dart';
import 'package:gestao_yahweh/services/church_fornecedores_load_service.dart';
import 'package:gestao_yahweh/services/church_operational_paths.dart';
import 'package:gestao_yahweh/services/church_relatorios_load_service.dart';
import 'package:gestao_yahweh/services/finance_comprovante_disk_cache.dart';
import 'package:gestao_yahweh/services/finance_month_cache.dart';
import 'package:gestao_yahweh/services/firebase_storage_service.dart';
import 'package:gestao_yahweh/services/member_card_directory_service.dart';
import 'package:gestao_yahweh/services/member_card_photo_cache.dart';
import 'package:gestao_yahweh/services/noticia_share_prefetch_service.dart';
import 'package:gestao_yahweh/services/panel_programacao_loader.dart';
import 'package:gestao_yahweh/services/public_church_slug_resolver.dart';
import 'package:gestao_yahweh/services/smart_category_hints_service.dart';
import 'package:gestao_yahweh/utils/finance_transactions_hub.dart';

/// Esvazia **todos** os caches em RAM quando o operador global troca de igreja.
///
/// Existe porque a troca de igreja mudava o `churchId` mas o painel continuava
/// a mostrar os dados da igreja anterior. Duas causas distintas:
///
/// 1. Caches cuja chave **nao inclui** a igreja — [FinanceMonthCache] indexa
///    por `uid|ano-mes`, portanto o mesmo operador via sempre o mes da primeira
///    igreja que abriu. Era este o «Financeiro nao carrega a igreja escolhida».
/// 2. Caches indexados por igreja mas com TTL de 8 a 25 minutos: a igreja certa
///    era lida, so que a entrada antiga continuava viva e voltava a aparecer
///    ao regressar. Esvaziar e barato — a proxima leitura repovoa.
///
/// Chamado de um unico sitio: `_onMasterTenantChanged` no shell do painel.
/// Ao acrescentar um cache novo, junte-o aqui.
abstract final class ChurchTenantSwitchPurge {
  ChurchTenantSwitchPurge._();

  static void purgarTudo() {
    // Cada purga e independente: uma que falhe nao pode impedir as restantes,
    // senao a troca ficava a meio — pior do que nao purgar nada.
    void tentar(void Function() purgar) {
      try {
        purgar();
      } catch (_) {}
    }

    tentar(FinanceMonthCache.purgarNaTrocaDeIgreja);
    tentar(FinanceComprovanteDiskCache.purgarNaTrocaDeIgreja);
    tentar(FinanceTransactionsHub.limparApagados);
    tentar(ChurchBrandService.purgarNaTrocaDeIgreja);
    tentar(ChurchDepartmentsLoadService.purgarNaTrocaDeIgreja);
    tentar(ChurchDonationLoadService.purgarNaTrocaDeIgreja);
    tentar(ChurchFornecedoresLoadService.purgarNaTrocaDeIgreja);
    tentar(ChurchRelatoriosLoadService.purgarNaTrocaDeIgreja);
    tentar(ChurchOperationalPaths.clearSessionCache);
    tentar(CertificateEmitidoService.purgarNaTrocaDeIgreja);
    tentar(FirebaseStorageService.purgarNaTrocaDeIgreja);
    tentar(MemberCardDirectoryService.purgarNaTrocaDeIgreja);
    tentar(MemberCardPhotoCache.purgarNaTrocaDeIgreja);
    tentar(NoticiaSharePrefetchService.purgarNaTrocaDeIgreja);
    tentar(PanelProgramacaoLoader.purgarNaTrocaDeIgreja);
    tentar(PublicChurchSlugResolver.purgarNaTrocaDeIgreja);
    tentar(SmartCategoryHintsService.purgarNaTrocaDeIgreja);
  }
}
