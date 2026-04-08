# Como subir a versão atualizada e as regras do banco no domínio

Siga estes passos para deixar o **domínio** com a versão atual e o **banco seguro** (nenhuma igreja vê dados da outra; só o master tem acesso a tudo).

---

## 1. Publicar as regras do Firestore (banco seguro)

As regras em **`firestore.rules`** já estão atualizadas no projeto:

- **Isolamento:** cada igreja só acessa os próprios dados (`sameChurch(id)`).
- **Master:** usuário com `role == 'MASTER'` no documento `users/{uid}` tem acesso a **tudo** (todas as igrejas, members, subscriptions, etc.).
- **Master de referência:** CPF 94536368191, Raihom Severino Barbosa, raihom@gmail.com (também gestor da igreja Brasil para Cristo).

### Opção A — Firebase Console (recomendado)

1. Acesse [Firebase Console](https://console.firebase.google.com) e selecione o projeto **gestaoyahweh-21e23** (Gestão YAHWEH).
2. No menu: **Firestore Database** → aba **Regras**.
3. Abra o arquivo **`firestore.rules`** deste repositório (pasta raiz do projeto).
4. Copie **todo** o conteúdo de `firestore.rules` e cole no editor de regras do Firebase (substituindo o que estiver lá).
5. Clique em **Publicar**.

### Opção B — Firebase CLI

```bash
# Na raiz do projeto (gestao_yahweh_premium_final)
firebase use gestaoyahweh-21e23
firebase deploy --only firestore:rules
```

Assim que publicar, o banco passa a usar as novas regras (igrejas isoladas, master com acesso total).

---

## 2. Garantir que você é o Master no banco

O **master** é quem tem no Firestore o documento **`users/{seu_uid}`** com o campo **`role: 'MASTER'`** (e, se quiser, `igrejaId` da Brasil para Cristo para atuar como gestor dela).

- **UID:** é o ID do usuário no Firebase Auth (não é o CPF). Você descobre no Firebase Console → Authentication → Usuários → raihom@gmail.com → copiar o UID.
- No Firestore, em **`users/{UID_do_raihom}`** deve existir algo como:
  - `role: 'MASTER'`
  - `igrejaId: '<id_da_igreja_brasil_para_cristo>'` (para você ser gestor da Brasil para Cristo)
  - demais campos que o app já usa (email, nome, etc.)

Se esse documento não existir ou não tiver `role: 'MASTER'`, crie/atualize (pode ser pelo próprio app, por um script ou pelo Console do Firestore).

---

## 3. Subir a versão atualizada para o domínio (web)

A versão do app está em **`flutter_app/lib/app_version.dart`** e **`flutter_app/pubspec.yaml`** (ex.: 10.0.19). Para o usuário acessar essa versão no domínio:

### 3.1 Build web

```bash
cd flutter_app
flutter pub get
flutter build web
```

Isso gera os arquivos em **`flutter_app/build/web/`**.

### 3.2 Publicar no Firebase Hosting

```bash
# Na raiz do projeto
firebase use gestaoyahweh-21e23
firebase deploy --only hosting
```

Se o seu projeto usar outro domínio (ex.: próprio no GCP ou outra CDN), faça o upload do conteúdo de **`flutter_app/build/web/`** para o servidor que atende esse domínio.

---

## 4. Resumo do que as regras garantem

| Quem | O que pode |
|------|------------|
| **Igreja A (gestor)** | Só lê/escreve dados da **própria igreja** (members, notícias, etc.). Não vê Igreja B. |
| **Master (raihom@gmail.com com role MASTER)** | Lê e escreve **tudo**: todas as igrejas, tenants, members, users, subscriptions, config, etc. |
| **Visitante (não logado)** | Só o que as regras permitem como público (ex.: leitura de tenants para busca, igrejas, notícias). |

Assim o sistema fica **estável e seguro** para o usuário: cada igreja só vê os próprios dados, e você, como master, mantém acesso total.

---

*Arquivo de referência. Atualize a versão em `app_version.dart` e `pubspec.yaml` antes de cada novo deploy.*
