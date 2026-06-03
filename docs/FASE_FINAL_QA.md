# Fase Final de Qualidade — Gestão YAHWEH



Diagnóstico arquitetural **fechado**. A partir daqui: **CORRIGIR → TESTAR** — sem novas funcionalidades, telas ou serviços paralelos.



## Regra multiplataforma (obrigatória)



Nenhuma correção está **concluída** sem validação em **Android + iOS + Web**.



**Falhou numa plataforma → RELEASE BLOQUEADA.**



Ver `docs/PADRONIZACAO_MULTIPLATAFORMA.md` e `.cursor/rules/padronizacao-multiplataforma.mdc`.



## Onde executar



**Painel Master → Saúde do Sistema** (`SystemFirebaseHealthPage`)



| Aba | Conteúdo |

|-----|----------|

| Central | Modo produção (liberado/bloqueado) |

| Diagnóstico | Firebase, Auth, Firestore, Storage, Sync, Chat, Push, Site, pendências, backup, health 5 min |

| Modo QA | Matriz multiplataforma + 28 verificações |

| Métricas | Tempos da sessão vs metas |

| Firebase / Uploads / Filas | Detalhe operacional |



## Modo QA (28 testes × 3 plataformas)



Implementação: `lib/core/qa/qa_assurance_runner.dart`  

Matriz: `lib/core/qa/multiplatform_qa_matrix.dart`



Executar **Modo QA** em cada plataforma antes de release.



## Relatório tri-plataforma (template)



| # | Teste | Android | iOS | Web | Acção |

|---|-------|---------|-----|-----|-------|

| 1 | Login Google | | | | |

| … | … | | | | |

| 28 | Painel Master | | | | |



| Módulo | Android | iOS | Web |

|--------|---------|-----|-----|

| Login | | | |

| Chat | | | |

| Avisos | | | |

| Eventos | | | |

| Membros | | | |

| Patrimônio | | | |

| Financeiro | | | |

| Uploads | | | |

| Offline | | | |

| Sync | | | |

| Retornar onde parou | | | |



## Gate CI local



```powershell

.\scripts\verify_production_checklist.ps1

cd flutter_app; flutter test test/qa_assurance_runner_test.dart

```



## Regra de ouro



Se uma alteração reduzir estabilidade, **não implementar**. Estabilidade > funcionalidades novas.



## Escopo fechado



Base · Experiência · Módulos · Performance · Produção · **Plataformas alinhadas** — ver `PADRONIZACAO_MULTIPLATAFORMA.md`.


