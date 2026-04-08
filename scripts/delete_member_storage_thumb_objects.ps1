# Lista objetos em igrejas/*/membros/* cujo nome contem "thumb" e remove (exceto se quiser filtrar manualmente).
# Requer: gcloud CLI com Storage. Bucket: gestaoyahweh-21e23.firebasestorage.app
# AVISO: Revise a lista antes de descomentar a remocao em massa.

$ErrorActionPreference = 'Continue'
$bucket = 'gs://gestaoyahweh-21e23.firebasestorage.app'

if (-not (Get-Command gcloud -ErrorAction SilentlyContinue)) {
    Write-Error 'gcloud nao encontrado.'
}

Write-Host 'Buscando objetos com "thumb" no caminho igrejas/*/membros/ ...'
# gcloud storage ls recursive (formato moderno)
$prefix = "$bucket/igrejas/"
gcloud storage ls --recursive "$prefix**" 2>$null | Where-Object { $_ -match '/membros/' -and $_ -match 'thumb' } | ForEach-Object {
    Write-Host $_
    # gcloud storage rm "$_"
}

Write-Host 'Concluido (somente listagem). Para apagar, edite o script e descomente gcloud storage rm.'
