import "dart:async";

import "package:flutter/foundation.dart" show kIsWeb;
import "package:flutter/material.dart";
import "package:gestao_yahweh/core/public_site_media_auth.dart";
import "package:cloud_functions/cloud_functions.dart";
import "package:cloud_firestore/cloud_firestore.dart";
import "package:url_launcher/url_launcher.dart";
import "package:gestao_yahweh/ui/widgets/version_footer.dart";
import "package:gestao_yahweh/ui/theme_clean_premium.dart";
import "package:gestao_yahweh/ui/login_page.dart";
import "package:gestao_yahweh/data/planos_oficiais.dart";
import "package:gestao_yahweh/services/plan_price_service.dart";
import "package:gestao_yahweh/ui/widgets/premium_storage_video/premium_institutional_video.dart";
import "package:gestao_yahweh/ui/widgets/marketing_gestao_yahweh_gallery.dart";
import "package:gestao_yahweh/ui/widgets/marketing_clientes_showcase_section.dart";
import "package:gestao_yahweh/services/public_site_analytics.dart";

String money(double v) => "R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}";

/// Cores de destaque por índice (mesma ordem de planosOficiais).
const _planAccents = [
  Color(0xFF1E5AA8),
  Color(0xFF2563EB),
  Color(0xFF7C3AED),
  Color(0xFFF97316),
  Color(0xFFDC2626),
  Color(0xFFF59E0B),
  Color(0xFF6B4E16),
  Color(0xFF64748B),
];
Color _accentForPlan(int index) =>
    index < _planAccents.length ? _planAccents[index] : const Color(0xFF2563EB);

/// Planos exibidos no site de divulgação = planosOficiais (mesma fonte do painel igreja e cadastro).

class SitePublicPage extends StatefulWidget {
  final String? slug;
  final bool isConviteRoute;

  const SitePublicPage({super.key, this.slug, this.isConviteRoute = false});

  @override
  State<SitePublicPage> createState() => _SitePublicPageState();
}

