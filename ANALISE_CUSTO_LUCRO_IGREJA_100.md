# Análise: custo mensal e lucro — igreja com 100 membros (fotos, vídeos, etc.)

## 1. Plano e receita

Para **até 100 membros**, o plano indicado no sistema é o **Plano Inicial**:

| Item            | Valor        |
|-----------------|--------------|
| Preço mensal    | **R$ 49,90** |
| Preço anual (12 por 10) | R$ 499,00 |

**Receita mensal por igreja de 100 membros (plano mensal): R$ 49,90**

---

## 2. Uso estimado por igreja (100 membros) — fotos, vídeos, etc.

Estimativa conservadora de uso **por mês** por igreja:

| Tipo de uso              | Quantidade estimada | Tamanho médio   | Volume/mês   |
|--------------------------|---------------------|-----------------|-------------|
| Fotos (eventos, avisos, perfis) | 80–150 fotos        | 1–2 MB cada     | ~150 MB     |
| Vídeos (eventos, avisos)       | 5–15 vídeos         | 30–80 MB cada   | ~400 MB     |
| **Total upload (novo)**        |                     |                 | **~550 MB** |
| Visualizações (download)       | 100 membros vendo feed | ~5–15 GB egress | **~8 GB**   |

Observação: no seu sistema, após **30 dias** as mídias do mural são migradas para o **Google Drive** (ver `MURAL_E_DRIVE.md`). No Firebase Storage ficam, em regime estável, basicamente só os **últimos 30 dias** de mídia. Isso reduz o custo de armazenamento no Firebase.

---

## 3. Custo mensal estimado (Firebase) por igreja

Preços Firebase em USD (Blaze); conversão aproximada **1 USD ≈ R$ 5,50**.

| Serviço        | Uso estimado por igreja/mês | Faixa de custo (USD) | Em R$ (aprox.) |
|----------------|-----------------------------|----------------------|----------------|
| **Firestore**  | Leituras/escritas moderadas (app + painel) | Dentro do free tier ou ~US$ 0,50 | R$ 0 – 2,75   |
| **Storage**    | ~1–2 GB armazenados (30 dias no Firebase)  | ~US$ 0,03–0,06       | R$ 0,20 – 0,35 |
| **Storage**    | Download (egress) ~8 GB                      | ~US$ 0,96            | R$ 5,30       |
| **Functions**  | Invocações (webhook, migração, etc.)        | Free tier ou baixo   | R$ 0 – 1,00   |
| **Hosting**    | Tráfego do app/site                         | Geralmente baixo     | R$ 0 – 1,00   |

**Custo total estimado por igreja de 100 membros (com fotos e vídeos): entre R$ 6 e R$ 12 por mês**, dependendo de leituras Firestore e tráfego. Um valor central razoável é **~R$ 9/mês**.

(Se a igreja subir muito o uso de vídeos e visualizações, o egress pode aumentar; o custo pode ir para algo como R$ 12–18/mês.)

---

## 4. Lucro mensal por igreja de 100 membros

| Conceito        | Valor (R$/mês) |
|-----------------|----------------|
| Receita (plano) | 49,90          |
| Custo infra     | -9,00 (média)  |
| **Lucro**       | **~R$ 41/mês** |

Ou seja: **cerca de R$ 41 de lucro por igreja de 100 membros**, na hipótese de uso “normal” com fotos e vídeos e migração para Drive após 30 dias.

---

## 5. Resumo e observações

- **Plano usado:** Plano Inicial (até 100 membros) = **R$ 49,90/mês**.
- **Custo mensal estimado** para essa igreja (fotos, vídeos, etc.): **~R$ 6–12** (média **~R$ 9**).
- **Lucro mensal estimado:** **~R$ 41** por igreja.
- A política de **arquivar mídia no Drive após 30 dias** ajuda a manter o custo de Storage no Firebase baixo.
- Se muitas igrejas usarem bastante vídeo e visualizações, vale monitorar o **egress** do Storage no Firebase Console e, se quiser, definir limites ou orientar uso (ex.: vídeos mais curtos, menos resolução).

Os valores acima são **estimativas**; o custo real depende do uso real no Firebase (Firestore, Storage, Functions, Hosting). Para números exatos, use o **Firebase Console** → Uso e faturamento.
