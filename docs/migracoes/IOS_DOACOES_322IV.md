# iOS — Doações (Guideline 3.2.2(iv)) — só Gestão YAHWEH

> **Controle Total** e **Moova Super Premium** **não têm** módulo de
> dízimos/ofertas no app. **Não aplicar** esta secção nesses projetos.
> Aplicar apenas o padrão de **licença/plano** (`IosPaymentsGate` +
> `IosPaymentUnavailableView`).

---

## Problema Apple (exemplo real — maio/2026)

**Guideline 3.2.2(iv)** — «arrecadação de doações beneficentes dentro do app».

A Apple aceita:

- Doações **fora** do app, com **link para o site** que abre o **Safari**
  (navegador padrão ou `SFSafariViewController`).
- Organização **sem fins lucrativos** aprovada Benevity/Candid (não é o
  caso típico de um SaaS B2B para igrejas).

**Gestão YAHWEH** não é ONG beneficente: é **software de gestão**; as
igrejas recebem dízimos/ofertas dos membros — mesmo assim a Apple trata
checkout de doação **dentro do binário iOS** como sensível.

---

## Solução implementada (Gestão YAHWEH)

| Plataforma | Módulo menu **Doação** |
|------------|------------------------|
| **Android** | `ChurchDonationsPage` — PIX/cartão no painel (Mercado Pago) |
| **Web** | Igual |
| **iOS nativo** | **Não** mostra formulário de doação. Mostra `IosDonationReaderView` e abre **Safari** em `{publicWebBaseUrl}/igreja/{slug}?from=ios_app&utm_medium=church_donation` |

O utilizador contribui no **site público da igreja** (botão doação / PIX /
ofertas já existentes na web).

### Ficheiros (YAHWEH)

```
flutter_app/lib/ui/widgets/ios_donation_reader_view.dart   # NOVO
flutter_app/lib/services/ios_payments_gate.dart            # + openChurchDonationsExternally
flutter_app/lib/ui/igreja_clean_shell.dart                 # case 23 → IosDonationReaderView se iOS
flutter_app/lib/ui/pages/church_donations_page.dart        # guard no build (defesa)
flutter_app/lib/ui/church_public_page.dart               # já: doação → Safari iOS
flutter_app/lib/ui/site_publico_igreja/church_public_donation_sheet.dart  # checkout MP → Safari iOS (se abrir sheet noutro fluxo)
```

### API do gate

```dart
IosPaymentsGate.openChurchDonationsExternally(
  churchSlug: slug,
  churchData: churchDocData, // opcional — domínio customizado
);
```

---

## Controle Total / Moova — o que fazer

| App | Módulo doações? | Acção |
|-----|-----------------|--------|
| **Controle Total** | ❌ Não | **Ignorar** esta migração. Só licença + `IosPaymentsGate`. |
| **Moova Super Premium** | ❌ Não | **Ignorar** esta migração. Licença motorista + `/login/apple` no site. |
| **Gestão YAHWEH** | ✅ Sim | Manter `IosDonationReaderView` em todo build iOS para revisão. |

Se no futuro outro app ganhar doações:

1. Copiar `ios_donation_reader_view.dart` (adaptar textos e URL).
2. Adicionar `openChurchDonationsExternally` ao gate local.
3. Interceptar o índice do menu / rota no shell com `IosPaymentsGate.isIosNative`.

---

## Texto sugerido — App Store Connect (YAHWEH, inglês)

> Regarding Guideline 3.2.2(iv): our app is **B2B church management
> software**, not a charitable organization. On **iOS**, we **removed
> in-app donation collection**. The “Donation” menu item only **opens
> the church’s public website in Safari**, where users may contribute
> via PIX or card — the same flow available on the web. **Android** keeps
> the in-app donation tools for church treasurers.

---

## Checklist antes de reenviar iOS (YAHWEH)

- [ ] Build iOS com `IosDonationReaderView` (não `ChurchDonationsPage` no iPhone).
- [ ] Testar: Menu **Doação** → Safari → site `/igreja/{slug}` → botão doação no site.
- [ ] Capturas iOS **sem** ecrã de PIX/cartão de dízimo **dentro** da app.
- [ ] Notas de revisão atualizadas (`flutter_app/docs/app_store_review_notes.md` §3.2.2).

---

## Estado da revisão (referência interna)

- **Licença / plano da plataforma (3.1.x):** caminho Reader + Safari — em
  validação / aprovado conforme build enviado.
- **Doações (3.2.2(iv)):** corrigido em código; requer **novo build** após
  rejeição que cite apenas doações.

_Última atualização: 2026-05-18 — build referência `11.2.295+1577`; próximo iOS com doações Safari-only._
