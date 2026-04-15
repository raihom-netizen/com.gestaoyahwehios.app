Migração MP bridges e índice de certificados (raiz → igrejas/{tenantId}/...)

O script está em: functions/tools/migrate_mp_bridges_para_igrejas.cjs
(usa firebase-admin da pasta functions; scripts/ tem "type":"module" e não convém .js CommonJS aqui)

Na raiz do repositório:
  cd functions
  node tools/migrate_mp_bridges_para_igrejas.cjs

Credenciais: GOOGLE_APPLICATION_CREDENTIALS ou ficheiro em secrets/ na raiz do repo.
