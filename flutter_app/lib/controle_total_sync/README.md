# Sincronização Controle Total → Gestão YAHWEH

Pasta com código portado do **Controle Total App** (lançamento expresso / SMS, parcelas no texto,
máscara em tempo real, clipboard com imagem, parser de banco, partição PDF produtividade).

## Conteúdo

| Ficheiro | Função |
|----------|--------|
| `currency_formats.dart` | `CurrencyFormats.formatBRL` (máscara / exibição R$) |
| `date_time_formats.dart` | Datas `dd/MM/yyyy` pt_BR |
| `finance_bank_presets.dart` | Presets de banco para `BankNotificationParser` |
| `bank_notification_parser.dart` | Parse de SMS, CSV, fatura, parcelas no texto, `parseManyForBatch` |
| `produtividade_ocorrencias_pdf_partition.dart` | Partição sem folga / usadas folga (relatórios PDF) |
| `smart_input_live_mask.dart` | Máscara `d/m`→ano + centavos início/fim (campo texto) |
| `smart_input_clipboard_paste_*.dart` | Colar imagem (web + `dart:io` com `super_clipboard`) |

## Android / iOS / Web — paridade

| Funcionalidade | Web | Android | iOS |
|----------------|-----|---------|-----|
| Máscara `SmartInputLiveMask` | Sim | Sim | Sim |
| Parser SMS / CSV / parcelas | Sim | Sim | Sim |
| Colar **imagem** (print) — botão «Colar» | `dart:html` + listener paste | `super_clipboard` + teclado: `ContentInsertionConfiguration` | `super_clipboard` (teclado raro; use «Colar») |
| Colar texto | `Clipboard` / API web | `Clipboard` | `Clipboard` |
| OCR de imagem (ML Kit) | Textify (Dart) | ML Kit | ML Kit |

- **Máscara e parser**: Dart puro — todas as plataformas.
- **Clipboard imagem (nativo)**: `pubspec.yaml` com `super_clipboard`; primeira build Android pode compilar NDK das extensões nativas.
- **Ditado** (se integrar ecrã completo): Android — `RECORD_AUDIO` no manifest; iOS — `NSSpeechRecognitionUsageDescription` + `NSMicrophoneUsageDescription` no `Info.plist` (como no Controle Total).

## Integração no app Yahweh

1. `flutter pub get`
2. Importar onde precisar, por exemplo:
   - `import 'package:gestao_yahweh/controle_total_sync/smart_input_live_mask.dart';`
   - `import 'package:gestao_yahweh/controle_total_sync/bank_notification_parser.dart';`
3. No ecrã de lançamento rápido, usar import condicional como no Controle Total:
   - `smart_input_clipboard_paste_stub.dart` + `if (dart.library.html) web` + `if (dart.library.io) io`
4. `ContentInsertionConfiguration` no `TextField` (colagem de imagem pelo teclado no Android).

## Próximos passos (não incluídos aqui)

- Ecrã completo tipo `SmartInputScreen`, `RelatorioService`, Firestore `ocorrencias` / `reminders` — copiar do repositório Controle Total se/quando o fluxo financeiro Yahweh for alinhado ao mesmo modelo de dados.

Última cópia manual a partir de: `Controletotalapp_Independente/flutter_app/lib`.
