# Melhor estratégia: igreja livre para fotos e vídeos com baixo custo

Objetivo: **dar liberdade** para a igreja anexar fotos e vídeos, mantendo **custo mensal baixo e previsível**.

---

## 1. O que você já faz bem (manter)

| Prática | Onde está | Efeito |
|--------|------------|--------|
| **Redução de foto no app** | Mural e Eventos: `maxWidth: 1200`, `imageQuality: 80` | Foto sobe já comprimida → menos armazenamento e menos egress |
| **Migração para Drive em 15 dias** | Cloud Function `archiveChurchMediaToDrive` (parâmetro `MEDIA_RETENTION_DAYS=15`) | Só ~15 dias de mídia no Firebase → custo de Storage baixo |
| **Limite de tamanho no Storage** | `storage.rules`: 10 MB por arquivo (imagem) | Evita uploads gigantes que disparam custo |

Ou seja: **continue** com compressão no cliente e arquivamento no Drive.

---

## 2. Estratégias recomendadas (por impacto)

### A) Fotos: padronizar compressão em todo o app (alto impacto, baixo esforço)

- **Onde:** Mural, Eventos, Cadastro da Igreja (logo), Patrimônio, Departamentos, etc.
- **Regra única:** antes de subir para o Storage, **sempre** usar:
  - `maxWidth` ou `maxHeight`: **1200 px** (ou 1024 para telas pequenas)
  - `imageQuality`: **75–80**
- **Efeito:** Todas as fotos ficam em tamanho moderado (ex.: 200–600 KB em vez de 3–5 MB) → menos armazenamento e **bem menos egress** (que é o que mais custa no Firebase).

**Resumo:** Igreja continua “livre” para anexar quantas fotos quiser; o custo por foto cai porque cada uma fica menor.

---

### B) Thumbnails no feed (médio impacto, médio esforço)

- **Ideia:** No mural/feed, exibir uma **miniatura** (ex.: 400–500 px de largura) em vez da imagem em tamanho cheio.
- **Como:**  
  - Opção 1: ao fazer upload, gerar no app (ou em Function) uma versão pequena e salvar como `thumb_...` no Storage. No feed, carregar só a thumbnail. Ao abrir o post, carregar a imagem “cheia” (ou o link do Drive).  
  - Opção 2: usar a mesma imagem mas com parâmetros de resize na URL (se no futuro usar um serviço que suporte isso).
- **Efeito:** A maior parte do tráfego vira download de thumbnail (poucos KB por visualização) em vez de imagem grande → **redução forte de egress** e custo.

---

### C) Vídeos: duas linhas possíveis (escolher uma)

**Opção 1 – Vídeo como link (custo zero de Storage para vídeo)**  
- Igreja não sobe vídeo no app; sobe no **YouTube** (ou Vimeo) e cola o **link** no post/evento.  
- App só guarda a URL e exibe o player (iframe ou `url_launcher`).  
- **Vantagem:** Custo de vídeo no Firebase = 0. Igreja continua “livre” para usar vídeo.  
- **Desvantagem:** Depende de a igreja ter conta YouTube e aceitar o fluxo.

**Opção 2 – Upload de vídeo com limite e ida direto para o Drive**  
- Permitir upload de vídeo no app com **limite** (ex.: 1–2 min ou 50–100 MB por arquivo).  
- Em vez de salvar no Firebase Storage, a **Cloud Function** recebe o upload (ou um signed URL) e envia o arquivo direto para o **Google Drive** (como já faz com mídia arquivada). No Firestore fica só a URL do Drive.  
- **Vantagem:** Vídeo nunca passa pelo Storage do Firebase → custo de vídeo no Firebase = 0. Igreja anexa vídeo “dentro” do app.  
- **Desvantagem:** Exige implementar fluxo de upload para Drive (ou via Function).

Recomendação prática: **curto prazo** = Opção 1 (link YouTube); **médio prazo** = Opção 2 se quiser “upload de vídeo” nativo com custo baixo.

---

### D) Encurtar permanência no Firebase (opcional)

- Hoje: mídia fica **30 dias** no Firebase e depois vai para o Drive.  
- Se quiser **reduzir mais** o custo: diminuir para **15 dias** (ex.: alterar `MEDIA_RETENTION_DAYS` para 15).  
- **Efeito:** Metade do “estoque” de mídia no Firebase → menos GB armazenados e um pouco menos de egress nos primeiros 15 dias.  
- **Trade-off:** Conteúdo mais novo continua no Firebase; só encurta a janela.

---

### E) Limites por plano (evitar abuso, custo previsível)

- Manter a igreja **livre** dentro de um teto razoável, por plano. Exemplo (só como referência):

| Plano     | Fotos/mês (sugestão) | Vídeos/mês (se tiver upload) | Tamanho máx. vídeo |
|----------|-----------------------|-------------------------------|---------------------|
| Inicial  | 150                   | 10                            | 50 MB               |
| Essencial| 250                   | 20                            | 80 MB               |
| Maiores  | 500+                  | 30+                           | 100 MB              |

- **Implementação:** no app, ao criar post/evento, contar quantas fotos/vídeos a igreja já enviou no mês (Firestore) e, se passar do limite, mostrar mensagem amigável (“Este mês você já enviou X fotos; limite do seu plano é Y”).  
- **Efeito:** Custo por igreja fica **limitado e previsível**; ao mesmo tempo a igreja continua com boa liberdade (150 fotos + 10 vídeos já é bastante).

---

## 3. Ordem sugerida de implementação

1. **Imediato (já em parte feito):**  
   - Garantir **compressão de foto** (maxWidth 1200, quality 75–80) em **todos** os pontos do app que fazem upload de imagem (mural, eventos, logo, patrimônio, departamentos, etc.).

2. **Curto prazo:**  
   - Oferecer **vídeo por link** (YouTube/Vimeo) nos posts/eventos, com campo “Link do vídeo” e exibição no app.  
   - (Opcional) Reduzir `MEDIA_RETENTION_DAYS` para 15 se quiser cortar mais custo.

3. **Médio prazo:**  
   - **Thumbnails** no feed (gerar miniatura no upload ou na Function; feed carrega só thumbnail).  
   - **Limites por plano** (fotos/vídeos por mês) para manter custo previsível sem tirar a “liberdade” da igreja.

4. **Se quiser upload de vídeo no app:**  
   - Fluxo que envia vídeo **direto para o Drive** (ou via Function), sem passar pelo Firebase Storage.

---

## 4. Resumo em uma frase

**Melhor estratégia:** igreja **livre** para anexar fotos e vídeos dentro de **limites por plano**; **fotos sempre comprimidas** no app; **vídeos** por **link** (YouTube) ou por **upload direto para o Drive**; **feed** usando **thumbnail** para reduzir egress; **manter** migração para Drive em 30 (ou 15) dias. Assim o custo fica baixo e previsível sem limitar demais o uso.
