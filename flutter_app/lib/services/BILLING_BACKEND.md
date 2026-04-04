# Backend (Cloud Functions) — Pagamento e planos

## createMpPreapproval

O app envia os parâmetros:

- `planId` (string)
- `billingCycle`: `"monthly"` ou `"annual"` (planos mensais e anuais)
- `paymentMethod`: `"pix"` ou `"card"`
- `installments` (opcional, número): parcelas no cartão; padrão 6 (cartão em 6x)

**Recomendações no backend:**

1. Aceitar `billingCycle`, `paymentMethod` e `installments` no body da callable.
2. Gravar no Firestore a intenção (ex.: `subscription_intents/{id}`) com: `igrejaId`, `planId`, `billingCycle`, `paymentMethod`, `installments` (se cartão), `status: 'pending'`, `createdAt`.
3. Montar a preferência do Mercado Pago conforme:
   - **PIX**: incluir método de pagamento PIX.
   - **Cartão**: incluir cartão parcelado em até 6x (`installments: 6` quando enviado pelo app).
   - **Mensal**: usar `priceMonthly` do plano.
   - **Anual**: usar preço anual (campo `priceAnnual` em `config/plans/items/{planId}` ou calcular 10× mensal para 12 por 10).
4. Após confirmação do pagamento (webhook), gravar em `subscriptions` e atualizar licenças.

Fluxo: escolha no painel (PIX ou Cartão 6x, Mensal ou Anual) → checkout MP → webhook atualiza licenças.
