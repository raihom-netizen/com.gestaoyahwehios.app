import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:gestao_yahweh/models/user_profile.dart';
import 'package:gestao_yahweh/ui/pages/finance_page.dart'
    show FinanceScreen;

/// Adapter: YAHWEH shell calls FinancePage(tenantId, role, ...) ->
/// wraps Controle Total's FinanceScreen(uid, profile, ...).
class FinancePage extends StatefulWidget {
  const FinancePage({
    super.key,
    required this.tenantId,
    required this.role,
    this.cpf = '',
    this.podeVerFinanceiro = true,
    this.permissions = const [],
    this.embeddedInShell = false,
    this.initialTabIndex,
    this.openLancamentoId,
  });

  final String tenantId;
  final String role;
  final String cpf;
  final bool podeVerFinanceiro;
  final List<String>? permissions;
  final bool embeddedInShell;
  final int? initialTabIndex;
  final String? openLancamentoId;

  @override
  State<FinancePage> createState() => _FinancePageAdapterState();
}

class _FinancePageAdapterState extends State<FinancePage> {
  UserProfile? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() {
        _error = 'Utilizador nao autenticado.';
        _loading = false;
      });
      return;
    }
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('utilizadores')
          .doc(uid)
          .get();
      final data = userDoc.data() ?? <String, dynamic>{};
      final profile = UserProfile.fromFirestoreMap(uid, data);
      if (mounted) {
        setState(() {
          _profile = profile;
          _loading = false;
        });
      }
    } catch (e) {
      final profile = UserProfile(
        uid: uid,
        cpf: '',
        cpfMasked: '',
        email: FirebaseAuth.instance.currentUser?.email ?? '',
        name: FirebaseAuth.instance.currentUser?.displayName ?? 'Utilizador',
        role: widget.role.isNotEmpty ? widget.role : 'user',
        plan: 'premium',
        planStatus: 'active',
      );
      if (mounted) {
        setState(() {
          _profile = profile;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_profile == null) {
      return const Center(child: Text('Perfil nao carregado.'));
    }
    return FinanceScreen(
      key: ValueKey('finance_screen_${widget.tenantId}'),
      uid: _profile!.uid,
      profile: _profile!,
      isShellVisible: widget.embeddedInShell,
    );
  }
}
