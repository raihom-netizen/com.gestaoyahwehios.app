# Configuração da checagem automática de versão (web e celular)

O app verifica **automaticamente** ao abrir (sem depender do usuário) se há uma versão mais nova obrigatória. A checagem usa o Firestore e funciona em **web** e **mobile**.

## Onde é feita a checagem

- **VersionService** (`lib/services/version_service.dart`): lê o documento `config/appVersion` no Firestore, compara com a versão do app (`app_version.dart`) e devolve se está desatualizado e se é obrigatório atualizar.
- **UpdateChecker** (`lib/ui/widgets/update_checker.dart`): widget que envolve o app no `main.dart` e roda a checagem no primeiro frame; se houver atualização, exibe o diálogo.
- **Login**: após o login também é chamado `_ensureLatestVersion()` para bloquear uso se a versão for antiga e obrigatória.

## Documento no Firestore: `config/appVersion`

Crie (ou edite) o documento **config/appVersion** com os campos:

| Campo             | Tipo    | Obrigatório | Descrição |
|-------------------|---------|-------------|-----------|
| `minVersion`      | string  | Sim         | Versão mínima aceita (ex: `"5.0"`, `"5.1.0"`). O app compara com a versão atual. |
| `forceUpdate`     | boolean | Não         | Se `true`, o usuário não pode continuar sem atualizar (diálogo não fecha). |
| `message`         | string  | Não         | Mensagem exibida no diálogo. Se vazio, usa mensagem padrão. |
| `storeUrlAndroid` | string  | Não         | URL da Play Store (mobile Android). |
| `storeUrlIos`     | string  | Não         | URL da App Store (mobile iOS). |
| `webRefresh`      | boolean | Não         | Se `true`, na web o botão "Atualizar" recarrega a página para pegar a nova versão. |

### Exemplo (Firestore Console)

```json
{
  "minVersion": "5.0",
  "forceUpdate": false,
  "message": "Nova versão disponível com melhorias de segurança e desempenho.",
  "storeUrlAndroid": "https://play.google.com/store/apps/details?id=seu.pacote",
  "storeUrlIos": "https://apps.apple.com/app/id123456789",
  "webRefresh": true
}
```

- Para **forçar** todos a atualizarem: use `forceUpdate: true` e defina `minVersion` para a nova versão (ex: `"5.1"`).
- **Web**: não usa loja; com `webRefresh: true` o botão "Atualizar" recarrega a página (o usuário recebe a nova versão do hosting).
- **Mobile**: preencha `storeUrlAndroid` e/ou `storeUrlIos` para o botão abrir a loja.

## Regra de segurança

Em `firestore.rules` já existe:

```
match /config/appVersion {
  allow read: if true;
  allow write: if isMaster();
}
```

Assim qualquer pessoa (mesmo sem login) pode **ler** a configuração de versão ao abrir o app; só Master pode **escrever**.

## Resumo

- Checagem **automática** ao abrir o app (web e celular).
- Não depende do usuário ir em “verificar atualização”; o app busca sozinho no Firestore.
- Você controla a versão mínima e se é obrigatório atualizar editando o documento `config/appVersion`.
