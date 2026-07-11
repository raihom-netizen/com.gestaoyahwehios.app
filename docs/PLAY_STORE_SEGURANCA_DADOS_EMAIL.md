# Google Play — Segurança dos dados (rejeição: E-mail não declarado)

**App:** Gestão Yahweh - Igrejas  
**Pacote:** `com.gestaoyahweh.app`  
**Versão rejeitada (exemplo):** `versionCode` **2078** — e-mail não declarado  
**Correção:** atualizar ficha **Segurança dos dados** na Play Console **antes** de enviar o próximo AAB (não basta só subir APK/AAB novo).

---

## Por que foi rejeitado?

O Google detectou que o app **envia e-mail para servidores** (Firebase/Google Cloud), mas o formulário **Segurança dos dados** não declarava **Endereço de e-mail**.

O app **precisa** de e-mail — não remova do código. A correção é **atualizar a declaração** na Play Console.

---

## Onde o app coleta/transmite e-mail

| Origem | Uso |
|--------|-----|
| **Firebase Authentication** | Login com e-mail/senha, Google Sign-In, Apple |
| **Firestore** `igrejas/{id}/membros` | Cadastro de membros (campo EMAIL/email) |
| **Firestore** `igrejas/{id}` | Cadastro da igreja / gestor |
| **Firestore** `users/{uid}` | Perfil global da conta |
| **Mercado Pago** (planos) | E-mail do pagador quando aplicável |

SDKs envolvidos: **Firebase Auth**, **Cloud Firestore**, **Google Sign-In**, **Sign in with Apple**, **Firebase Analytics/Crashlytics** (podem associar identificador à conta).

Política no app: `config/legal_documents` — secção «Informações que coletamos» já menciona e-mail.

---

## Passo a passo na Play Console (obrigatório ANTES do novo AAB)

1. [Play Console](https://play.google.com/console) → app **Gestão Yahweh - Igrejas**
2. **Política do app** → **Segurança dos dados**
3. **Gerenciar** → revisar todas as secções
4. Em **Tipos de dados** → **Adicionar tipo de dados** → **Informações pessoais** → **Endereço de e-mail**

### Preencher «Endereço de e-mail» assim:

| Pergunta | Resposta recomendada |
|----------|----------------------|
| Os dados são coletados? | **Sim** |
| Os dados são compartilhados? | **Sim** (Firebase/Google Cloud; provedores de login e pagamento) |
| Os dados são processados de forma efêmera? | **Não** |
| A coleta é obrigatória ou opcional? | **O usuário pode escolher** (login Google/Apple/e-mail; cadastro membro pode exigir e-mail conforme igreja) — ou **Obrigatório** se só login por e-mail for exigido |
| Por que os dados são coletados? | **Funcionalidade do app**, **Gerenciamento de contas** |
| Por que os dados são compartilhados? | **Funcionalidade do app**, **Gerenciamento de contas** |
| Os dados são criptografados em trânsito? | **Sim** (HTTPS/TLS — Firebase) |

5. Verificar também (se ainda não declarados):

   - **Nome** (cadastro membro/igreja)
   - **Fotos** (perfil, avisos, chat, patrimônio)
   - **Outras informações** (CPF, telefone — se já marcados no formulário)
   - **Identificadores do dispositivo** (FCM token — notificações)
   - **Registros de falhas** (Firebase Crashlytics)

6. **Salvar** → **Enviar para análise** (rascunho da ficha de dados)

7. **Testar e lançar** → **Produção** → criar nova versão → upload do **AAB** com `versionCode` **maior que 2078** (ex.: 2079 após `build_android_play_store_aab.ps1`)

---

## Gerar novo AAB (repositório)

Na raiz do projeto (PowerShell):

```powershell
.\scripts\build_android_play_store_aab.ps1
```

Saída: `flutter_app\build\app\outputs\bundle\release\app-release.aab`  
Cópia: `D:\Temporarios\` (nome com versão e build).

---

## Automação no repositório (não substitui a Play Console)

Antes de cada AAB:

```powershell
.\scripts\play_store_data_safety_preflight.ps1 -Strict
```

O script `build_android_play_store_aab.ps1` já imprime este lembrete após o build.

---

## Tabela completa — tipos de dados a declarar (evitar nova rejeição)

Marque na Play Console **todos** que o app usa (scanner do Google compara tráfego real × ficha):

| Tipo (Play Console) | Coletado | Compartilhado | Origem no app |
|---------------------|----------|---------------|---------------|
| **Endereço de e-mail** | Sim | Sim | Firebase Auth, login Google/Apple, cadastro membro/igreja, MP |
| **Nome** | Sim | Sim | Cadastro membro, igreja, chat |
| **Fotos** | Sim | Sim | Perfil, avisos, eventos, chat, patrimônio |
| **Telefone** | Sim | Opcional | Cadastro membro/igreja |
| **Outras informações** (CPF) | Sim | Não* | Membros, quando informado |
| **Identificadores do dispositivo** | Sim | Sim | FCM push, Analytics |
| **Registros de falhas** | Sim | Sim | Firebase Crashlytics |
| **Arquivos e documentos** | Sim | Sim | Chat, comprovantes financeiros |

\*Compartilhado = enviado a processadores (Google Cloud, Mercado Pago), não “vendido a terceiros”.

**ID de publicidade:** manifest declara `AD_ID` — na ficha, confirme uso conforme Firebase Analytics.

---

## Checklist antes de reenviar

- [ ] Segurança dos dados: **E-mail** declarado (coletado + compartilhado)
- [ ] Política de privacidade URL na ficha do app (site ou `/privacidade`)
- [ ] `versionCode` **> 2078** (2079 ou superior no próximo envio)
- [ ] AAB assinado com a mesma chave de upload (SHA1 `96:91:41:90:...`)
- [ ] Enviar alterações da ficha + novo pacote para análise

---

## Se ainda rejeitar

- Abra **Mais detalhes** na notificação e confira se pedem outro tipo (ex.: **Nome**, **ID do usuário**, **Fotos**).
- Use [SDK Index](https://developer.android.com/distribute/sdk-index) para Firebase/Google e alinhe cada SDK ao formulário.
- Não marque «Nenhum dado coletado» — o scanner do Google já provou transmissão de e-mail.
