import 'package:flutter/material.dart';
import 'package:gestao_yahweh/services/church_signatory_load_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_digital_signature_stamp_preview.dart';
import 'package:gestao_yahweh/utils/pdf_digital_signature_stamp.dart';

/// Modo de assinatura — mesmo padrão Cartas (transferência / apresentação).
enum ChurchDocumentSignatureMode { digital, manual }

extension ChurchDocumentSignatureModeX on ChurchDocumentSignatureMode {
  bool get isDigital => this == ChurchDocumentSignatureMode.digital;
}

/// Resultado para PDFs oficiais (recibo, inventário, relatório).
class ChurchDocumentSignatureResult {
  const ChurchDocumentSignatureResult({
    required this.signer,
    required this.mode,
    this.digitalStamp,
  });

  final ChurchSignatoryEntry signer;
  final ChurchDocumentSignatureMode mode;
  final PdfDigitalStampInput? digitalStamp;

  bool get useDigital => mode.isDigital;
}

PdfDigitalStampInput? buildChurchDocumentDigitalStamp({
  required ChurchSignatoryEntry signer,
  required String churchName,
  Map<String, dynamic>? churchData,
}) {
  return PdfDigitalStampInput.now(
    signerName: signer.nome,
    signerCpfDigits: signer.cpfDigits,
    churchName: churchName,
    churchData: churchData,
  );
}

/// SegmentedButton + texto de ajuda (padrão carta de transferência).
class ChurchDocumentSignatureModeSelector extends StatelessWidget {
  const ChurchDocumentSignatureModeSelector({
    super.key,
    required this.mode,
    required this.onModeChanged,
    this.digitalHint =
        'Digital: selo compacto de certificado (igreja + assinante + data/hora).',
    this.manualHint =
        'Manual: espaço proporcional para assinatura à caneta no documento impresso.',
  });

  final ChurchDocumentSignatureMode mode;
  final ValueChanged<ChurchDocumentSignatureMode> onModeChanged;
  final String digitalHint;
  final String manualHint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ChurchDocumentSignatureMode>(
          segments: const [
            ButtonSegment<ChurchDocumentSignatureMode>(
              value: ChurchDocumentSignatureMode.digital,
              icon: Icon(Icons.draw_rounded),
              label: Text('Assinatura digital'),
            ),
            ButtonSegment<ChurchDocumentSignatureMode>(
              value: ChurchDocumentSignatureMode.manual,
              icon: Icon(Icons.edit_note_rounded),
              label: Text('Assinar manualmente'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (v) {
            if (v.isEmpty) return;
            onModeChanged(v.first);
          },
        ),
        const SizedBox(height: 6),
        Text(
          mode.isDigital ? digitalHint : manualHint,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

/// Pré-visualização do selo (só modo digital).
class ChurchDocumentSignaturePreviewCard extends StatelessWidget {
  const ChurchDocumentSignaturePreviewCard({
    super.key,
    required this.signer,
    required this.churchName,
    this.churchData,
  });

  final ChurchSignatoryEntry signer;
  final String churchName;
  final Map<String, dynamic>? churchData;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pré-visualização do selo',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: ChurchDigitalSignatureStampPreview(
              signerName: signer.nome,
              signerCpfDigits: signer.cpfDigits ?? '',
              churchName: churchName,
              churchData: churchData,
              cargo: signer.cargo,
            ),
          ),
        ],
      ),
    );
  }
}

/// Painel completo: modo + prévia (quando digital e há signatário).
class ChurchDocumentSignaturePanel extends StatelessWidget {
  const ChurchDocumentSignaturePanel({
    super.key,
    required this.mode,
    required this.onModeChanged,
    this.signer,
    this.churchName = '',
    this.churchData,
  });

  final ChurchDocumentSignatureMode mode;
  final ValueChanged<ChurchDocumentSignatureMode> onModeChanged;
  final ChurchSignatoryEntry? signer;
  final String churchName;
  final Map<String, dynamic>? churchData;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChurchDocumentSignatureModeSelector(
          mode: mode,
          onModeChanged: onModeChanged,
        ),
        if (mode.isDigital && signer != null)
          ChurchDocumentSignaturePreviewCard(
            signer: signer!,
            churchName: churchName,
            churchData: churchData,
          ),
      ],
    );
  }
}

/// Folha inferior — escolher modo após signatário (inventário / relatórios).
Future<ChurchDocumentSignatureResult?> showChurchDocumentSignatureModeSheet(
  BuildContext context, {
  required ChurchSignatoryEntry signer,
  required String churchName,
  Map<String, dynamic>? churchData,
  String title = 'Assinatura do documento',
}) async {
  var mode = ChurchDocumentSignatureMode.digital;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: StatefulBuilder(
          builder: (ctx, setSt) {
            return Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: ThemeCleanPremium.softUiCardShadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${signer.nome} — ${signer.cargo}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ChurchDocumentSignaturePanel(
                      mode: mode,
                      onModeChanged: (v) => setSt(() => mode = v),
                      signer: signer,
                      churchName: churchName,
                      churchData: churchData,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Continuar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    },
  );
  if (ok != true || !context.mounted) return null;
  return ChurchDocumentSignatureResult(
    signer: signer,
    mode: mode,
    digitalStamp: mode.isDigital
        ? buildChurchDocumentDigitalStamp(
            signer: signer,
            churchName: churchName,
            churchData: churchData,
          )
        : null,
  );
}
