# Migra todas as igrejas: noticias→eventos, chat_threads→chats (Cloud Function).
# Requer: firebase login, functions deployadas, utilizador master.
param(
  [int]$Limit = 200
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ensure_gestao_yahweh_toolchain_path.ps1"

Write-Host "A chamar migrateAllTenantsFirestoreCollections (limit=$Limit)..." -ForegroundColor Cyan
firebase functions:call migrateAllTenantsFirestoreCollections --data "{`"limit`":$Limit}" --project gestaoyahweh-21e23
Write-Host "Concluido. Verifique logs no Firebase Console > Functions." -ForegroundColor Green
