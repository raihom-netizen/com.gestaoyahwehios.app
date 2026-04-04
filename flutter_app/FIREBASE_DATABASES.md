# Separação dos bancos Firestore — Gestão YAHWEH

## Estrutura

| Banco        | Uso |
|-------------|-----|
| **(default)** | Coleção raiz **igrejas** (cada igreja e seu gestor); subscriptions, users, relatorios, publicCpfIndex, etc. |
| **frotasveiculo** | Frota: frota_veiculos, frota_licenses, frota_manutencao, frota_motoristas, frota_abastecimentos, frota_combustiveis, usuarios (frota). |

O app usa apenas o banco **(default)** para dados de igreja e apenas **frotasveiculo** para dados de frota.

## Padrão: tudo vinculado dentro de cada igreja

Cada igreja é um documento em **`igrejas/{igrejaId}`**. Todo o conteúdo da igreja fica em **subcoleções** desse documento, vinculado ao gestor e à igreja:

| Subcoleção | Conteúdo |
|------------|----------|
| **membros** | Cadastro de membros (substitui "members") |
| **noticias** | Mural de avisos / notícias (com comentarios) |
| **eventos** | Eventos; fotos e vídeos no Storage em `igrejas/{id}/eventos/` |
| **event_templates** | Modelos de evento |
| **patrimonio** | Patrimônio; fotos em `igrejas/{id}/patrimonio/` |
| **finance** / **contas** / **categorias_despesas** / **despesas_fixas** | Financeiro; comprovantes em `igrejas/{id}/comprovantes/` |
| **escalas** / **escala_templates** | Escalas de culto/serviço |
| **departamentos** | Departamentos; fotos em `igrejas/{id}/departamentos/` |
| **cargos** | Cargos/funções |
| **visitantes** (e followups) | Visitantes e acompanhamento |
| **cultos** / **presencas** | Cultos e presença |
| **pedidosOracao** | Pedidos de oração |
| **config** | Configurações da igreja (ex.: carteira) |
| **users** | Usuários com acesso ao painel da igreja |
| **usersIndex** | Índice de usuários |

**Storage:** Fotos e vídeos da igreja ficam em **`igrejas/{igrejaId}/...`** (membros, noticias, eventos, patrimonio, departamentos, comprovantes, etc.).

## Correção automática do banco (recomendado)

1. Faça **deploy** das regras e das Cloud Functions (na raiz do projeto):
   ```bash
   firebase deploy
   ```
   Ou só Firestore + Functions:
   ```bash
   firebase deploy --only firestore,functions
   ```

2. No app, entre como **MASTER** (raihom@gmail.com ou usuário ADM), vá em **Painel Admin** → **Frotas** → **Licenças Frota**. No canto superior direito, clique no ícone **Storage** (banco) e confirme **Corrigir banco**. Isso vai:
   - Migrar todos os dados de frota do banco **(default)** para **frotasveiculo**
   - Apagar do **(default)** as coleções: `frota_licenses`, `frota_manutencao`, `frota_motoristas`, `frota_veiculos`, `frota_abastecimentos`, `frota_combustiveis`, `frotas`

3. O banco **(default)** fica só com igrejas; o banco **frotasveiculo** fica com toda a frota.

## Limpeza manual (alternativa)

Se preferir apagar manualmente no Console:

1. Acesse [Firebase Console](https://console.firebase.google.com) → projeto **GESTAOYAHWEH**.
2. Firestore Database → banco **(default)**.
3. Apague as coleções de frota listadas acima (após migrar os dados, se precisar).

Os dados novos de frota passam a ser gravados apenas no banco **frotasveiculo**. Para ver/gerir frota, no Firestore selecione o banco **frotasveiculo**.
