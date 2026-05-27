import 'package:gestao_yahweh/services/member_codigo_service.dart';
import 'package:gestao_yahweh/ui/widgets/member_digital_wallet_card.dart'
    show walletFiliacaoFromMember;

/// Dados normalizados para o cartão membro padrão (estilo CNH digital).
class MemberCardCnhViewData {
  const MemberCardCnhViewData({
    required this.tenantId,
    required this.memberId,
    required this.nome,
    required this.cpf,
    required this.codigoMembro,
    required this.igrejaSede,
    required this.dataNascimento,
    required this.validade,
    required this.filiacao,
    required this.dataAdmissao,
    required this.categoria,
    required this.churchTitle,
    required this.churchSubtitle,
    required this.qrPayload,
    this.assinada = false,
    this.assinadaPorNome = '',
    this.assinadaPorCargo = '',
  });

  final String tenantId;
  final String memberId;
  final String nome;
  final String cpf;
  final String codigoMembro;
  final String igrejaSede;
  final String dataNascimento;
  final String validade;
  final String filiacao;
  final String dataAdmissao;
  final String categoria;
  final String churchTitle;
  final String churchSubtitle;
  final String qrPayload;
  final bool assinada;
  final String assinadaPorNome;
  final String assinadaPorCargo;

  static String _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static String _formatCpf(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length != 11) return raw.trim().isEmpty ? '—' : raw.trim();
    return '${d.substring(0, 3)}.${d.substring(3, 6)}.${d.substring(6, 9)}-${d.substring(9)}';
  }

  static String _fmtDate(dynamic v) {
    if (v == null) return '';
    DateTime? dt;
    if (v is DateTime) {
      dt = v;
    } else if (v is Map) {
      final sec = v['seconds'] ?? v['_seconds'];
      if (sec is num) {
        dt = DateTime.fromMillisecondsSinceEpoch(sec.toInt() * 1000);
      }
    } else {
      final t = DateTime.tryParse(v.toString());
      dt = t;
    }
    if (dt == null) return '';
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$d/$mo/${dt.year}';
  }

  static String _memberCode(Map<String, dynamic> m, String memberId) {
    final c = MemberCodigoService.readFromMember(m);
    if (c.isNotEmpty) return c;
    return 'Pendente';
  }

  static String _churchSede(Map<String, dynamic> tenant, String subtitle) {
    final cidade = _pick(tenant, ['cidade', 'city', 'municipio', 'MUNICIPIO']);
    final uf = _pick(tenant, ['uf', 'estado', 'state', 'UF', 'ESTADO']);
    if (cidade.isNotEmpty && uf.isNotEmpty) return '$cidade-$uf';
    if (cidade.isNotEmpty) return cidade;
    if (subtitle.trim().isNotEmpty) return subtitle.trim();
    return _pick(tenant, ['nome', 'name', 'titulo']);
  }

  static String _validityLabel(Map<String, dynamic> member) {
    if (member['CARTEIRA_PERMANENTE'] == true) return 'Permanente';
    final validadeCartao = member['validadeCartao'] ??
        member['VALIDADE_CARTAO'] ??
        member['validade_cartao'] ??
        member['validade'] ??
        member['VALIDADE'] ??
        member['dataValidade'] ??
        member['data_validade'];
    final v1 = _fmtDate(validadeCartao);
    if (v1.isNotEmpty) return v1;
    final carteiraValidade =
        member['CARTEIRA_VALIDADE'] ?? member['carteiraValidade'];
    final v2 = _fmtDate(carteiraValidade);
    if (v2.isNotEmpty) return v2;
    final years = member['CARTEIRA_ANOS'];
    if (years is int && years > 0) {
      final now = DateTime.now();
      return _fmtDate(DateTime(now.year + years, now.month, now.day));
    }
    final now = DateTime.now();
    return _fmtDate(DateTime(now.year + 1, now.month, now.day));
  }

  static String _categoria(Map<String, dynamic> m, String cargoLabel) {
    final c = _pick(m, [
      'categoria',
      'CATEGORIA',
      'tipoMembro',
      'TIPO_MEMBRO',
      'statusMembro',
      'STATUS_MEMBRO',
    ]);
    if (c.isNotEmpty) return c;
    final cargo = _pick(m, [
      'CARGO',
      'cargo',
      'funcao',
      'FUNCAO',
      'roleLabel',
    ]);
    if (cargo.isNotEmpty) return cargo;
    if (cargoLabel.trim().isNotEmpty) return cargoLabel.trim();
    return 'Membro Ativo';
  }

  factory MemberCardCnhViewData.fromMaps({
    required String tenantId,
    required String memberId,
    required Map<String, dynamic> member,
    required Map<String, dynamic> tenant,
    required String churchTitle,
    required String churchSubtitle,
    required String qrPayload,
    String cargoLabel = '',
  }) {
    final nome = _pick(member, [
      'NOME',
      'nome',
      'name',
      'nomeCompleto',
      'NOME_COMPLETO',
    ]);
    final cpfRaw = _pick(member, ['CPF', 'cpf']);
    final nasc = _fmtDate(
      member['DATA_NASCIMENTO'] ??
          member['dataNascimento'] ??
          member['data_nascimento'] ??
          member['nascimento'],
    );
    final adm = _fmtDate(
      member['DATA_MEMBRO'] ??
          member['dataMembro'] ??
          member['dataAdmissao'] ??
          member['data_admissao'] ??
          member['DATA_ADMISSAO'] ??
          member['admissao'],
    );
    final assinadaEm = member['carteirinhaAssinadaEm'];
    final assinadaPorNome =
        (member['carteirinhaAssinadaPorNome'] ?? '').toString().trim();
    final assinaturaUrl =
        (member['carteirinhaAssinaturaUrl'] ?? '').toString().trim();
    final assinada = assinadaEm != null ||
        assinadaPorNome.isNotEmpty ||
        assinaturaUrl.isNotEmpty;

    return MemberCardCnhViewData(
      tenantId: tenantId,
      memberId: memberId,
      nome: nome.isEmpty ? '—' : nome,
      cpf: _formatCpf(cpfRaw),
      codigoMembro: _memberCode(member, memberId),
      igrejaSede: _churchSede(tenant, churchSubtitle),
      dataNascimento: nasc.isEmpty ? '—' : nasc,
      validade: _validityLabel(member),
      filiacao: walletFiliacaoFromMember(member).trim().isEmpty
          ? '—'
          : walletFiliacaoFromMember(member),
      dataAdmissao: adm.isEmpty ? '—' : adm,
      categoria: _categoria(member, cargoLabel),
      churchTitle: churchTitle.trim().isEmpty ? 'Gestão YAHWEH' : churchTitle,
      churchSubtitle: churchSubtitle.trim().isEmpty
          ? 'Credencial de membro'
          : churchSubtitle,
      qrPayload: qrPayload,
      assinada: assinada,
      assinadaPorNome: assinadaPorNome,
      assinadaPorCargo:
          (member['carteirinhaAssinadaPorCargo'] ?? '').toString().trim(),
    );
  }
}
