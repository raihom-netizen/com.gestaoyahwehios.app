# Mural de eventos e avisos — 30 dias no Firebase, depois Drive

## Comportamento

1. **Primeiros 30 dias**: Publicações do mural (avisos e eventos) ficam no **Firebase** (Firestore `igrejas/{tenantId}/noticias` e mídia no Storage). O mural exibe normalmente (feed estilo Instagram).

2. **Após 30 dias**: Uma Cloud Function agendada (`archiveChurchMediaToDrive`, todo dia às 00:20 BRT) migra as **mídias** (imagem e vídeo) para o **Google Drive** e remove do Storage. O documento do post no Firestore é atualizado:
   - `imageUrl` / `videoUrl` passam a apontar para o link do Drive (visualização continua no mural).
   - São gravados também `imageUrlDriveFileId`, `imageUrlDriveViewUrl`, `archivedToDriveAt`, `archivedCreatedByCpf`, etc.

3. **Estrutura no Drive** (ID raiz configurável, ex.: `1_MUqq_vmocRNfliev_akaeoj6Uu8xaYH`):
   - **Raiz** → pasta **Igrejas** → **uma pasta por igreja** (nome do tenant ou tenantId_CPF do criador da igreja) → **midias_arquivadas** → **YYYY-MM** (mês do post).
   - Cada arquivo no Drive tem na descrição o **CPF de quem lançou** o post (`lancado_por_CPF: xxx`).
   - A coleção `drive_archives` no Firestore guarda `tenantId`, `postId`, `createdByCpf`, `createdByUid`, `driveDirectUrl`, etc., para rastreio.

4. **Mural continua igual**: O app continua lendo `igrejas/{tenantId}/noticias`. Como `imageUrl` e `videoUrl` são atualizados para o link do Drive após a migração, o feed segue mostrando imagem e o botão "Assistir vídeo" abre o vídeo no Drive. Nada some do mural; só o caminho da mídia que muda (Firebase → Drive).

## Configuração

- **DRIVE_CHURCH_ROOT_ID**: ID da pasta raiz no Google Drive (ex.: `1_MUqq_vmocRNfliev_akaeoj6Uu8xaYH`). Configure nas variáveis do projeto (Firebase Functions config).
- **MEDIA_RETENTION_DAYS**: Número de dias no Firebase antes de migrar (padrão **30**).

## Mural tipo Instagram

- Abas **Avisos** e **Eventos**.
- Cards com avatar, data/hora, título, imagem (ou link para vídeo), texto, local (eventos), compartilhar no WhatsApp, copiar texto, comentários (eventos).
- Quem tem permissão (gestor/adm/líder) pode editar; líder só o que criou.
