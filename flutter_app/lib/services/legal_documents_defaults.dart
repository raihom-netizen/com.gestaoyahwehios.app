import 'package:gestao_yahweh/services/legal_document_models.dart';

/// Contato e metadados padrão (fallback offline / 1.ª publicação).
const String kLegalDocumentsLastUpdatedDefault = 'Junho de 2026';
const String kLegalSupportEmail = 'raihom@gmail.com';
const String kLegalSupportWhatsAppDisplay = '(62) 9 9170-5247';
const String kLegalSupportWhatsAppWaMe = '5562991705247';
const String kDeveloperPublicName = 'Raihom Barbosa';

/// Texto embutido quando `config/legal_documents` ainda não existe no Firestore.
abstract final class LegalDocumentsDefaults {
  LegalDocumentsDefaults._();

  static LegalDocumentsBundle get bundle => LegalDocumentsBundle(
        lastUpdatedLabel: kLegalDocumentsLastUpdatedDefault,
        supportEmail: kLegalSupportEmail,
        supportWhatsAppDisplay: kLegalSupportWhatsAppDisplay,
        terms: _terms,
        privacy: _privacy,
        revision: 0,
      );

  static const LegalDocumentContent _terms = LegalDocumentContent(
    title: 'Termos de Uso',
    intro:
        'Leia atentamente estes Termos de Uso antes de utilizar o Gestão YAHWEH. '
        'Documento elaborado em observância à legislação brasileira aplicável, '
        'incluindo a Lei Geral de Proteção de Dados (Lei nº 13.709/2018 — LGPD), '
        'o Marco Civil da Internet (Lei nº 12.965/2014) e demais normas pertinentes.',
    sections: [
      LegalSectionEntry(
        title: '1. Aceitação',
        body:
            'Ao utilizar o Gestão YAHWEH (aplicativo, painel web e funcionalidades disponíveis), '
            'você concorda com estes Termos de Uso e com a Política de Privacidade. '
            'Se não concordar, não utilize o serviço.',
      ),
      LegalSectionEntry(
        title: '2. Serviço',
        body:
            'O Gestão YAHWEH oferece ferramentas para gestão eclesiástica e administrativa, '
            'conforme o plano contratado pela igreja, incluindo: cadastro da igreja; '
            'membros e visitantes; departamentos e cargos; avisos e mural; eventos e agenda; '
            'chat interno; pedidos de oração; escalas; financeiro e fornecedores; patrimônio; '
            'certificados e carteirinha digital; cartas e transferências; doações; '
            'configurações e painel web (PWA). '
            'O acesso pode ser feito por celular (Android/iOS), tablet ou computador. '
            'Funcionalidades e limites seguem o plano contratado (incluindo período de teste, '
            'quando oferecido).',
      ),
      LegalSectionEntry(
        title: '3. Conta e licença',
        body:
            'Você é responsável por manter a confidencialidade do login e pela atividade realizada '
            'na sua conta. O acesso depende de licença ativa (período de teste, assinatura ou '
            'condições comerciais vigentes). Licença vencida ou suspensa pode restringir o uso '
            'conforme a política do serviço e o contrato com a igreja.',
      ),
      LegalSectionEntry(
        title: '4. Uso adequado',
        body:
            'Você se compromete a usar o app de forma lícita, sem prejudicar terceiros ou o serviço. '
            'É proibido o uso para atividades ilegais, envio de conteúdo ofensivo, violação de '
            'direitos de terceiros ou tentativas de acesso não autorizado.',
      ),
      LegalSectionEntry(
        title: '5. Propriedade intelectual',
        body:
            'Todo o conteúdo e a tecnologia do Gestão YAHWEH são de propriedade do desenvolvedor '
            'ou licenciados para uso no produto. Você tem direito de usar o serviço conforme '
            'previsto nestes termos, sem copiar ou distribuir o software de forma indevida.',
      ),
      LegalSectionEntry(
        title: '6. Pagamentos',
        body:
            'Os planos pagos podem ser processados via Mercado Pago (PIX ou cartão, conforme '
            'disponibilizado). As condições de reembolso seguem a política do Mercado Pago e '
            'podem ser solicitadas diretamente à plataforma, quando aplicável.',
      ),
      LegalSectionEntry(
        title: '7. Limitação de responsabilidade',
        body:
            'O app é fornecido “como está”, no limite da lei aplicável. Não nos responsabilizamos '
            'por decisões pastorais, financeiras ou administrativas tomadas com base nos dados '
            'ou relatórios gerados — recomenda-se validação por responsáveis competentes quando necessário.',
      ),
      LegalSectionEntry(
        title: '8. Alterações',
        body:
            'Podemos alterar estes termos. Alterações significativas serão comunicadas por meios '
            'razoáveis (aplicativo, painel ou e-mail). O uso continuado após as alterações pode '
            'indicar aceitação, sem prejuízo dos seus direitos legais.',
      ),
      LegalSectionEntry(
        title: '9. Contato',
        body:
            'Dúvidas sobre estes Termos de Uso: $kLegalSupportEmail ou WhatsApp $kLegalSupportWhatsAppDisplay.',
      ),
    ],
  );

