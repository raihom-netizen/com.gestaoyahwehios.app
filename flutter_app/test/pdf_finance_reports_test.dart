import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/pdf.dart';

import 'package:gestao_yahweh/pdf/finance_vinculo_extrato_pdf.dart';
import 'package:gestao_yahweh/pdf/fornecedor_historico_pdf.dart';
import 'package:gestao_yahweh/pdf/membros_financeiro_geral_pdf.dart';
import 'package:gestao_yahweh/ui/pages/membros_financeiro_geral_page.dart';
import 'package:gestao_yahweh/utils/report_pdf_branding.dart';

/// Relatórios financeiros em PDF.
///
/// O primeiro teste é a rede de segurança do defeito que motivou a revisão: a
/// coluna «Data» tinha 56pt, «25/08/2026» precisa de 61pt, e o relatório saía
/// com a data partida ao meio («25/08/202 6»). Largura de coluna não se
/// arbitra a olho — mede-se com a fonte que o PDF usa.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => initializeDateFormatting('pt_BR'));

  const branding = ReportPdfBranding(
    churchName: 'Igreja Teste',
    accent: PdfColor.fromInt(0xFF1D4ED8),
    churchDetailLines: ['CNPJ 00.000.000/0001-00', 'Rua Teste, 100'],
  );

  test('colunas fixas comportam data e dinheiro sem quebrar', () async {
    final doc = PdfDocument();
    final regular = PdfTtfFont(
      doc,
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final negrito = PdfTtfFont(
      doc,
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );

    // PdfSuperPremiumTheme: célula 8.65pt, recuo horizontal de 8pt de cada lado.
    const corpo = 8.65;
    double precisa(String s, PdfFont f) => f.stringMetrics(s).width * corpo + 16;

    final colunas = <String, ({double precisa, double tem})>{
      'extrato/data': (precisa: precisa('25/08/2026', regular), tem: 64),
      'extrato/tipo': (precisa: precisa('Despesa', regular), tem: 54),
      'extrato/status': (precisa: precisa('Pendente', regular), tem: 58),
      'extrato/valor': (precisa: precisa(r'R$ 12.345,67', regular), tem: 70),
      'extrato/entradas': (precisa: precisa(r'R$ 12.345,67', regular), tem: 74),
      'extrato/% do total': (precisa: precisa('% do total', negrito), tem: 78),
      'geral/contribuiu': (precisa: precisa('Contribuiu', negrito), tem: 72),
      'geral/despesas': (precisa: precisa(r'R$ 12.345,67', regular), tem: 68),
      'geral/saldo': (precisa: precisa(r'R$ 12.345,67', regular), tem: 68),
      'fornecedor/data e hora': (
        precisa: precisa('22/07/2026 15:54', regular),
        tem: 96,
      ),
      'fornecedor/total': (precisa: precisa(r'R$ 12.345,67', regular), tem: 80),
    };

    final estreitas = [
      for (final e in colunas.entries)
        if (e.value.precisa > e.value.tem)
          '${e.key} (precisa ${e.value.precisa.toStringAsFixed(1)}pt, '
              'tem ${e.value.tem}pt)',
    ];
    expect(estreitas, isEmpty, reason: 'colunas estreitas: $estreitas');
  });

  test('extrato do membro gera PDF', () async {
    final bytes = await buildFinanceVinculoExtratoPdf(
      branding: branding,
      tipo: 'membro',
      nome: 'Amanda Peixoto Lacerda',
      periodoLabel: 'Ano de 2026',
      departamentos: const ['mulheres'],
      lancamentos: [
        {
          'tipo': 'receita',
          'categoria': 'Dízimos',
          'descricao': 'Dízimos AGOSTO/2026',
          'amount': 149.0,
          'data': '2026-08-25T05:48:00.000',
          'status': 'paid',
        },
        {
          'tipo': 'receita',
          'categoria': 'Dízimos',
          'descricao': 'Dízimos AGOSTO/2026',
          'amount': 50.0,
          'data': '2026-08-21T20:13:00.000',
          'status': 'paid',
        },
        {
          'tipo': 'despesa',
          'categoria': 'Ajuda social',
          'descricao': 'Cesta básica',
          'amount': 80.0,
          'data': '2026-07-02T10:00:00.000',
          'status': 'pending',
        },
      ],
    );
    expect(bytes.length, greaterThan(2000));
  });

  test('financeiro geral gera PDF com muitos membros', () async {
    final linhas = [
      for (var i = 0; i < 12; i++)
        MembroFinanceiroLinha(
          id: 'm$i',
          nome: 'Membro de Teste Número $i',
          sexo: i.isEven ? 'f' : 'm',
          departamentos: i.isEven ? const ['mulheres'] : const ['louvor'],
          idade: 30 + i,
        )
          ..receitas = 100.0 * (i + 1)
          ..despesas = 10.0 * i
          ..lancamentos = i + 1
          ..ultimoLancamento = DateTime(2026, 8, 25),
    ];
    final bytes = await buildMembrosFinanceiroGeralPdf(
      branding: branding,
      linhas: linhas,
      periodoLabel: 'Ano de 2026',
      filtroLabel: 'Todos os membros',
    );
    expect(bytes.length, greaterThan(2000));
  });

  test('historico do fornecedor gera PDF', () async {
    final bytes = await buildFornecedorHistoricoPdf(
      branding: branding,
      fornecedorNome: 'RAIHOM SEVERINO BARBOSA',
      periodoLabel: 'Ano de 2026',
      lancamentos: [
        {
          'tipo': 'despesa',
          'categoria': 'Internet',
          'descricao': 'teste',
          'amount': 150.0,
          'data': '2026-07-22T10:00:00.000',
          'status': 'paid',
        },
      ],
      compromissos: [
        {
          'titulo': 'Visita tecnica',
          'dataVencimento': '2026-07-22T15:54:00.000',
          'status': 'pendente',
          'valorEstimado': 250.0,
        },
      ],
    );
    expect(bytes.length, greaterThan(2000));
  });

  test('financeiro geral sem membros nao rebenta', () async {
    final bytes = await buildMembrosFinanceiroGeralPdf(
      branding: branding,
      linhas: const [],
      periodoLabel: 'Ano de 2026',
      filtroLabel: 'Todos os membros',
    );
    expect(bytes.length, greaterThan(1000));
  });
}
