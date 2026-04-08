# GESTÃO YAHWEH — PACOTE PRODUÇÃO (IGREJAS)

Crédito oficial: **Raihom Barbosa** (idealizador e responsável pelo sistema)

Mensagem bíblica oficial:
**Provérbios 16:3**
> Consagre ao Senhor tudo o que você faz, e os seus planos serão bem-sucedidos.

## Deploy Produção (PowerShell)
1. Functions + Firestore (rules/indexes)
2. Build Web + Hosting

Veja scripts em `scripts/`:
- DEPLOY_PRODUCAO_YAHWEH.ps1
- BUILD_ANDROID_YAHWEH.ps1
- RUN_TUDO.ps1
- GERAR_ZIP_TOTAL.ps1

## Regras de vídeo
- Galeria: **até 90 segundos**
- Acima disso: publicar no YouTube e inserir o link/canal.

## Endpoints
- resolveCpfToChurchPublic (HTTP): `https://us-central1-gestaoyahweh-21e23.cloudfunctions.net/resolveCpfToChurchPublic?cpf=<CPF>`
