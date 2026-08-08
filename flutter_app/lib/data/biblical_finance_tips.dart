import 'package:gestao_yahweh/services/financial_tips_catalog_service.dart';

/// Dicas financeiras com base bíblica — catálogo principal do Início WISDOMAPP.
const List<FinancialTipDisplayItem> kBiblicalFinanceTips = [
  FinancialTipDisplayItem(
    id: 'bib_proverbios_16_3',
    titulo: 'Consagre seus planos ao Senhor',
    descricao:
        'Quando você alinha metas financeiras com propósito e integridade, '
        'decide melhor onde gastar, poupar e investir. Planeje o mês com calma, '
        'registre entradas e saídas e revise semanalmente.',
    categoriaSlug: 'biblia',
    iconKey: 'menu_book',
    colorKey: 'indigo',
    ordem: 10,
    referenciaBiblica: 'Provérbios 16:3',
    textoVersiculo:
        'Consagre ao Senhor tudo o que você faz, e os seus planos serão bem-sucedidos.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_21_20',
    titulo: 'Sabedoria guarda tesouro',
    descricao:
        'Há tesouro desejável e azeite na casa do sábio; o tolo devora tudo o que possui. '
        'Construa reserva de emergência antes de aumentar o padrão de vida.',
    categoriaSlug: 'biblia',
    iconKey: 'savings',
    colorKey: 'green',
    ordem: 20,
    referenciaBiblica: 'Provérbios 21:20',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_22_7',
    titulo: 'Cuidado com o endividamento',
    descricao:
        'O rico domina sobre o pobre, e o que toma emprestado é servo do que empresta. '
        'Evite juros altos, quite dívidas caras primeiro e só use crédito com plano de pagamento.',
    categoriaSlug: 'biblia',
    iconKey: 'warning',
    colorKey: 'red',
    ordem: 30,
    referenciaBiblica: 'Provérbios 22:7',
  ),
  FinancialTipDisplayItem(
    id: 'bib_lucas_14_28',
    titulo: 'Conte o custo antes de construir',
    descricao:
        'Qual de vós, querendo edificar uma torre, não se assenta primeiro a calcular '
        'os gastos? Antes de comprar ou contratar, simule parcelas e impacto no orçamento mensal.',
    categoriaSlug: 'biblia',
    iconKey: 'bar_chart',
    colorKey: 'blue',
    ordem: 40,
    referenciaBiblica: 'Lucas 14:28',
  ),
  FinancialTipDisplayItem(
    id: 'bib_malaquias_3_10',
    titulo: 'Primeiro o que é de Deus',
    descricao:
        'Trazei todos os dízimos à casa do tesouro. Honrar a Deus com os bens é prioridade; '
        'depois organize despesas fixas, metas e poupança com o que resta.',
    categoriaSlug: 'biblia',
    iconKey: 'account_balance',
    colorKey: 'purple',
    ordem: 50,
    referenciaBiblica: 'Malaquias 3:10',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_27_23',
    titulo: 'Conheça sua situação financeira',
    descricao:
        'Procura conhecer o estado dos teus rebanhos e inclina o coração ao teu rebanho. '
        'Revise saldos, faturas e metas toda semana — o que não se mede, não se administra.',
    categoriaSlug: 'biblia',
    iconKey: 'search',
    colorKey: 'teal',
    ordem: 60,
    referenciaBiblica: 'Provérbios 27:23',
  ),
  FinancialTipDisplayItem(
    id: 'bib_eclesiastes_11_2',
    titulo: 'Diversifique com prudência',
    descricao:
        'Reparte com sete e ainda com oito, pois não sabes que mal haverá sobre a terra. '
        'Não concentre tudo em uma única aplicação ou renda; tenha reserva líquida e metas claras.',
    categoriaSlug: 'biblia',
    iconKey: 'trending_up',
    colorKey: 'primary',
    ordem: 70,
    referenciaBiblica: 'Eclesiastes 11:2',
  ),
  FinancialTipDisplayItem(
    id: 'bib_1timoteo_6_10',
    titulo: 'Dinheiro é meio, não fim',
    descricao:
        'A raiz de todos os males é o amor ao dinheiro. Use recursos para servir, '
        'cuidar da família e cumprir propósito — sem viver para acumular ou comparar.',
    categoriaSlug: 'biblia',
    iconKey: 'shield',
    colorKey: 'orange',
    ordem: 80,
    referenciaBiblica: '1 Timóteo 6:10',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_13_11',
    titulo: 'Riqueza gradual e constante',
    descricao:
        'A riqueza de vaidade diminui, mas quem a junta pouco a pouco a aumenta. '
        'Automatize uma parte da renda para poupança e invista com disciplina, não com pressa.',
    categoriaSlug: 'biblia',
    iconKey: 'timer',
    colorKey: 'green',
    ordem: 90,
    referenciaBiblica: 'Provérbios 13:11',
  ),
  FinancialTipDisplayItem(
    id: 'bib_mateus_6_21',
    titulo: 'Onde está seu tesouro',
    descricao:
        'Onde estiver o teu tesouro, aí estará também o teu coração. '
        'Defina metas financeiras que reflitam valores — educação, família, generosidade e segurança.',
    categoriaSlug: 'biblia',
    iconKey: 'lightbulb',
    colorKey: 'indigo',
    ordem: 100,
    referenciaBiblica: 'Mateus 6:21',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_3_9_10',
    titulo: 'Honre com o primeiro fruto',
    descricao:
        'Honra ao Senhor com os teus bens e com as primícias de toda a tua renda. '
        'Ao receber salário ou receita, separe primeiro dízimos, reserva e contas essenciais.',
    categoriaSlug: 'biblia',
    iconKey: 'percent',
    colorKey: 'purple',
    ordem: 110,
    referenciaBiblica: 'Provérbios 3:9-10',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_6_6_8',
    titulo: 'Formiga: poupar no tempo certo',
    descricao:
        'Vai ter com a formiga, ó preguiçoso, considera os seus caminhos e sê sábio. '
        'Ela prepara no verão o seu mantimento. Guarde parte da renda nos meses bons para os difíceis.',
    categoriaSlug: 'biblia',
    iconKey: 'savings',
    colorKey: 'teal',
    ordem: 120,
    referenciaBiblica: 'Provérbios 6:6-8',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_15_22',
    titulo: 'Peça conselho antes de decidir',
    descricao:
        'Onde não há conselho, frustram-se os planos; mas na multidão de conselheiros eles se firmam. '
        'Converse com quem administra bem antes de grandes compras, empréstimos ou investimentos.',
    categoriaSlug: 'biblia',
    iconKey: 'menu_book',
    colorKey: 'blue',
    ordem: 130,
    referenciaBiblica: 'Provérbios 15:22',
  ),
  FinancialTipDisplayItem(
    id: 'bib_romanos_13_8',
    titulo: 'Não fique devendo a ninguém',
    descricao:
        'A ninguém devais coisa alguma, a não ser o amor. '
        'Quite compromissos no prazo, evite parcelar o que não cabe no orçamento e negocie quando necessário.',
    categoriaSlug: 'biblia',
    iconKey: 'credit_card',
    colorKey: 'red',
    ordem: 140,
    referenciaBiblica: 'Romanos 13:8',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_24_27',
    titulo: 'Prepare antes de expandir',
    descricao:
        'Prepara os teus trabalhos fora, apronta o teu campo, e então edifica a tua casa. '
        'Fortaleça reserva e fluxo de caixa antes de assumir novas despesas fixas ou upgrades.',
    categoriaSlug: 'biblia',
    iconKey: 'bar_chart',
    colorKey: 'primary',
    ordem: 150,
    referenciaBiblica: 'Provérbios 24:27',
  ),
  FinancialTipDisplayItem(
    id: 'bib_2corintios_9_7',
    titulo: 'Generosidade com alegria',
    descricao:
        'Deus ama quem dá com alegria. Inclua ajuda a quem precisa no orçamento — '
        'com planejamento, não por impulso que comprometa contas básicas.',
    categoriaSlug: 'biblia',
    iconKey: 'lightbulb',
    colorKey: 'green',
    ordem: 160,
    referenciaBiblica: '2 Coríntios 9:7',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_11_1',
    titulo: 'Peso justo nos negócios',
    descricao:
        'Balança falsa é abominação ao Senhor, mas o peso justo é o seu contentamento. '
        'Seja transparente em preços, contratos e cobranças — integridade protege reputação e finanças.',
    categoriaSlug: 'biblia',
    iconKey: 'shield',
    colorKey: 'blueGrey',
    ordem: 170,
    referenciaBiblica: 'Provérbios 11:1',
  ),
  FinancialTipDisplayItem(
    id: 'bib_filipenses_4_11_12',
    titulo: 'Contentamento e disciplina',
    descricao:
        'Aprendi a contentar-me com o que tenho. Contentamento não é parar de crescer — '
        'é viver dentro do orçamento com gratidão enquanto busca metas com sabedoria.',
    categoriaSlug: 'biblia',
    iconKey: 'timer',
    colorKey: 'purple',
    ordem: 180,
    referenciaBiblica: 'Filipenses 4:11-12',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_22_26_27',
    titulo: 'Não se comprometa por impulso',
    descricao:
        'Não estejas entre os que se comprometem, entre os que ficam por fiadores de empréstimos. '
        'Evite avalizar dívidas alheias e contratos que você não controla.',
    categoriaSlug: 'biblia',
    iconKey: 'warning',
    colorKey: 'deepOrange',
    ordem: 190,
    referenciaBiblica: 'Provérbios 22:26-27',
  ),
  FinancialTipDisplayItem(
    id: 'bib_joao_10_10',
    titulo: 'Vida plena com propósito',
    descricao:
        'Eu vim para que tenham vida e a tenham com abundância. '
        'Administrar bem liberta tempo e recursos para o que realmente importa: família, fé e serviço.',
    categoriaSlug: 'biblia',
    iconKey: 'trending_up',
    colorKey: 'teal',
    ordem: 200,
    referenciaBiblica: 'João 10:10',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_28_20',
    titulo: 'Fidelidade traz prosperidade',
    descricao:
        'O homem fiel será ricamente abençoado, mas quem quer enriquecer depressa não ficará impune. '
        'Prefira ganhos honestos e consistentes a atalhos arriscados ou esquemas duvidosos.',
    categoriaSlug: 'biblia',
    iconKey: 'account_balance',
    colorKey: 'green',
    ordem: 210,
    referenciaBiblica: 'Provérbios 28:20',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_21_5',
    titulo: 'Planejamento vence a pressa',
    descricao:
        'Os planos do diligente conduzem à fartura, mas todo apressado acaba na pobreza. '
        'Antes de gastar, planeje o mês; decisões financeiras com calma rendem mais que impulsos.',
    categoriaSlug: 'biblia',
    iconKey: 'bar_chart',
    colorKey: 'blue',
    ordem: 220,
    referenciaBiblica: 'Provérbios 21:5',
    textoVersiculo:
        'Os planos bem elaborados levam à fartura; mas o apressado sempre acaba na miséria.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_13_22',
    titulo: 'Deixe herança e legado',
    descricao:
        'O homem de bem deixa herança aos filhos de seus filhos. '
        'Poupe e invista pensando no longo prazo — o que você constrói hoje pode abençoar gerações.',
    categoriaSlug: 'biblia',
    iconKey: 'account_balance',
    colorKey: 'green',
    ordem: 230,
    referenciaBiblica: 'Provérbios 13:22',
    textoVersiculo:
        'O homem de bem deixa herança aos filhos de seus filhos, mas a riqueza do pecador é depositada para o justo.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_10_4',
    titulo: 'Mãos diligentes prosperam',
    descricao:
        'As mãos preguiçosas empobrecem, mas as mãos diligentes enriquecem. '
        'Renda vem do trabalho constante: dedique-se, aprimore-se e seja fiel na sua função.',
    categoriaSlug: 'biblia',
    iconKey: 'trending_up',
    colorKey: 'teal',
    ordem: 240,
    referenciaBiblica: 'Provérbios 10:4',
    textoVersiculo:
        'As mãos preguiçosas empobrecem o homem, porém as mãos diligentes lhe trazem riqueza.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_14_23',
    titulo: 'Trabalho traz proveito',
    descricao:
        'Em todo trabalho há proveito, mas o só falar leva à pobreza. '
        'Menos promessas, mais ação: transforme metas financeiras em passos práticos e constantes.',
    categoriaSlug: 'biblia',
    iconKey: 'savings',
    colorKey: 'indigo',
    ordem: 250,
    referenciaBiblica: 'Provérbios 14:23',
    textoVersiculo:
        'Todo trabalho árduo traz proveito, mas o só falar leva à pobreza.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_lucas_16_10',
    titulo: 'Fiel no pouco, fiel no muito',
    descricao:
        'Quem é fiel no pouco também é fiel no muito. '
        'Administre bem o pouco que tem hoje — a boa gestão de pequenas quantias prepara para as maiores.',
    categoriaSlug: 'biblia',
    iconKey: 'shield',
    colorKey: 'purple',
    ordem: 260,
    referenciaBiblica: 'Lucas 16:10',
    textoVersiculo:
        'Quem é fiel no pouco, também é fiel no muito; e quem é injusto no pouco, também é injusto no muito.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_eclesiastes_5_10',
    titulo: 'Dinheiro não sacia o coração',
    descricao:
        'Quem ama o dinheiro jamais terá o suficiente. '
        'Defina o quanto é "suficiente" para você e evite a corrida sem fim por sempre ter mais.',
    categoriaSlug: 'biblia',
    iconKey: 'money_off',
    colorKey: 'red',
    ordem: 270,
    referenciaBiblica: 'Eclesiastes 5:10',
    textoVersiculo:
        'Quem ama o dinheiro jamais terá o suficiente; quem ama as riquezas jamais se satisfará com a sua renda.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_hebreus_13_5',
    titulo: 'Contentamento sem avareza',
    descricao:
        'Vivam livres do amor ao dinheiro, contentando-se com o que têm. '
        'Gratidão pelo que já possui reduz gastos por comparação e ansiedade financeira.',
    categoriaSlug: 'biblia',
    iconKey: 'timer',
    colorKey: 'orange',
    ordem: 280,
    referenciaBiblica: 'Hebreus 13:5',
    textoVersiculo:
        'Conservai a vossa vida livre do amor ao dinheiro, contentando-vos com o que tendes.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_1timoteo_6_6',
    titulo: 'Piedade com contentamento',
    descricao:
        'A piedade com contentamento é grande fonte de lucro. '
        'Alinhar fé e finanças traz paz: viva dentro do orçamento com propósito, não por status.',
    categoriaSlug: 'biblia',
    iconKey: 'account_balance',
    colorKey: 'primary',
    ordem: 290,
    referenciaBiblica: '1 Timóteo 6:6',
    textoVersiculo:
        'De fato, a piedade com contentamento é grande fonte de lucro.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_mateus_6_24',
    titulo: 'Deus no lugar do dinheiro',
    descricao:
        'Ninguém pode servir a dois senhores: a Deus e ao dinheiro. '
        'Faça o dinheiro servir aos seus valores e propósito — não deixe que ele governe suas decisões.',
    categoriaSlug: 'biblia',
    iconKey: 'shield',
    colorKey: 'deepOrange',
    ordem: 300,
    referenciaBiblica: 'Mateus 6:24',
    textoVersiculo:
        'Ninguém pode servir a dois senhores... Não podeis servir a Deus e às riquezas.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_mateus_6_33',
    titulo: 'Busque primeiro o Reino',
    descricao:
        'Busquem em primeiro lugar o Reino de Deus, e todas as coisas serão acrescentadas. '
        'Prioridades certas trazem provisão: coloque Deus em primeiro e organize o resto com sabedoria.',
    categoriaSlug: 'biblia',
    iconKey: 'search',
    colorKey: 'green',
    ordem: 310,
    referenciaBiblica: 'Mateus 6:33',
    textoVersiculo:
        'Buscai, pois, em primeiro lugar, o seu Reino e a sua justiça, e todas essas coisas vos serão acrescentadas.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_22_1',
    titulo: 'Bom nome vale mais',
    descricao:
        'Mais vale o bom nome do que muitas riquezas. '
        'Pague em dia, cumpra acordos e mantenha o crédito limpo — reputação abre portas que o dinheiro não abre.',
    categoriaSlug: 'biblia',
    iconKey: 'credit_card',
    colorKey: 'blue',
    ordem: 320,
    referenciaBiblica: 'Provérbios 22:1',
    textoVersiculo:
        'Mais digno de ser escolhido é o bom nome do que as muitas riquezas.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_15_16',
    titulo: 'Pouco com paz vale mais',
    descricao:
        'Melhor é o pouco com o temor do Senhor do que grande tesouro com inquietação. '
        'Prefira segurança e tranquilidade a riscos que tiram seu sono por um ganho maior.',
    categoriaSlug: 'biblia',
    iconKey: 'savings',
    colorKey: 'teal',
    ordem: 330,
    referenciaBiblica: 'Provérbios 15:16',
    textoVersiculo:
        'Melhor é o pouco com o temor do Senhor do que grande tesouro onde há inquietação.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_16_8',
    titulo: 'Pouco com justiça',
    descricao:
        'Melhor é o pouco com justiça do que grandes rendas com injustiça. '
        'Ganhos honestos duram; evite atalhos, fraudes e esquemas que prometem enriquecer rápido.',
    categoriaSlug: 'biblia',
    iconKey: 'shield',
    colorKey: 'indigo',
    ordem: 340,
    referenciaBiblica: 'Provérbios 16:8',
    textoVersiculo:
        'Melhor é o pouco com justiça do que grande renda com injustiça.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_23_4_5',
    titulo: 'Não se esgote por riqueza',
    descricao:
        'Não te fatigues para enriquecer; as riquezas criam asas e voam. '
        'Trabalhe com equilíbrio: saúde e família não se recuperam, e o dinheiro é passageiro.',
    categoriaSlug: 'biblia',
    iconKey: 'timer',
    colorKey: 'orange',
    ordem: 350,
    referenciaBiblica: 'Provérbios 23:4-5',
    textoVersiculo:
        'Não te fatigues para enriquecer; desiste de confiar na tua própria sabedoria.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_30_8_9',
    titulo: 'Nem pobreza, nem excesso',
    descricao:
        'Não me dês nem a pobreza nem a riqueza; dá-me o pão que me for necessário. '
        'Busque o equilíbrio: o suficiente com sabedoria protege o coração da ganância e da falta.',
    categoriaSlug: 'biblia',
    iconKey: 'account_balance',
    colorKey: 'purple',
    ordem: 360,
    referenciaBiblica: 'Provérbios 30:8-9',
    textoVersiculo:
        'Não me dês nem a pobreza nem a riqueza; dá-me apenas o alimento que me é necessário.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_19_17',
    titulo: 'Dar ao pobre é emprestar a Deus',
    descricao:
        'Quem trata bem o pobre empresta ao Senhor, e Ele o recompensará. '
        'Inclua a generosidade no orçamento — ajudar quem precisa é investimento que Deus honra.',
    categoriaSlug: 'biblia',
    iconKey: 'lightbulb',
    colorKey: 'green',
    ordem: 370,
    referenciaBiblica: 'Provérbios 19:17',
    textoVersiculo:
        'Quem trata bem o pobre empresta ao Senhor, e Ele o recompensará.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_11_24_25',
    titulo: 'A alma generosa prospera',
    descricao:
        'Um dá generosamente e vê aumentar; a alma generosa prosperará. '
        'Generosidade planejada não empobrece — abra espaço no orçamento para abençoar e ser abençoado.',
    categoriaSlug: 'biblia',
    iconKey: 'trending_up',
    colorKey: 'teal',
    ordem: 380,
    referenciaBiblica: 'Provérbios 11:24-25',
    textoVersiculo:
        'Há quem distribua generosamente, e cada vez tem mais; e há quem retenha mais do que é justo, e vem a empobrecer.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_28_19',
    titulo: 'Trabalho firme, pão farto',
    descricao:
        'Quem trabalha a sua terra terá fartura de pão; quem persegue fantasias colherá pobreza. '
        'Prefira fontes de renda reais e consistentes a promessas de dinheiro fácil.',
    categoriaSlug: 'biblia',
    iconKey: 'savings',
    colorKey: 'blue',
    ordem: 390,
    referenciaBiblica: 'Provérbios 28:19',
    textoVersiculo:
        'Quem trabalha a sua terra terá fartura de pão, mas quem persegue fantasias se fartará de pobreza.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_27_12',
    titulo: 'O prudente prevê o perigo',
    descricao:
        'O prudente vê o perigo e se abriga; o inexperiente segue adiante e sofre as consequências. '
        'Tenha reserva de emergência e seguros — antecipar riscos evita dívidas em imprevistos.',
    categoriaSlug: 'biblia',
    iconKey: 'shield',
    colorKey: 'indigo',
    ordem: 400,
    referenciaBiblica: 'Provérbios 27:12',
    textoVersiculo:
        'O prudente vê o perigo e se abriga; mas os inexperientes seguem adiante e sofrem as consequências.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_21_17',
    titulo: 'Cuidado com o excesso de prazer',
    descricao:
        'Quem ama o prazer empobrecerá; quem ama o vinho e o luxo nunca enriquecerá. '
        'Lazer é saudável com limite: defina um valor mensal para diversão sem comprometer o essencial.',
    categoriaSlug: 'biblia',
    iconKey: 'fastfood',
    colorKey: 'deepOrange',
    ordem: 410,
    referenciaBiblica: 'Provérbios 21:17',
    textoVersiculo:
        'Quem se entrega aos prazeres passará necessidade; quem se apega ao vinho e ao azeite jamais será rico.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_deuteronomio_8_18',
    titulo: 'Deus dá poder para produzir',
    descricao:
        'Lembra-te do Senhor, pois é Ele quem te dá poder para adquirir riquezas. '
        'Reconheça a fonte da provisão e administre com gratidão, disciplina e propósito.',
    categoriaSlug: 'biblia',
    iconKey: 'account_balance',
    colorKey: 'primary',
    ordem: 420,
    referenciaBiblica: 'Deuteronômio 8:18',
    textoVersiculo:
        'Mas lembra-te do Senhor, teu Deus, pois é Ele que te dá força para produzires riqueza.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_salmos_37_21',
    titulo: 'O justo paga e reparte',
    descricao:
        'O ímpio toma emprestado e não paga; o justo se compadece e reparte. '
        'Honre suas dívidas e mantenha a palavra — integridade financeira é testemunho e proteção.',
    categoriaSlug: 'biblia',
    iconKey: 'credit_card',
    colorKey: 'red',
    ordem: 430,
    referenciaBiblica: 'Salmos 37:21',
    textoVersiculo:
        'Os ímpios tomam emprestado e não pagam, mas os justos dão com generosidade.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_salmos_24_1',
    titulo: 'Tudo pertence a Deus',
    descricao:
        'Do Senhor é a terra e tudo o que nela existe. '
        'Você é administrador, não dono absoluto — decisões financeiras são atos de mordomia diante de Deus.',
    categoriaSlug: 'biblia',
    iconKey: 'menu_book',
    colorKey: 'purple',
    ordem: 440,
    referenciaBiblica: 'Salmos 24:1',
    textoVersiculo:
        'Do Senhor é a terra e a sua plenitude, o mundo e os que nele habitam.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_lucas_12_15',
    titulo: 'Guarde-se da ganância',
    descricao:
        'A vida não consiste na quantidade de bens. Acautelai-vos de toda a avareza. '
        'Meça o sucesso por propósito e relacionamentos, não pelo acúmulo de coisas.',
    categoriaSlug: 'biblia',
    iconKey: 'money_off',
    colorKey: 'orange',
    ordem: 450,
    referenciaBiblica: 'Lucas 12:15',
    textoVersiculo:
        'Tende cuidado! Guardai-vos de toda a ganância; porque a vida de um homem não consiste na abundância dos seus bens.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_galatas_6_7',
    titulo: 'Você colhe o que semeia',
    descricao:
        'Aquilo que o homem semear, isso também ceifará. '
        'Cada real poupado e cada hábito financeiro é uma semente — plante bem hoje para colher amanhã.',
    categoriaSlug: 'biblia',
    iconKey: 'trending_up',
    colorKey: 'green',
    ordem: 460,
    referenciaBiblica: 'Gálatas 6:7',
    textoVersiculo:
        'Não vos enganeis: de Deus não se zomba; pois tudo o que o homem semear, isso também ceifará.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_2corintios_9_6',
    titulo: 'Semeie com fartura',
    descricao:
        'Quem semeia pouco, pouco colhe; quem semeia com fartura, com fartura colhe. '
        'Investir e contribuir com constância e boa medida amplia os frutos ao longo do tempo.',
    categoriaSlug: 'biblia',
    iconKey: 'savings',
    colorKey: 'teal',
    ordem: 470,
    referenciaBiblica: '2 Coríntios 9:6',
    textoVersiculo:
        'Aquele que semeia pouco, pouco também colherá; e o que semeia com fartura, com abundância também colherá.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_tiago_4_13_15',
    titulo: 'Planeje sob a vontade de Deus',
    descricao:
        'Não presuma do amanhã: diga "se o Senhor quiser, faremos isto ou aquilo". '
        'Faça planos financeiros com humildade e flexibilidade, prontos para ajustar diante dos imprevistos.',
    categoriaSlug: 'biblia',
    iconKey: 'bar_chart',
    colorKey: 'blue',
    ordem: 480,
    referenciaBiblica: 'Tiago 4:13-15',
    textoVersiculo:
        'Em vez disso, devíeis dizer: Se o Senhor quiser, viveremos e faremos isto ou aquilo.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_24_3_4',
    titulo: 'Sabedoria edifica a casa',
    descricao:
        'Com sabedoria se edifica a casa, e com bom senso os aposentos se enchem de bens. '
        'Conhecimento e planejamento fazem o patrimônio crescer — invista em educação financeira.',
    categoriaSlug: 'biblia',
    iconKey: 'menu_book',
    colorKey: 'indigo',
    ordem: 490,
    referenciaBiblica: 'Provérbios 24:3-4',
    textoVersiculo:
        'Pela sabedoria se edifica a casa, e com discernimento ela se firma; pelo conhecimento os cômodos se enchem do que é precioso e agradável.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_31_16',
    titulo: 'Avalie antes de investir',
    descricao:
        'Ela avalia um campo e o compra; com o que ganha, planta uma vinha. '
        'Analise antes de aplicar: pesquise, calcule o retorno e só então invista com critério.',
    categoriaSlug: 'biblia',
    iconKey: 'search',
    colorKey: 'purple',
    ordem: 500,
    referenciaBiblica: 'Provérbios 31:16',
    textoVersiculo:
        'Ela avalia um campo e o compra; com o que ganha planta uma vinha.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_mateus_6_19_20',
    titulo: 'Tesouros que não perecem',
    descricao:
        'Não ajunteis tesouros na terra, onde a traça e a ferrugem corroem; ajuntai tesouros no céu. '
        'Invista também no eterno: generosidade e propósito têm valor que nenhuma crise apaga.',
    categoriaSlug: 'biblia',
    iconKey: 'shield',
    colorKey: 'primary',
    ordem: 510,
    referenciaBiblica: 'Mateus 6:19-20',
    textoVersiculo:
        'Não acumuleis para vós tesouros na terra... Mas acumulai para vós tesouros no céu.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_20_21',
    titulo: 'Riqueza rápida não dura',
    descricao:
        'A herança adquirida às pressas no princípio não será abençoada no fim. '
        'Desconfie de ganhos fáceis e rápidos; construir com constância é mais seguro e duradouro.',
    categoriaSlug: 'biblia',
    iconKey: 'timer',
    colorKey: 'red',
    ordem: 520,
    referenciaBiblica: 'Provérbios 20:21',
    textoVersiculo:
        'A herança que no princípio se obtém às pressas, no fim não será abençoada.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_11_28',
    titulo: 'Não confie nas riquezas',
    descricao:
        'Quem confia em suas riquezas cairá, mas os justos florescerão como a folhagem verde. '
        'Diversifique e não deposite sua segurança apenas no dinheiro — ele é instável.',
    categoriaSlug: 'biblia',
    iconKey: 'warning',
    colorKey: 'deepOrange',
    ordem: 530,
    referenciaBiblica: 'Provérbios 11:28',
    textoVersiculo:
        'Quem confia em suas riquezas certamente cairá, mas os justos florescerão como a folhagem verdejante.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_salmos_62_10',
    titulo: 'Não apegue o coração aos bens',
    descricao:
        'Se as vossas riquezas aumentam, não ponhais nelas o coração. '
        'Deixe o dinheiro crescer sem se tornar seu senhor — mantenha valores acima do saldo.',
    categoriaSlug: 'biblia',
    iconKey: 'account_balance',
    colorKey: 'blueGrey',
    ordem: 540,
    referenciaBiblica: 'Salmos 62:10',
    textoVersiculo:
        'Ainda que aumente a vossa riqueza, não ponhais nela o coração.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_3_27_28',
    titulo: 'Pague o que deve, no prazo',
    descricao:
        'Não digas ao próximo: "volte amanhã", tendo tu contigo o que dar hoje. '
        'Quite compromissos assim que puder — atrasar o que já pode pagar gera juros e desgaste.',
    categoriaSlug: 'biblia',
    iconKey: 'credit_card',
    colorKey: 'orange',
    ordem: 550,
    referenciaBiblica: 'Provérbios 3:27-28',
    textoVersiculo:
        'Não digas ao teu próximo: Vai e volta, amanhã to darei, tendo-o tu contigo.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_25_28',
    titulo: 'Autocontrole nos gastos',
    descricao:
        'Como cidade sem muros é quem não sabe dominar o próprio espírito. '
        'Disciplina protege as finanças: espere antes de comprar e evite decisões movidas por emoção.',
    categoriaSlug: 'biblia',
    iconKey: 'shield',
    colorKey: 'indigo',
    ordem: 560,
    referenciaBiblica: 'Provérbios 25:28',
    textoVersiculo:
        'Como a cidade derrubada, que não tem muros, assim é o homem que não pode conter o seu espírito.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_14_15',
    titulo: 'Não creia em tudo (golpes)',
    descricao:
        'O ingênuo crê em tudo, mas o prudente atenta para os seus passos. '
        'Desconfie de promessas milagrosas e verifique tudo — cautela evita golpes e perdas.',
    categoriaSlug: 'biblia',
    iconKey: 'search',
    colorKey: 'red',
    ordem: 570,
    referenciaBiblica: 'Provérbios 14:15',
    textoVersiculo:
        'O ingênuo crê em qualquer palavra, mas o prudente atenta para os seus passos.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_colossenses_3_23',
    titulo: 'Trabalhe como para o Senhor',
    descricao:
        'Tudo o que fizerdes, fazei de todo o coração, como para o Senhor. '
        'Excelência no trabalho valoriza sua renda e abre oportunidades — faça bem o que faz.',
    categoriaSlug: 'biblia',
    iconKey: 'trending_up',
    colorKey: 'green',
    ordem: 580,
    referenciaBiblica: 'Colossenses 3:23',
    textoVersiculo:
        'Tudo quanto fizerdes, fazei-o de todo o coração, como para o Senhor e não para homens.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_lucas_16_11',
    titulo: 'Fidelidade com o dinheiro',
    descricao:
        'Se não fostes fiéis com as riquezas deste mundo, quem vos confiará as verdadeiras? '
        'Administrar bem o dinheiro é prova de caráter e prepara para responsabilidades maiores.',
    categoriaSlug: 'biblia',
    iconKey: 'account_balance',
    colorKey: 'teal',
    ordem: 590,
    referenciaBiblica: 'Lucas 16:11',
    textoVersiculo:
        'Se, pois, no injusto dinheiro não fostes fiéis, quem vos confiará as verdadeiras riquezas?',
  ),
  FinancialTipDisplayItem(
    id: 'bib_eclesiastes_7_12',
    titulo: 'Sabedoria protege como dinheiro',
    descricao:
        'A sabedoria é defesa, como o dinheiro é defesa; mas ela preserva a vida de quem a possui. '
        'Antes de acumular recursos, acumule conhecimento — decisões sábias valem mais que o saldo.',
    categoriaSlug: 'biblia',
    iconKey: 'menu_book',
    colorKey: 'blue',
    ordem: 600,
    referenciaBiblica: 'Eclesiastes 7:12',
    textoVersiculo:
        'Porque a sabedoria serve de defesa, como de defesa serve o dinheiro; mas a excelência do conhecimento é que a sabedoria preserva a vida de quem a possui.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_1cronicas_29_14',
    titulo: 'Devolver o que é de Deus',
    descricao:
        'Tudo vem de ti, e do que é teu to damos. '
        'Contribuir e ser generoso é devolver uma parte do que já é de Deus — faça-o com alegria e planejamento.',
    categoriaSlug: 'biblia',
    iconKey: 'percent',
    colorKey: 'purple',
    ordem: 610,
    referenciaBiblica: '1 Crônicas 29:14',
    textoVersiculo:
        'Porque tudo vem de ti, e das tuas mãos to damos.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_28_22',
    titulo: 'Ganância cega o julgamento',
    descricao:
        'O invejoso corre atrás das riquezas e não percebe que a pobreza o aguarda. '
        'Pressa por lucro leva a decisões ruins — invista com calma, informação e paciência.',
    categoriaSlug: 'biblia',
    iconKey: 'warning',
    colorKey: 'deepOrange',
    ordem: 620,
    referenciaBiblica: 'Provérbios 28:22',
    textoVersiculo:
        'O invejoso corre atrás das riquezas e não percebe que a pobreza o aguarda.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_12_11',
    titulo: 'Cultive o que é real',
    descricao:
        'Quem cultiva a sua terra terá fartura de pão, mas quem persegue ilusões não tem juízo. '
        'Concentre esforços em fontes de renda concretas em vez de sonhos sem plano.',
    categoriaSlug: 'biblia',
    iconKey: 'savings',
    colorKey: 'green',
    ordem: 630,
    referenciaBiblica: 'Provérbios 12:11',
    textoVersiculo:
        'Quem trabalha a sua terra terá fartura de pão, mas quem segue coisas vãs é falto de juízo.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_1timoteo_6_9',
    titulo: 'A ânsia de enriquecer',
    descricao:
        'Os que querem ficar ricos caem em tentação e em muitas ambições insensatas e nocivas. '
        'Busque prosperar com propósito e limites — evite dívidas e riscos movidos pela ambição desmedida.',
    categoriaSlug: 'biblia',
    iconKey: 'money_off',
    colorKey: 'red',
    ordem: 640,
    referenciaBiblica: '1 Timóteo 6:9',
    textoVersiculo:
        'Os que querem ficar ricos caem em tentação, em armadilhas e em muitos desejos descontrolados e nocivos.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_31_18',
    titulo: 'Acompanhe seus resultados',
    descricao:
        'Ela sente que o seu ganho é bom; a sua lâmpada não se apaga de noite. '
        'Monitore receitas e despesas de perto — quem acompanha os números toma decisões melhores.',
    categoriaSlug: 'biblia',
    iconKey: 'bar_chart',
    colorKey: 'teal',
    ordem: 650,
    referenciaBiblica: 'Provérbios 31:18',
    textoVersiculo:
        'Ela percebe que o seu comércio é bom; a sua lâmpada não se apaga de noite.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_13_18',
    titulo: 'Aceite correção e aprenda',
    descricao:
        'Pobreza e vergonha virão ao que rejeita a disciplina, mas quem acolhe a correção será honrado. '
        'Reveja erros financeiros sem orgulho: aprender com eles é o caminho para prosperar.',
    categoriaSlug: 'biblia',
    iconKey: 'lightbulb',
    colorKey: 'orange',
    ordem: 660,
    referenciaBiblica: 'Provérbios 13:18',
    textoVersiculo:
        'Quem despreza a disciplina cai na pobreza e na vergonha, mas quem acolhe a repreensão recebe tratamento honroso.',
  ),
];
