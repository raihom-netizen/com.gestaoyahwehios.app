# Instruções para criar uma nova igreja e gestor automaticamente

## Como usar o script de automação

1. Abra o terminal na raiz do projeto (C:\gestao_yahweh_premium_final).
2. Execute o comando abaixo, substituindo os parâmetros pelos dados da nova igreja e gestor:

```
node functions/setup_igreja_automatica.js <igrejaId> <igrejaNome> <gestorEmail> <gestorCpf> <gestorNome> <userId>
```

### Parâmetros obrigatórios:
- `<igrejaId>`: ID único da igreja (ex: brasilparacristo_sistema)
- `<igrejaNome>`: Nome completo da igreja (ex: "Brasil para Cristo")
- `<gestorEmail>`: E-mail do gestor principal
- `<gestorCpf>`: CPF do gestor (apenas números)
- `<gestorNome>`: Nome completo do gestor
- `<userId>`: UID do usuário gestor (gerado pelo Firebase Auth)

### Exemplo real:
```
node functions/setup_igreja_automatica.js brasilparacristo_sistema "Brasil para Cristo" raihom@gmail.com 94536368191 "RAIHOM SEVERINO BARBOSA" WIQ6QyLFn5UeEKZKXzF08kE4rCC2
```

---

## O que o script faz automaticamente:
- Cria/atualiza o documento da igreja na coleção `igrejas`.
- Cria/atualiza o usuário gestor na coleção `users`.
- Cria todas as coleções/tabelas essenciais para funcionamento da igreja, com um documento inicial.

---

## Observações
- O campo `<userId>` deve ser o UID do usuário no Firebase Authentication. Você pode obter esse UID ao criar o usuário pelo painel do Firebase Auth.
- O script pode ser executado quantas vezes quiser, sem duplicar dados.
- Para novas igrejas, basta rodar novamente com os dados desejados.

Se precisar de mais automações, integração com painel web ou dúvidas, consulte a equipe técnica!
