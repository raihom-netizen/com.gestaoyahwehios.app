import 'package:flutter/material.dart';

/// Data de referência exibida nas páginas legais (atualizar quando o texto mudar).
const String kLegalDocumentsLastUpdated = 'Abril de 2026';

class TermosDeUsoPage extends StatelessWidget {
  const TermosDeUsoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalScaffold(
      title: 'Termos de Uso',
      lastUpdated: kLegalDocumentsLastUpdated,
      sections: [
        _LegalSection(
          title: '1. Aceitação',
          body:
              'Ao utilizar o Gestão YAHWEH, a igreja (ou organização religiosa cadastrada) e seus usuários autorizados concordam com estes termos, com a Política de Privacidade disponível em https://gestaoyahweh.com.br/politica-de-privacidade e com a legislação brasileira aplicável.',
        ),
        _LegalSection(
          title: '2. Natureza do serviço',
          body:
              'O Gestão YAHWEH é uma plataforma de gestão eclesiástica (membros, ministérios, comunicação, documentos, financeiro e patrimônio, conforme módulos contratados). A disponibilidade de funcionalidades depende do plano, da configuração da igreja e do perfil de cada usuário.',
        ),
        _LegalSection(
          title: '3. Responsabilidade da igreja',
          body:
              'A igreja é responsável pelos dados inseridos e pela legalidade do tratamento perante seus membros, visitantes e colaboradores: veracidade das informações, bases legais (incluindo consentimentos quando necessários), uso de imagens, dados de menores e cumprimento da LGPD no âmbito da sua atuação como controladora.',
        ),
        _LegalSection(
          title: '4. Contas, acesso e conduta',
          body:
              'Credenciais são pessoais e intransferíveis. É proibido usar a plataforma para fins ilícitos, fraude, assédio, violação de direitos de terceiros, disseminação de malware ou qualquer atividade que comprometa a segurança ou o bom funcionamento do sistema.',
        ),
        _LegalSection(
          title: '5. Assinatura, pagamentos e planos',
          body:
              'Planos, limites e condições comerciais são informados no momento da contratação ou renovação. Pagamentos de assinatura podem ser processados por parceiros (ex.: gateways de pagamento); a fatura e os dados de cartão ou PIX seguem as regras do provedor de pagamento e desta política.',
        ),
        _LegalSection(
          title: '6. Propriedade intelectual',
          body:
              'Marca, identidade visual, software e documentação do Gestão YAHWEH são protegidos por lei. É vedada cópia, engenharia reversa, sublicenciamento ou uso fora do escopo contratado, salvo autorização expressa.',
        ),
        _LegalSection(
          title: '7. Disponibilidade, suporte e melhorias',
          body:
              'Empregamos esforços razoáveis para manter a plataforma disponível. Podem ocorrer manutenções programadas ou corretivas. Funcionalidades podem evoluir; avisos relevantes serão dados por meios adequados (ex.: aplicativo, e-mail ou painel).',
        ),
        _LegalSection(
          title: '8. Limitação de responsabilidade',
          body:
              'Na extensão permitida pela lei, não nos responsabilizamos por danos indiretos, lucros cessantes ou perdas decorrentes de uso indevido pela igreja ou terceiros, indisponibilidade de internet, casos fortuitos ou força maior. A igreja deve manter cópias e controles internos compatíveis com a criticidade dos seus dados.',
        ),
        _LegalSection(
          title: '9. Encerramento',
          body:
              'O acesso pode ser suspenso ou encerrado em caso de violação destes termos, inadimplência grave ou determinação legal. Após encerramento, a retenção e exclusão de dados observarão a Política de Privacidade e obrigações legais.',
        ),
        _LegalSection(
          title: '10. Contato',
          body:
              'Dúvidas sobre estes termos: utilize os canais oficiais divulgados no site https://gestaoyahweh.com.br ou no aplicativo.',
        ),
      ],
    );
  }
}