class _SitePublicPageState extends State<SitePublicPage> {
  final _cpfCtrl = TextEditingController();
  bool _loading = false;
  Map<String, ({double? monthly, double? annual})>? _effectivePrices;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PublicSiteMediaAuth.ensureWebAnonymousForStorage();
      });
    }
    // Preços = mesma fonte do Master: Firestore `config/plans/items` (+ fallback [planosOficiais]).
    PlanPriceService.getEffectivePrices().then((p) {
      if (mounted) setState(() => _effectivePrices = p);
    });
  }

  String? _statusMsg; // msg amigável (não mostra internal/not_found)
  Map<String, dynamic>? _church; // {tenantId, name, logoUrl, slug...}

  Timer? _autoTimer;

  @override
  void dispose() {
    _autoTimer?.cancel();
    _cpfCtrl.dispose();
    super.dispose();
  }

  String _onlyDigits(String s) => s.replaceAll(RegExp(r"[^0-9]"), "");
  bool _isEmail(String s) => s.contains('@');

  /// Normaliza CPF: 10 dígitos -> adiciona zero à esquerda (ex: 9453636891 -> 09453636891)
  String _normalizeCpf(String digits) {
    if (digits.length == 10) return '0$digits';
    return digits;
  }

  Future<void> _loadChurch({bool autoNavigateToLogin = false}) async {
    final raw = _cpfCtrl.text.trim();
    final isEmail = _isEmail(raw);
    var cpf = _onlyDigits(raw);
    cpf = _normalizeCpf(cpf);

    if (!isEmail && cpf.length != 11) {
      setState(() {
        _statusMsg = "Informe um CPF valido (11 digitos) ou e-mail.";
        _church = null;
      });
      return;
    }
    setState(() => _loading = true);
    _statusMsg = null;
    _church = null;
    try {
      // Usa APENAS callable para evitar erro de permissão Firestore (Brasil para Cristo — CPF 94536368191)
      try {
        if (isEmail) {
          final fn = FirebaseFunctions.instance.httpsCallable('resolveEmailToChurchPublic');
          final res = await fn.call({'email': raw.trim()});
          final data = Map<String, dynamic>.from(res.data as Map);
          final tid = (data['tenantId'] ?? '').toString().trim();
          if (tid.isNotEmpty && mounted) {
            setState(() {
              _church = {
                'tenantId': tid,
                'name': (data['name'] ?? tid).toString(),
                'slug': (data['slug'] ?? data['alias'] ?? tid).toString(),
                'logoUrl': (data['logoUrl'] ?? '').toString(),
              };
              _loading = false;
              _statusMsg = null;
            });
            return;
          }
        } else if (cpf.length == 11) {
          final fn = FirebaseFunctions.instance.httpsCallable('resolveCpfToChurchPublic');
          final res = await fn.call({'cpf': cpf});
          final data = Map<String, dynamic>.from(res.data as Map);
          final tid = (data['tenantId'] ?? '').toString().trim();
          if (tid.isNotEmpty && mounted) {
            setState(() {
              _church = {
                'tenantId': tid,
                'name': (data['name'] ?? tid).toString(),
                'slug': (data['slug'] ?? data['alias'] ?? tid).toString(),
                'logoUrl': (data['logoUrl'] ?? '').toString(),
              };
              _loading = false;
              _statusMsg = null;
            });
            return;
          }
        }
      } on FirebaseFunctionsException catch (e) {
        if (!mounted) return;
        final code = e.code;
        setState(() {
          _loading = false;
          _church = null;
          _statusMsg = code == 'not-found'
              ? 'Nenhuma igreja encontrada para este CPF ou e-mail.'
              : 'Não foi possível conectar. Tente novamente em instantes.';
        });
        return;
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _church = null;
          _statusMsg = 'Não foi possível conectar ao servidor. Tente novamente.';
        });
        return;
      }

      // Fallback: Firestore (se callable não retornou igreja)
      try {
      final refTenants = FirebaseFirestore.instance.collection('igrejas');
      var snapTenants = isEmail
          ? await refTenants.where('email', isEqualTo: raw.trim().toLowerCase()).limit(1).get()
          : await refTenants.where('cpf', isEqualTo: cpf).limit(1).get();
      if (snapTenants.docs.isEmpty && isEmail) {
        snapTenants = await refTenants.where('email', isEqualTo: raw.trim()).limit(1).get();
      }
      if (snapTenants.docs.isEmpty && isEmail) {
        snapTenants = await refTenants.where('gestorEmail', isEqualTo: raw.trim().toLowerCase()).limit(1).get();
      }
      if (!mounted) return;
      if (snapTenants.docs.isNotEmpty) {
        final doc = snapTenants.docs.first;
        final data = doc.data();
        setState(() {
          _church = {
            'tenantId': doc.id,
            'name': data['name'] ?? data['nome'] ?? doc.id,
            'slug': data['slug'] ?? doc.id,
            'logoUrl': data['logoUrl'] ?? data['logoUrl'],
          };
          _loading = false;
          _statusMsg = null;
        });
        return;
      }
      } catch (_) {}
      // 1b) Busca em usersIndex (ex.: Brasil para Cristo — usuário GESTOR cadastrado por CPF ou e-mail)
      QuerySnapshot<Map<String, dynamic>>? snapUsers;
      if (isEmail) {
        try {
          final usersIndexCol = FirebaseFirestore.instance.collectionGroup('usersIndex');
          snapUsers = await usersIndexCol.where('email', isEqualTo: raw.trim().toLowerCase()).limit(1).get();
          if (snapUsers.docs.isEmpty) {
            snapUsers = await usersIndexCol.where('email', isEqualTo: raw.trim()).limit(1).get();
          }
        } catch (_) {
          snapUsers = null;
        }
      } else {
        try {
          // Primeiro por campo cpf (igual ao backend) — doc ID pode ser diferente do CPF
          snapUsers = await FirebaseFirestore.instance
              .collectionGroup('usersIndex')
              .where('cpf', isEqualTo: cpf)
              .limit(1)
              .get();
          if (snapUsers.docs.isEmpty) {
            snapUsers = await FirebaseFirestore.instance
                .collectionGroup('usersIndex')
                .where(FieldPath.documentId, isEqualTo: cpf)
                .limit(1)
                .get();
          }
          if (snapUsers.docs.isEmpty && cpf.startsWith('0')) {
            snapUsers = await FirebaseFirestore.instance
                .collectionGroup('usersIndex')
                .where('cpf', isEqualTo: cpf.substring(1))
                .limit(1)
                .get();
          }
          if (snapUsers.docs.isEmpty && cpf.startsWith('0')) {
            snapUsers = await FirebaseFirestore.instance
                .collectionGroup('usersIndex')
                .where(FieldPath.documentId, isEqualTo: cpf.substring(1))
                .limit(1)
                .get();
          }
        } catch (_) {
          snapUsers = null;
        }
      }
      if (!mounted) return;
      if (snapUsers != null && snapUsers.docs.isNotEmpty) {
        final userDoc = snapUsers.docs.first;
        final pathSegments = userDoc.reference.path.split('/');
        // path: tenants/XXX/usersIndex/YYY ou igrejas/XXX/usersIndex/YYY -> tenantId = segment 1
        final tenantId = pathSegments.length >= 2 ? pathSegments[1] : '';
        if (tenantId.isNotEmpty) {
          var tenantSnap = await FirebaseFirestore.instance.collection('igrejas').doc(tenantId).get();
          if (!tenantSnap.exists) {
            tenantSnap = await FirebaseFirestore.instance.collection('igrejas').doc(tenantId).get();
          }
          if (!mounted) return;
          if (tenantSnap.exists) {
            final data = tenantSnap.data()!;
            setState(() {
              _church = {
                'tenantId': tenantId,
                'name': data['nome'] ?? data['name'] ?? tenantId,
                'slug': data['slug'] ?? data['alias'] ?? tenantId,
                'logoUrl': data['logoUrl'] ?? data['logoProcessedUrl'] ?? data['logoProcessed'],
              };
              _loading = false;
              _statusMsg = null;
            });
            _navigateToChurchLogin();
            return;
          }
        }
      }
      // 1c) Busca em igrejas por e-mail do gestor (email, gestorEmail, emailGestor)
      if (isEmail) {
        final emailNorm = raw.trim().toLowerCase();
        var snapIgrejasEmail = await FirebaseFirestore.instance
            .collection('igrejas')
            .where('email', isEqualTo: emailNorm)
            .limit(1)
            .get();
        if (snapIgrejasEmail.docs.isEmpty) {
          snapIgrejasEmail = await FirebaseFirestore.instance
              .collection('igrejas')
              .where('gestorEmail', isEqualTo: emailNorm)
              .limit(1)
              .get();
        }
        if (snapIgrejasEmail.docs.isEmpty) {
          snapIgrejasEmail = await FirebaseFirestore.instance
              .collection('igrejas')
              .where('emailGestor', isEqualTo: emailNorm)
              .limit(1)
              .get();
        }
        if (snapIgrejasEmail.docs.isEmpty) {
          snapIgrejasEmail = await FirebaseFirestore.instance
              .collection('igrejas')
              .where('emailContato', isEqualTo: emailNorm)
              .limit(1)
              .get();
        }
        if (snapIgrejasEmail.docs.isEmpty) {
          snapIgrejasEmail = await FirebaseFirestore.instance
              .collection('igrejas')
              .where('responsavelEmail', isEqualTo: emailNorm)
              .limit(1)
              .get();
        }
        if (snapIgrejasEmail.docs.isNotEmpty) {
          final doc = snapIgrejasEmail.docs.first;
          final data = doc.data();
          if (!mounted) return;
          setState(() {
            _church = {
              'tenantId': doc.id,
              'name': data['nome'] ?? data['name'] ?? doc.id,
              'slug': data['slug'] ?? doc.id,
              'logoUrl': data['logoUrl'] ?? data['logoProcessedUrl'] ?? data['logoProcessed'],
            };
            _loading = false;
            _statusMsg = null;
          });
          _navigateToChurchLogin();
          return;
        }
      }
      // 2) Se não achou em tenants/usersIndex, busca em igrejas por cnpjCpf (ex.: Brasil para Cristo)
      if (!isEmail && cpf.length == 11) {
        var snapIgrejas = await FirebaseFirestore.instance
            .collection('igrejas')
            .where('cnpjCpf', isEqualTo: cpf)
            .limit(1)
            .get();
        // Tenta CPF sem zero à esquerda (ex: 9453636891) se armazenado assim
        if (snapIgrejas.docs.isEmpty && cpf.startsWith('0')) {
          snapIgrejas = await FirebaseFirestore.instance
              .collection('igrejas')
              .where('cnpjCpf', isEqualTo: cpf.substring(1))
              .limit(1)
              .get();
        }
        if (!mounted) return;
        if (snapIgrejas.docs.isNotEmpty) {
          final doc = snapIgrejas.docs.first;
          final data = doc.data();
          setState(() {
            _church = {
              'tenantId': doc.id,
              'name': data['nome'] ?? data['name'] ?? doc.id,
              'slug': data['slug'] ?? doc.id,
              'logoUrl': data['logoUrl'] ?? data['logoProcessedUrl'] ?? data['logoProcessed'],
            };
            _loading = false;
            _statusMsg = null;
          });
          _navigateToChurchLogin();
          return;
        }
        // 3) Busca igreja pelo CPF do membro — coleção padrão: membros (igrejas/xxx/membros)
        var snapMembers = await FirebaseFirestore.instance
            .collectionGroup('membros')
            .where('CPF', isEqualTo: cpf)
            .limit(1)
            .get();
        if (snapMembers.docs.isEmpty) {
          snapMembers = await FirebaseFirestore.instance
              .collectionGroup('membros')
              .where('cpf', isEqualTo: cpf)
              .limit(1)
              .get();
        }
        if (snapMembers.docs.isEmpty) {
          snapMembers = await FirebaseFirestore.instance
              .collectionGroup('members')
              .where('CPF', isEqualTo: cpf)
              .limit(1)
              .get();
        }
        if (snapMembers.docs.isEmpty) {
          snapMembers = await FirebaseFirestore.instance
              .collectionGroup('members')
              .where('cpf', isEqualTo: cpf)
              .limit(1)
              .get();
        }
        if (!mounted) return;
        if (snapMembers.docs.isNotEmpty) {
          final memberDoc = snapMembers.docs.first;
          final pathSegments = memberDoc.reference.path.split('/');
          String tenantId = '';
          if (pathSegments.length >= 4) {
            if (pathSegments[0] == 'igrejas' && (pathSegments[2] == 'membros' || pathSegments[2] == 'members')) {
              tenantId = pathSegments[1];
            } else if (pathSegments[0] == 'tenants' && pathSegments[2] == 'members') {
              tenantId = pathSegments[1];
            }
          }
          if (tenantId.isEmpty) {
            final data = memberDoc.data();
            tenantId = (data['tenantId'] ?? data['tenant_id'] ?? data['igrejaId'] ?? data['igreja_id'] ?? '').toString().trim();
          }
          if (tenantId.isNotEmpty) {
            final tenantSnap = await FirebaseFirestore.instance.collection('igrejas').doc(tenantId).get();
            final igrejaSnap = await FirebaseFirestore.instance.collection('igrejas').doc(tenantId).get();
            if (!mounted) return;
            final data = tenantSnap.exists ? tenantSnap.data() : (igrejaSnap.exists ? igrejaSnap.data() : null);
            if (data != null) {
              setState(() {
                _church = {
                  'tenantId': tenantId,
                  'name': data['nome'] ?? data['name'] ?? data['nomeFantasia'] ?? tenantId,
                  'slug': data['slug'] ?? tenantId,
                  'logoUrl': data['logoUrl'] ?? data['logoProcessedUrl'] ?? data['logoProcessed'],
                };
                _loading = false;
                _statusMsg = null;
              });
              _navigateToChurchLogin();
              return;
            }
          }
        }
      }
      // 4) Fallback CPF: callable do backend (publicCpfIndex + usersIndex por cpf/docId)
      if (!isEmail && cpf.length == 11) {
        try {
          final fn = FirebaseFunctions.instance.httpsCallable('resolveCpfToChurchPublic');
          final res = await fn.call({'cpf': cpf});
          final data = Map<String, dynamic>.from(res.data as Map);
          final tid = (data['tenantId'] ?? '').toString().trim();
          if (tid.isNotEmpty && mounted) {
            setState(() {
              _church = {
                'tenantId': tid,
                'name': (data['name'] ?? tid).toString(),
                'slug': (data['slug'] ?? data['alias'] ?? tid).toString(),
                'logoUrl': (data['logoUrl'] ?? '').toString(),
              };
              _loading = false;
              _statusMsg = null;
            });
            _navigateToChurchLogin();
            return;
          }
        } catch (_) {
          // callable pode falhar (regras, rede); segue para mensagem final
        }
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMsg = 'Nenhuma igreja encontrada com esse CPF ou e-mail. Se você é gestor, cadastre seu e-mail (email, gestorEmail ou emailGestor) na igreja pelo Painel Master.';
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      final isPermission = msg.contains('permission_denied') || msg.contains('permission-denied');
      final isConnection = msg.contains('unavailable') || msg.contains('failed to fetch')
          || msg.contains('network') || msg.contains('socket') || msg.contains('could not reach');

      // Se deu permissão negada, tenta resolver via callable (backend tem acesso total)
      if (isPermission && _loading) {
        try {
          if (isEmail) {
            final fn = FirebaseFunctions.instance.httpsCallable('resolveEmailToChurchPublic');
            final res = await fn.call({'email': raw.trim()});
            final data = Map<String, dynamic>.from(res.data as Map);
            final tid = (data['tenantId'] ?? '').toString().trim();
            if (tid.isNotEmpty && mounted) {
              setState(() {
                _church = {
                  'tenantId': tid,
                  'name': (data['name'] ?? tid).toString(),
                  'slug': (data['slug'] ?? data['alias'] ?? tid).toString(),
                  'logoUrl': (data['logoUrl'] ?? '').toString(),
                };
                _loading = false;
                _statusMsg = null;
              });
              _navigateToChurchLogin();
              return;
            }
          } else if (cpf.length == 11) {
            final fn = FirebaseFunctions.instance.httpsCallable('resolveCpfToChurchPublic');
            final res = await fn.call({'cpf': cpf});
            final data = Map<String, dynamic>.from(res.data as Map);
            final tid = (data['tenantId'] ?? '').toString().trim();
            if (tid.isNotEmpty && mounted) {
              setState(() {
                _church = {
                  'tenantId': tid,
                  'name': (data['name'] ?? tid).toString(),
                  'slug': (data['slug'] ?? data['alias'] ?? tid).toString(),
                  'logoUrl': (data['logoUrl'] ?? '').toString(),
                };
                _loading = false;
                _statusMsg = null;
              });
              _navigateToChurchLogin();
              return;
            }
          }
        } catch (_) {
          // callable falhou; segue para mensagem abaixo
        }
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMsg = isConnection
            ? 'Não foi possível conectar ao servidor. Verifique sua internet e tente novamente.'
            : isPermission
                ? 'Sem permissão para consultar. Verifique as regras do Firestore e se o domínio está autorizado no Firebase (Authentication > Authorized domains).'
                : 'Erro ao buscar. Verifique o CPF ou e-mail e tente novamente.';
        _church = null;
      });
    }
  }

  /// Abre o Painel Master (login admin).
  void _goAdmin() {
    unawaited(PublicSiteAnalytics.logMarketingAction('marketing_master_login'));
    Navigator.of(context).pushNamedAndRemoveUntil('/login_admin', (route) => false);
  }
  void _onCpfChanged(String value) => setState(() {});

  /// Após carregar a igreja, navega direto para a página de login da igreja.
  void _navigateToChurchLogin() {
    final church = _church;
    if (church == null || !mounted) return;
    unawaited(PublicSiteAnalytics.logMarketingAction(
        'marketing_prefill_church_login'));
    final name = church['name']?.toString();
    final cpfOrEmail = _cpfCtrl.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => LoginPage(
            title: 'Entrar — Painel da Igreja',
            afterLoginRoute: '/painel',
            showFleetBranding: false,
            churchLabel: name,
            churchLogoUrl: (church['logoUrl'] ?? '').toString().trim().isEmpty
                ? null
                : (church['logoUrl'] ?? '').toString().trim(),
            prefillCpf: cpfOrEmail.isNotEmpty ? cpfOrEmail : null,
            backRoute: '/',
          ),
        ),
      );
    });
  }

  void _goChurch() {
    if (_church == null || _loading) return;
    final slug = _church!['slug'] as String?;
    if (slug != null && slug.isNotEmpty) {
      unawaited(
          PublicSiteAnalytics.logMarketingAction('marketing_open_church_slug'));
      Navigator.of(context).pushNamed('/igreja_$slug');
    }
  }

  /// AppBar curta (Android/iPhone): logo + título; ações em menu para não truncar.
  static const double _kAppBarCompactWidth = 520;

  List<Widget> _sitePublicAppBarActions(BuildContext context) {
    if (widget.isConviteRoute) return const [];
    final narrow = MediaQuery.sizeOf(context).width < _kAppBarCompactWidth;
    if (narrow) {
      return [
        PopupMenuButton<String>(
          tooltip: 'Menu',
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          color: Colors.white,
          onSelected: (value) {
            switch (value) {
              case 'planos':
                unawaited(PublicSiteAnalytics.logMarketingAction(
                    'marketing_menu_planos'));
                Navigator.pushNamed(context, '/planos');
                break;
              case 'cadastro':
                unawaited(PublicSiteAnalytics.logMarketingAction(
                    'marketing_menu_cadastro'));
                Navigator.pushNamed(context, '/cadastro');
                break;
              case 'entrar':
                unawaited(PublicSiteAnalytics.logMarketingAction(
                    'marketing_menu_entrar'));
                Navigator.pushNamed(context, '/igreja/login');
                break;
            }
          },
          itemBuilder: (ctx) => const [
            PopupMenuItem(value: 'planos', child: Text('Planos')),
            PopupMenuItem(value: 'cadastro', child: Text('Cadastro')),
            PopupMenuItem(value: 'entrar', child: Text('Entrar')),
          ],
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () {
          unawaited(
              PublicSiteAnalytics.logMarketingAction('marketing_bar_planos'));
          Navigator.pushNamed(context, '/planos');
        },
        child: const Text(
          'Planos',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      TextButton(
        onPressed: () {
          unawaited(PublicSiteAnalytics.logMarketingAction(
              'marketing_bar_cadastro'));
          Navigator.pushNamed(context, '/cadastro');
        },
        child: const Text(
          'Cadastro',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(right: 4),
        child: TextButton(
          onPressed: () {
            unawaited(PublicSiteAnalytics.logMarketingAction(
                'marketing_bar_entrar'));
            Navigator.pushNamed(context, '/igreja/login');
          },
          child: const Text(
            'Entrar',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    ];
  }

  Widget _sitePublicAppBarTitle(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < _kAppBarCompactWidth;
    return Row(
      children: [
        _PublicSiteGestaoYahwehLogo(size: narrow ? 28 : 32),
        SizedBox(width: narrow ? 8 : 10),
        Expanded(
          child: Text(
            'Gestão YAHWEH',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: narrow ? 16 : 18,
              letterSpacing: 0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final topBar = ThemeCleanPremium.navSidebar;
    final scaffold = Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              topBar,
              ThemeCleanPremium.primaryLight,
              const Color(0xFFF0F4FF),
              ThemeCleanPremium.surfaceVariant,
            ],
            stops: const [0.0, 0.12, 0.22, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                leading: widget.isConviteRoute
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 26),
                        onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
                        tooltip: 'Voltar ao início',
                      )
                    : null,
                title: _sitePublicAppBarTitle(context),
                backgroundColor: topBar,
                foregroundColor: Colors.white,
                elevation: 0,
                scrolledUnderElevation: 0,
                iconTheme: const IconThemeData(color: Colors.white),
                actions: _sitePublicAppBarActions(context),
              ),
              Expanded(
                child: _buildBody(context),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.isConviteRoute) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && context.mounted) {
            Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
          }
        },
        child: scaffold,
      );
    }
    return scaffold;
  }

  Widget _buildBody(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final isMobile = c.maxWidth < 900;
        final left = _LeftHero(onGoAdmin: _goAdmin);
        final right = _ChurchLookupCard(
          cpfCtrl: _cpfCtrl,
          loading: _loading,
          statusMsg: _statusMsg,
          church: _church,
          onLoad: _loadChurch,
          onCpfChanged: _onCpfChanged,
          onEnter: (_church != null && !_loading) ? _goChurch : null,
        );
        final topRow = isMobile
            ? Column(
                children: [left, const SizedBox(height: 16), right],
              )
            : Row(
                children: [Expanded(child: left), const SizedBox(width: 16), SizedBox(width: 420, child: right)],
              );
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        final hPad =
            isMobile ? ThemeCleanPremium.spaceMd : ThemeCleanPremium.spaceLg;
        return SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              hPad,
              hPad,
              hPad,
              hPad + bottomInset + 8,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 920),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _SectionTitle(
                              title: 'Conheça em vídeo',
                              subtitle:
                                  'Pitch rápido do ecossistema: app, painel da igreja e site público.',
                            ),
                            const SizedBox(height: 10),
                            PremiumMarketingHeroVideo(
                              height: isMobile ? 200 : 280,
                              defaultStoragePath: 'public/videos/institucional.mp4',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    topRow,
                    const SizedBox(height: 24),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 960),
                        child: const MarketingClientesShowcaseSection(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 960),
                        child: const MarketingGestaoYahwehGallerySection(
                          excludePdfFromPublicGallery: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const _SectionTitle(
                      title: "Planos oficiais",
                      subtitle: "Todos os modulos inclusos. O que muda e a escala de uso.",
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: planosOficiais.asMap().entries.map((e) {
                        final i = e.key;
                        final p = e.value;
                        final ep = _effectivePrices?[p.id];
                        return SizedBox(
                          width: isMobile ? double.infinity : 280,
                          child: _PlanCard(
                            plan: p,
                            accent: _accentForPlan(i),
                            priceMonthly: ep?.monthly ?? p.monthlyPrice,
                            priceAnnual: ep?.annual ?? p.annualPrice,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pushNamed(context, '/cadastro'),
                        icon: const Icon(Icons.person_add_rounded),
                        label: const Text('Escolhi meu plano — Ir para cadastro'),
                        style: FilledButton.styleFrom(
                          backgroundColor: ThemeCleanPremium.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: ThemeCleanPremium.spaceXl,
                              vertical: ThemeCleanPremium.spaceMd),
                          minimumSize: const Size(48, 48),
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const _SectionTitle(
                      title: "Tudo o que está incluído",
                      subtitle:
                          "Nenhum plano é capado: o sistema completo já vem ativo, com estes módulos.",
                    ),
                    const SizedBox(height: 16),
                    const _PremiumIncludedFeaturesGrid(),
                    const SizedBox(height: 28),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 720),
                        child: const _YahwehPublicFaqSection(),
                      ),
                    ),
                    const SizedBox(height: 26),
                    _DownloadsSection(),
                    const SizedBox(height: 22),
                    Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 720),
                        child: const _YahwehAudienceFooterBar(),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const VersionFooter(showVersion: true),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _YahwehPublicFaqSection extends StatelessWidget {
  const _YahwehPublicFaqSection();

  @override
  Widget build(BuildContext context) {
    Widget tile(String q, String a) {
      return ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        title: Text(q, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(a, style: TextStyle(fontSize: 14, height: 1.4, color: Colors.grey.shade800)),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Perguntas frequentes',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.blueGrey.shade900,
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              tile(
                'Posso usar meu próprio domínio no site da igreja?',
                'Sim. O site público pode ser divulgado com o endereço da igreja (slug) e integrações de contato; domínio personalizado depende da sua configuração de DNS e hospedagem — nossa equipe orienta na contratação.',
              ),
              const Divider(height: 1),
              tile(
                'Preciso instalar algo para os membros?',
                'Há aplicativo para celular e acesso web. Membros podem usar o que for mais conveniente; o painel da igreja funciona em navegador e em app.',
              ),
              const Divider(height: 1),
              tile(
                'Onde ficam armazenados dados e mídias?',
                'Em infraestrutura cloud com regras de acesso por perfil (igreja, gestor e membro). Você controla o que é público no site e o que permanece interno.',
              ),
              const Divider(height: 1),
              tile(
                'LGPD e responsabilidade pelos dados',
                'A igreja é titular dos dados dos membros cadastrados. O Gestão YAHWEH fornece ferramentas de gestão e boas práticas de acesso; recomendamos política interna de privacidade alinhada à LGPD.',
              ),
              const Divider(height: 1),
              tile(
                'Como falo com o suporte?',
                'Use os canais indicados após o cadastro ou no painel. Priorizamos estabilidade, segurança e resposta em horário comercial.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _YahwehAudienceFooterBar extends StatelessWidget {
  const _YahwehAudienceFooterBar();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Três entradas claras',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Colors.blueGrey.shade900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Escolha o caminho que combina com você: visitante, membro ou liderança.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.35),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ActionChip(
              avatar: const Icon(Icons.waving_hand_rounded, size: 18),
              label: const Text('Visitantes — cadastro da igreja'),
              onPressed: () {
                unawaited(PublicSiteAnalytics.logMarketingAction(
                    'marketing_footer_chip_cadastro'));
                Navigator.pushNamed(context, '/cadastro');
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.login_rounded, size: 18),
              label: const Text('Membros — entrar no sistema'),
              onPressed: () {
                unawaited(PublicSiteAnalytics.logMarketingAction(
                    'marketing_footer_chip_entrar'));
                Navigator.pushNamed(context, '/igreja/login');
              },
            ),
            ActionChip(
              avatar: const Icon(Icons.workspace_premium_rounded, size: 18),
              label: const Text('Líderes — planos e limites'),
              onPressed: () {
                unawaited(PublicSiteAnalytics.logMarketingAction(
                    'marketing_footer_chip_planos'));
                Navigator.pushNamed(context, '/planos');
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Membros: use CPF ou e-mail para localizar sua igreja na página inicial. Líderes: após o cadastro da igreja, liberamos o painel completo conforme o plano.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
        ),
      ],
    );
  }
}

/// Logo da marca no site público: PNG → ícone do app → identidade tipográfica (nunca área vazia).
class _PublicSiteGestaoYahwehLogo extends StatelessWidget {
  final double size;

  const _PublicSiteGestaoYahwehLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    final primary = ThemeCleanPremium.primary;
    return Image.asset(
      'assets/LOGO_GESTAO_YAHWEH.png',
      height: size,
      width: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => Image.asset(
        'assets/icon/app_icon.png',
        height: size * 0.88,
        width: size * 0.88,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) =>
            _PublicSiteGestaoYahwehTextMark(maxSide: size, color: primary),
      ),
    );
  }
}

class _PublicSiteGestaoYahwehTextMark extends StatelessWidget {
  final double maxSide;
  final Color color;

  const _PublicSiteGestaoYahwehTextMark({
    required this.maxSide,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: maxSide,
        maxWidth: maxSide * 1.35,
        minHeight: 72,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.church_rounded, size: maxSide * 0.22, color: color),
            const SizedBox(height: 8),
            Text(
              'Gestão',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 22,
                height: 1.05,
              ),
            ),
            Text(
              'YAHWEH',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 26,
                height: 1.05,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LeftHero extends StatelessWidget {
  final VoidCallback onGoAdmin;
  const _LeftHero({required this.onGoAdmin});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 700;
    return Container(
      decoration: ThemeCleanPremium.premiumSurfaceCard,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: isMobile ? ThemeCleanPremium.spaceLg : 32,
            vertical: isMobile ? ThemeCleanPremium.spaceLg : ThemeCleanPremium.spaceXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final logoSize = isMobile
                      ? (constraints.maxWidth < 400 ? 200.0 : 280.0)
                      : 480.0;
                  return _PublicSiteGestaoYahwehLogo(size: logoSize);
                },
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Gestão YAHWEH",
              style: TextStyle(
                fontSize: isMobile ? 22 : 28,
                fontWeight: FontWeight.w900,
                color: ThemeCleanPremium.primary,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              "Um sistema de excelência feito para sua igreja",
              style: TextStyle(
                fontSize: isMobile ? 15 : 20,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    unawaited(PublicSiteAnalytics.logMarketingAction(
                        'marketing_hero_login'));
                    Navigator.pushNamed(context, '/igreja/login');
                  },
                  icon: const Icon(Icons.login),
                  label: const Text('Login'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ThemeCleanPremium.primary,
                    side: const BorderSide(color: ThemeCleanPremium.primary),
                    minimumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(ThemeCleanPremium.radiusMd)),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    unawaited(PublicSiteAnalytics.logMarketingAction(
                        'marketing_hero_planos'));
                    Navigator.pushNamed(context, '/planos');
                  },
                  icon: const Icon(Icons.star),
                  label: const Text('Ver planos'),
                ),
                TextButton.icon(
                  onPressed: onGoAdmin,
                  icon: const Icon(Icons.admin_panel_settings),
                  label: const Text('Painel Master'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              width: 4,
              height: 26,
              decoration: BoxDecoration(
                color: ThemeCleanPremium.primary,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: ThemeCleanPremium.onSurface,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(
            color: ThemeCleanPremium.onSurfaceVariant,
            height: 1.45,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final PlanoOficial plan;
  final Color accent;
  final double? priceMonthly;
  final double? priceAnnual;
  const _PlanCard({required this.plan, required this.accent, this.priceMonthly, this.priceAnnual});

  @override
  Widget build(BuildContext context) {
    final monthly = priceMonthly ?? plan.monthlyPrice;
    final annual = priceAnnual ?? plan.annualPrice;
    return Container(
      padding: const EdgeInsets.all(ThemeCleanPremium.spaceMd),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ThemeCleanPremium.radiusMd),
        border: Border.all(
            color: plan.featured
                ? accent.withValues(alpha: 0.55)
                : const Color(0xFFE5EAF3)),
        boxShadow: ThemeCleanPremium.softUiCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              if (plan.featured)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text("Recomendado", style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(plan.members, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 10),
          Text(
            monthly == null ? (plan.note ?? "Sob consulta") : "${money(monthly)} / mes",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: accent),
          ),
          const SizedBox(height: 6),
          if (annual != null)
            Text("Anual: ${money(annual)} (12 por 10)", style: const TextStyle(fontSize: 12, color: Colors.black45)),
          const SizedBox(height: 12),
          const Text(
            "App + Painel Web + Site publico\nEventos, escalas e financeiro\nBackups automaticos e seguranca",
            style: TextStyle(color: Colors.black54, height: 1.35, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Módulos incluídos no plano — ícones Material 3, cartões com sombra suave.
class _PremiumIncludedFeaturesGrid extends StatelessWidget {
  const _PremiumIncludedFeaturesGrid();

  static const List<({IconData icon, String label})> _features = [
    (icon: Icons.groups_rounded, label: 'Controle de membros'),
    (icon: Icons.cake_rounded, label: 'Aniversariantes'),
    (icon: Icons.campaign_rounded, label: 'Avisos'),
    (icon: Icons.event_available_rounded, label: 'Eventos'),
    (icon: Icons.calendar_view_week_rounded, label: 'Escalas'),
    (icon: Icons.calendar_month_rounded, label: 'Agendas'),
    (icon: Icons.volunteer_activism_rounded, label: 'Pedidos de orações'),
    (icon: Icons.public_rounded, label: 'Site público integrado ao sistema'),
    (icon: Icons.inventory_2_rounded, label: 'Controle de patrimônio'),
    (icon: Icons.account_balance_wallet_rounded, label: 'Controle financeiro'),
    (icon: Icons.workspace_premium_rounded, label: 'Emissão de certificados'),
    (icon: Icons.badge_rounded, label: 'Cartão membro moderno'),
    (icon: Icons.devices_rounded, label: 'Acesso via web, Android e iOS (Apple)'),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = ThemeCleanPremium.primary;
    return LayoutBuilder(
      builder: (context, c) {
        final maxW = c.maxWidth;
        final cols = maxW > 920 ? 3 : (maxW > 560 ? 2 : 1);
        const gap = 14.0;
        final tileW = cols <= 1
            ? maxW
            : (maxW - gap * (cols - 1)) / cols;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: _features.map((f) {
            return SizedBox(
              width: tileW,
              child: _PremiumFeatureTile(
                icon: f.icon,
                label: f.label,
                accent: primary,
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _PremiumFeatureTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;

  const _PremiumFeatureTile({
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent,
                  Color.lerp(accent, const Color(0xFF312E81), 0.35)!,
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                height: 1.28,
                color: Color(0xFF0F172A),
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadsSection extends StatelessWidget {
  Future<void> _open(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Baixar aplicativo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Android e iOS no mesmo pacote. Use o link abaixo para baixar.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .doc('config/appDownloads')
                  .snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? {};
                final folderUrl = (data['driveFolderUrl'] ?? '').toString();
                final androidUrl = (data['androidUrl'] ?? '').toString();
                final iosUrl = (data['iosUrl'] ?? '').toString();
                final downloadUrl = androidUrl.isNotEmpty
                    ? androidUrl
                    : (iosUrl.isNotEmpty ? iosUrl : folderUrl);

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: downloadUrl.isEmpty
                          ? null
                          : () => _open(downloadUrl),
                      icon: const Icon(Icons.android),
                      label: const Text('Android'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: downloadUrl.isEmpty
                          ? null
                          : () => _open(downloadUrl),
                      icon: const Icon(Icons.apple),
                      label: const Text('iOS'),
                    ),
                    OutlinedButton.icon(
                      onPressed: folderUrl.isEmpty
                          ? null
                          : () => _open(folderUrl),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Pasta de downloads'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ChurchLookupCard extends StatelessWidget {
  final TextEditingController cpfCtrl;
  final bool loading;
  final String? statusMsg;
  final Map<String, dynamic>? church;
  final VoidCallback onLoad;
  final VoidCallback? onEnter;
  final ValueChanged<String>? onCpfChanged;

  const _ChurchLookupCard({
    required this.cpfCtrl,
    required this.loading,
    required this.statusMsg,
    required this.church,
    required this.onLoad,
    required this.onEnter,
    this.onCpfChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE4E7EF)),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Acessar minha igreja", style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              controller: cpfCtrl,
              keyboardType: TextInputType.emailAddress,
              onChanged: onCpfChanged,
              decoration: const InputDecoration(
                labelText: "CPF ou e-mail",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: loading ? null : () => onLoad(),
                    icon: loading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                    label: const Text("Carregar igreja"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onEnter,
                    child: const Text("Abrir igreja"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (statusMsg != null)
              Text(
                statusMsg!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            if (church != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F8FB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE4E7EF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (church?["name"] ?? church?["tenantName"] ?? "Igreja encontrada").toString(),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Tenant: ${(church?["tenantId"] ?? "").toString()}",
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            const Text(
              "Digite seu CPF ou e-mail e clique em \"Carregar igreja\". Você será levado à página de login da sua igreja.",
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Text(
              "Sou gestor — criar minha igreja",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  unawaited(PublicSiteAnalytics.logMarketingAction(
                      'marketing_signup_google'));
                  Navigator.pushNamed(context, '/signup');
                },
                icon: const Icon(Icons.g_mobiledata_rounded, size: 22),
                label: const Text("Criar conta com Google (30 dias grátis)"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Você terá 30 dias para testar. Depois, complete os dados da igreja (logo, endereço, etc.) no painel.",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

