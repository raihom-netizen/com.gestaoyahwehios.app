# Como atualizar o ícone do PWA (Web App) — instalador web

1. Coloque o novo ícone em: flutter_app/assets/icon/app_icon.png
   (um único arquivo PNG; recomendado 512x512 px ou maior).

2. Regenerar os ícones da web (OBRIGATÓRIO após trocar app_icon.png):
   Na pasta flutter_app, execute um dos seguintes:

   Opção A — Script (recomendado):
   .\scripts\atualizar_icone_web.ps1
   ou (duplo clique): scripts\atualizar_icone_web.bat

   Opção B — Comando manual:
   flutter pub get
   dart run flutter_launcher_icons

   Isso sobrescreve em web/icons/:
   - Icon-192.png, Icon-512.png
   - Icon-maskable-192.png, Icon-maskable-512.png
   (e favicon na raiz de web/ se aplicável)

3. Build e deploy:
   flutter build web --release
   firebase deploy --only hosting  (ou seu método de deploy)

4. Se o ícone antigo ainda aparecer no "Instalar app":
   - Desinstale o PWA do celular (remover atalho "Gestão YAHWEH").
   - Acesse o site de novo e use "Adicionar à tela inicial" / "Instalar app".
   O instalador web passará a usar o ícone de assets/icon/app_icon.png.