  static const LegalDocumentContent _privacy = LegalDocumentContent(
    title: 'Política de Privacidade',
    intro:
        'O Gestão YAHWEH respeita a sua privacidade. Este documento descreve como tratamos '
        'dados pessoais no aplicativo (Android e iOS) e no painel web, em conformidade com a '
        'Lei Geral de Proteção de Dados — LGPD (Lei nº 13.709/2018), o Marco Civil da Internet '
        '(Lei nº 12.965/2014) e orientações da Autoridade Nacional de Proteção de Dados (ANPD), '
        'quando aplicáveis.',
    sections: [
      LegalSectionEntry(
        title: '1. Informações que coletamos',
        body:
            'Conforme os módulos utilizados pela igreja, podemos tratar: nome, **endereço de e-mail** '
            '(conta de login, cadastro pastoral e comunicações), telefone, '
            'CPF (quando informado), endereço, foto de perfil, dados de cadastro pastoral e '
            'administrativo, departamentos, cargos, escalas, agenda, avisos, eventos, mensagens '
            'de chat, pedidos de oração, lançamentos financeiros, patrimônio, fornecedores, '
            'documentos emitidos (certificados, carteirinha, cartas), preferências e configurações '
            'da conta.\n\n'
            'O login pode ocorrer por CPF/e-mail e senha, Google ou Apple (Sign in with Apple), '
            'conforme disponível na versão e plataforma. O **e-mail da conta** é transmitido de '
            'forma segura (HTTPS/TLS) para servidores Google Cloud (Firebase Authentication e '
            'Firestore), conforme exigido para autenticação e gestão da igreja — e deve constar '
            'na ficha «Segurança dos dados» da Google Play Store.\n\n'
            'Também tratamos dados técnicos necessários ao funcionamento: tokens de notificação '
            '(push), logs de segurança, identificadores de sessão, endereço IP, tipo de dispositivo '
            'e dados de uso do app para diagnóstico e melhoria do serviço.\n\n'
            'Fotos, documentos e arquivos enviados por você (logos, comprovantes, mídia do chat, '
            'etc.) são armazenados de forma segura na infraestrutura contratada, vinculados à '
            'igreja à qual você pertence.',
      ),
      LegalSectionEntry(
        title: '2. Finalidade e bases legais (LGPD)',
        body:
            'Utilizamos os dados para: prestar e operar o serviço; autenticar usuários; '
            'permitir a gestão autorizada pela liderança da igreja; enviar notificações '
            'relacionadas ao serviço; processar pagamentos de planos; reforçar segurança; '
            'cumprir obrigações legais; e melhorar a experiência no painel.\n\n'
            'As bases legais incluem, conforme o caso: execução de contrato ou procedimentos '
            'preliminares (art. 7º, V); legítimo interesse do controlador ou do titular, '
            'respeitados direitos fundamentais (art. 7º, IX); cumprimento de obrigação legal '
            '(art. 7º, II); e consentimento, quando exigido (art. 7º, I), por exemplo para '
            'recursos opcionais.\n\n'
            'O produto é voltado à gestão da igreja e não exibe anúncios de terceiros.',
      ),
      LegalSectionEntry(
        title: '3. Armazenamento e segurança',
        body:
            'Os dados são armazenados em infraestrutura segura na nuvem (Firebase / Google Cloud), '
            'organizados por igreja (identificador único no Firestore e no Storage). '
            'Aplicamos medidas técnicas e administrativas compatíveis com o risco — controle de '
            'acesso, criptografia em trânsito (HTTPS/TLS), autenticação e regras de segurança '
            'no banco de dados — em conformidade com a LGPD.\n\n'
            'Cada igreja é responsável pelos dados que cadastra sobre seus membros e colaboradores, '
            'atuando como controladora em relação a esses cadastros; o Gestão YAHWEH atua como '
            'operador de tratamento na prestação da plataforma, salvo quando indicado de forma diversa.',
      ),
      LegalSectionEntry(
        title: '4. Compartilhamento e transferência internacional',
        body:
            'Não vendemos seus dados pessoais.\n\n'
            'Podemos compartilhar informações apenas: (a) com provedores essenciais ao serviço '
            '(Google/Firebase para hospedagem; Google/Apple para login; Mercado Pago para '
            'pagamentos de planos), sob contratos e políticas próprias; (b) entre usuários da '
            'mesma igreja, conforme permissões definidas pela liderança; (c) quando exigido '
            'por lei, ordem judicial ou autoridade competente.\n\n'
            'Os provedores de nuvem podem processar dados em servidores fora do Brasil (incluindo '
            'Estados Unidos), com salvaguardas contratuais e técnicas previstas na LGPD para '
            'transferência internacional (art. 33 e seguintes).',
      ),
      LegalSectionEntry(
        title: '5. Retenção e eliminação',
        body:
            'Mantemos os dados pelo tempo necessário à prestação do serviço, cumprimento de '
            'obrigações legais, resolução de disputas e exercício de direitos. '
            'Após encerramento da conta ou solicitação válida do titular, adotaremos procedimentos '
            'razoáveis de exclusão ou anonimização, ressalvadas retenções legais ou de backup '
            'por prazo limitado.',
      ),
      LegalSectionEntry(
        title: '6. Seus direitos (titular de dados)',
        body:
            'Nos termos da LGPD (art. 18), você pode solicitar: confirmação de tratamento; '
            'acesso; correção de dados incompletos ou desatualizados; anonimização, bloqueio '
            'ou eliminação de dados desnecessários; portabilidade; informação sobre compartilhamento; '
            'revogação do consentimento, quando aplicável; e oposição a tratamentos em hipóteses '
            'legais.\n\n'
            'Para exercer seus direitos, entre em contato pelos canais abaixo. '
            'Também é possível apresentar reclamação à ANPD (www.gov.br/anpd).',
      ),
      LegalSectionEntry(
        title: '7. Versão web, cookies e armazenamento local',
        body:
            'No painel web, utilizamos armazenamento local do navegador (por exemplo, IndexedDB '
            'e cache) para funcionamento offline, sessão e desempenho, conforme necessário ao '
            'serviço. Não utilizamos cookies de publicidade de terceiros. '
            'Você pode limpar dados do navegador nas configurações do dispositivo, ciente de que '
            'isso pode exigir novo login.',
      ),
      LegalSectionEntry(
        title: '8. Biometria (Face ID, Touch ID, impressão digital)',
        body:
            'O app não coleta, não armazena e não envia ao servidor imagens do rosto, mapas '
            'faciais ou templates biométricos.\n\n'
            'O desbloqueio por biometria é opcional e serve apenas para reabrir uma sessão já '
            'autenticada neste aparelho, por meio da API nativa do sistema (iOS/Android). '
            'O processamento ocorre no dispositivo; não recebemos dados biométricos.\n\n'
            'Podemos guardar apenas a preferência de uso da biometria, sem dados biométricos.',
      ),
      LegalSectionEntry(
        title: '9. Crianças e adolescentes',
        body:
            'O serviço destina-se à gestão institucional da igreja. Dados de menores podem ser '
            'cadastrados pela igreja (por exemplo, membros infantis), sob responsabilidade da '
            'liderança e dos responsáveis legais. Não direcionamos o app como serviço de consumo '
            'infantil autônomo.',
      ),
      LegalSectionEntry(
        title: '10. Atualizações desta política',
        body:
            'Esta política pode ser atualizada para refletir mudanças legais ou do produto. '
            'Alterações relevantes serão comunicadas no app, no painel web ou por e-mail, '
            'quando razoável. A data da última atualização consta no topo deste documento.',
      ),
      LegalSectionEntry(
        title: '11. Contato (privacidade e LGPD)',
        body:
            'Encarregado / canal de privacidade: $kLegalSupportEmail ou WhatsApp '
            '$kLegalSupportWhatsAppDisplay.\n\n'
            'Respondemos solicitações de titulares no prazo legal aplicável.',
      ),
    ],
  );
}
