# Checklist venda — Brasil para Cristo (producao)

**Tenant:** `brasilparacristo_sistema` | **Web:** https://gestaoyahweh-21e23.web.app

## Antes de abrir para a igreja (hoje)

```powershell
cd c:\gestao_yahweh_premium_final
.\scripts\producao_alinhamento_rapido.ps1
```

Isto faz: gate producao, GCP + regras Firebase, CORS Storage, functions piloto, web hosting.

## Login gestor piloto

1. Email: `raihom@gmail.com` (ou gestor configurado)
2. Se nao entrar na igreja: botao **Garantir meu acesso (Brasil para Cristo)** no ecran de login
3. Console Firebase: projeto `gestaoyahweh-21e23`

## Validar rapido (15 min)

| Teste | Esperado |
|-------|----------|
| Painel igreja | Abre em < 2s (cache `_panel_cache`) |
| Lista membros | 20 itens + Carregar mais |
| Novo membro + foto | Grava Firestore; foto sobe em background |
| Aviso com foto | Publica sem travar UI |
| Chat texto | Envio optimista instantaneo |
| Web fotos Storage | `SafeNetworkImage` (CORS aplicado) |

## Android / iOS

- Android: AAB ultimo em `D:\Temporarios` ou build local
- iOS: Codemagic apos push; TestFlight conforme pipeline

## Se algo falhar

| Sintoma | Acao |
|---------|------|
| permission-denied | `.\scripts\deploy_firebase_rules.ps1 -ForcePublish` |
| Foto web nao carrega | `.\scripts\apply_firebase_storage_cors.ps1` |
| API Rules 503 | Aguardar ou `.\scripts\firebase_rules_gcp_watchdog.ps1 -StartBackground` |
| Painel lento | Menu > Saude do Sistema; verificar rede |

## Referencia

- `prompt_mestre_cursor.md` §6 (regras) e §12–19 (performance)
- `docs/PRODUCAO_PREMIUM_MISSAO.md`
