# Referência para limpeza manual de artefactos legados no Firebase Storage (Gestão YAHWEH).
# Requer: Google Cloud SDK (gsutil), autenticado para o projeto.
#
# 1) Inspecionar o bucket (substitua pelo storageBucket do Firebase, ex. projeto.appspot.com):
#    gsutil ls "gs://SEU_BUCKET/igrejas/"
#
# 2) Pastas thumbs/ (ajuste o prefixo após listar):
#    gsutil -m rm -r "gs://SEU_BUCKET/igrejas/ID_DA_IGREJA/.../thumbs"
#
# 3) Nomes com sufixos legados (revisar com gsutil ls antes de apagar):
#    gsutil ls "gs://SEU_BUCKET/igrejas/**/*_scaled*"
#    gsutil ls "gs://SEU_BUCKET/igrejas/**/*_card*"
#
# O wildcard ** pode não funcionar em todas as versões do gsutil no Windows;
# use caminhos explícitos ou copie os comandos para Cloud Shell.
param(
  [string] $Bucket = ""
)

if ($Bucket -eq "") {
  Write-Host "Abra este ficheiro e siga os comentários no topo (sem bucket definido, nada é executado)." -ForegroundColor Yellow
  exit 0
}

Write-Host "Bucket gs://$Bucket — use os exemplos no topo do script após inspeção com gsutil ls." -ForegroundColor Cyan