class PoliticaPrivacidadePage extends StatelessWidget {
  const PoliticaPrivacidadePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalScaffold(
      title: 'Política de Privacidade',
      lastUpdated: kLegalDocumentsLastUpdated,
      sections: [
        _LegalSection(
          title: '1. Introdução',
          body:
              'Esta Política de Privacidade descreve como o ecossistema Gestão YAHWEH trata dados pessoais no contexto de um sistema completo de gestão para igrejas e organizações religiosas: cadastro e pastoral de membros e visitantes, departamentos e escalas, comunicação (avisos, notificações), documentos (certificados, carteirinhas), finanças e patrimônio, conforme os módulos utilizados por cada igreja.\n\n'
              'O uso do aplicativo, do painel web e dos formulários públicos vinculados à sua igreja implica ciência desta política. Recomendamos que pastores, secretarias e tesourarias a disponibilizem também aos membros quando aplicável.',
        ),
        _LegalSection(
          title: '2. Quem é responsável pelos dados (LGPD)',
          body:
              'Em regra, cada igreja ou entidade cadastrada atua como controladora dos dados pessoais que coleta de seus membros, visitantes, voluntários e usuários do painel — ou seja, define as finalidades e os meios de tratamento no seu contexto pastoral e administrativo.\n\n'
              'A operação da plataforma (hospedagem, autenticação, backups técnicos, suporte e melhorias do produto) é realizada em nome das igrejas, em infraestrutura de nuvem, observando o papel de operador ou as cláusulas contratuais aplicáveis entre a igreja e o Gestão YAHWEH.\n\n'
              'Quando você utiliza funcionalidades globais do serviço (ex.: conta de gestor master, suporte ou cobrança de assinatura), o responsável pelo tratamento desses dados de contrato e faturação é quem presta o serviço Gestão YAHWEH, conforme descrito nas seções abaixo.',
        ),
        _LegalSection(
          title: '3. Quais dados podemos tratar',
          body:
              'Dependendo do que a igreja configurar e dos módulos ativos, podem ser tratados, entre outros:\n\n'
              '• Identificação e cadastro: nome, CPF ou documento, data de nascimento, estado civil, filiação, naturalidade, gênero, funções ministeriais, departamentos, cargos customizados, status de membro (ativo, pendente, visitante etc.).\n'
              '• Contato: e-mail, telefone, endereço, CEP, cidade, estado, coordenadas geográficas quando informadas para localização em mapas.\n'
              '• Imagem e documentos: fotografia de perfil, foto de capa, assinatura e imagem para carteirinha ou documentos, certificados emitidos pela igreja, anexos enviados pela secretaria.\n'
              '• Dados religiosos e pastorais: batismo, consagração, participação em ministérios — podem ser considerados sensíveis na LGPD quando revelam convicção religiosa; o tratamento deve ocorrer com base legal adequada e, quando exigido, consentimento específico.\n'
              '• Financeiro e patrimônio: registros de dízimos, ofertas, despesas, categorias, bens e inventário, conforme lançados por usuários autorizados.\n'
              '• Presença e escalas: registros de cultos, eventos, escalas de voluntários.\n'
              '• Comunicação: pedidos de oração, notícias, notificações push, tokens de dispositivo para envio de mensagens.\n'
              '• Conta e segurança: identificador de usuário, logs de acesso, dados de autenticação (senha tratada com mecanismos seguros; biometria no aparelho quando você ativar login biométrico local — em geral processada só pelo sistema do celular).\n'
              '• Dados técnicos: tipo de dispositivo, sistema operacional, idioma, endereço IP, identificadores de sessão e diagnósticos de falhas (ex.: relatórios de erro para estabilidade do app).\n\n'
              'A igreja deve inserir apenas dados necessários e lícitos; o membro ou visitante deve informar dados verdadeiros quando preencher cadastro próprio.',
        ),
        _LegalSection(
          title: '4. Finalidades e bases legais',
          body:
              'Tratamos dados para: prestar o serviço contratado pela igreja; permitir cadastro, aprovação e gestão de membros; emitir documentos oficiais da igreja; operar financeiro e patrimônio; enviar comunicações autorizadas; cumprir obrigações legais e regulatórias; exercer direitos em processos; melhorar segurança, desempenho e experiência do usuário; e, quando aplicável, com base em consentimento (ex.: comunicações opcionais, certas imagens ou dados sensíveis).\n\n'
              'As bases legais incluem, conforme o caso: execução de contrato ou procedimentos preliminares; legítimo interesse (com avaliação de balanceamento); cumprimento de obrigação legal ou regulatória; proteção da vida ou da incolumidade física; estudo por órgão de pesquisa; e consentimento do titular, quando exigido.',
        ),
        _LegalSection(
          title: '5. Menores de idade',
          body:
              'Dados de crianças e adolescentes devem ser tratados com base no consentimento de pelo menos um dos pais ou responsável legal, ou em outra hipótese prevista na LGPD. A igreja é responsável por obter e documentar essas autorizações no seu contexto. O sistema pode ser usado para cadastro de menores apenas quando a igreja tiver respaldo legal e pastoral adequados.',
        ),
        _LegalSection(
          title: '6. Como armazenamos e protegemos',
          body:
              'Os dados são armazenados em ambiente de nuvem (Google Firebase / Google Cloud), com controles de autenticação, regras de segurança por perfil, comunicação criptografada em trânsito (HTTPS) e práticas de segurança da informação compatíveis com o risco. Nenhum sistema é 100% invulnerável; em caso de incidente relevante, adotaremos medidas de contenção e notificação conforme a lei.',
        ),
        _LegalSection(
          title: '7. Compartilhamento e subprocessadores',
          body:
              'Não vendemos dados pessoais de membros. O compartilhamento ocorre quando necessário à prestação do serviço ou à lei, incluindo:\n\n'
              '• Provedores de infraestrutura e autenticação (Google Firebase, incluindo Firestore, Storage, Authentication, Cloud Functions, FCM para notificações).\n'
              '• Meios de pagamento e assinatura (ex.: processadores de PIX, cartão ou boletos, quando a igreja contrata planos pagos).\n'
              '• Ferramentas de diagnóstico de estabilidade (ex.: relatórios de falha do aplicativo), sem uso publicitário.\n\n'
              'Usuários da mesma igreja enxergam dados conforme permissões definidas pela liderança (pastor, secretaria, tesouraria, etc.). Dados não são expostos publicamente salvo onde a igreja deliberadamente publicar (ex.: site institucional integrado) dentro das regras do produto.',
        ),
        _LegalSection(
          title: '8. Transferência internacional',
          body:
              'Serviços de nuvem utilizados podem processar dados em servidores fora do Brasil. Nesses casos, adotamos instrumentos contratuais e medidas previstas na LGPD para garantir nível de proteção compatível.',
        ),
        _LegalSection(
          title: '9. Cookies, armazenamento local e PWA',
          body:
              'Na versão web, podem ser usados cookies ou armazenamento local para manter sessão, preferências e funcionamento offline limitado (PWA). Você pode limpar dados do navegador; isso pode exigir novo login.',
        ),
        _LegalSection(
          title: '10. Prazo de retenção',
          body:
              'Mantemos os dados pelo tempo necessário para cumprir as finalidades descritas, o contrato com a igreja e obrigações legais (ex.: fiscal ou trabalhista, quando houver). Após exclusão solicitada ou encerramento contratual, poderá haver retenção mínima em backups por período técnico seguro ou quando a lei exigir arquivo.',
        ),
        _LegalSection(
          title: '11. Seus direitos (titular de dados)',
          body:
              'Nos termos da LGPD, você pode solicitar: confirmação de tratamento; acesso; correção; anonimização, bloqueio ou eliminação de dados desnecessários; portabilidade; informação sobre compartilhamentos; revogação de consentimento (quando a base for consentimento); oposição a tratamento fundado em legítimo interesse; e revisão de decisões automatizadas.\n\n'
              'Para dados tratados pela sua igreja, o primeiro contato deve ser a liderança ou secretaria local. Para dados de assinatura, conta master ou operação da plataforma, utilize o canal oficial de privacidade indicado abaixo.',
        ),
        _LegalSection(
          title: '12. Encarregado de dados e contato',
          body:
              'Para questões específicas sobre esta política, privacidade e exercício de direitos em relação ao operador da plataforma Gestão YAHWEH, utilize o e-mail privacidade@gestaoyahweh.com.br ou os canais oficiais indicados em https://gestaoyahweh.com.br.\n\n'
              'Endereço público desta política: https://gestaoyahweh.com.br/politica-de-privacidade',
        ),
        _LegalSection(
          title: '13. Alterações',
          body:
              'Podemos atualizar esta política para refletir mudanças legais ou no produto. A data de “Última atualização” no topo da página será revisada. Uso continuado após aviso razoável pode constituir ciência da nova versão, sem prejuízo de direitos do titular.',
        ),
        _LegalSection(
          title: '14. Lei e foro',
          body:
              'Esta política é regida pelas leis da República Federativa do Brasil, em especial a Lei nº 13.709/2018 (LGPD). Fica eleito o foro da comarca de domicílio do consumidor ou, quando aplicável, o foro da capital do estado indicado em contrato, para dirimir controvérsias.',
        ),
      ],
    );
  }
}

class _LegalScaffold extends StatelessWidget {
  final String title;
  final String lastUpdated;
  final List<_LegalSection> sections;

  const _LegalScaffold({
    required this.title,
    required this.lastUpdated,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Última atualização: $lastUpdated',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                for (final section in sections) ...[
                  Text(
                    section.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    section.body,
                    style: const TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalSection {
  final String title;
  final String body;

  const _LegalSection({
    required this.title,
    required this.body,
  });
}
