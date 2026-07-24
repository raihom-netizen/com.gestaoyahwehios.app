import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/core/design_system/app_theme.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_auth_state.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_service.dart';
import 'package:gestao_yahweh/features/chat/presentation/telegram_chat_list_screen.dart';

/// Login TDLib: telefone → OTP → 2FA.
class TelegramLoginScreen extends StatefulWidget {
  const TelegramLoginScreen({super.key});

  @override
  State<TelegramLoginScreen> createState() => _TelegramLoginScreenState();
}

class _TelegramLoginScreenState extends State<TelegramLoginScreen> {
  final _phoneCtrl = TextEditingController(text: '+55');
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  StreamSubscription<TdlibAuthSnapshot>? _sub;
  TdlibAuthSnapshot _auth = TdlibAuthSnapshot.idle;
  bool _busy = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final svc = TdLibService.instance;
    _sub = svc.authorizationStateStream.listen((snap) {
      if (!mounted) return;
      setState(() {
        _auth = snap;
        if (snap.phase != TdlibAuthPhase.error) _localError = null;
      });
      if (snap.phase == TdlibAuthPhase.ready) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => const TelegramChatListScreen(),
            ),
          );
        });
      }
    });
    await svc.init();
    if (mounted) setState(() => _auth = svc.currentAuth);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _localError = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _localError = e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final err = _localError ??
        (_auth.phase == TdlibAuthPhase.error ? _auth.message : null);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('YAHWEH Chat — TDLib'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Icon(
                      Icons.bolt_rounded,
                      size: 48,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Yahweh Chat',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _statusLabel(_auth),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (kIsWeb) ...[
                      const SizedBox(height: 24),
                      _infoCard(
                        context,
                        'TDLib usa FFI e não roda na Web. '
                        'Teste no Android/iOS: flutter run',
                      ),
                    ],
                    if (err != null && err.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _errorCard(context, err),
                    ],
                    const SizedBox(height: 28),
                    if (_auth.phase == TdlibAuthPhase.waitPhoneNumber ||
                        _auth.phase == TdlibAuthPhase.error) ...[
                      TextFormField(
                        controller: _phoneCtrl,
                        enabled: !_busy &&
                            _auth.phase != TdlibAuthPhase.unsupported,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9+\s]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Telefone',
                          hintText: '+55 62 99999-0000',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                          ),
                        ),
                        validator: (v) {
                          final t = (v ?? '').replaceAll(RegExp(r'\s'), '');
                          if (t.length < 10) return 'Telefone incompleto';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        style: AppComponentStyles.primaryFilled,
                        onPressed: _busy ||
                                (_auth.phase != TdlibAuthPhase.waitPhoneNumber &&
                                    _auth.phase != TdlibAuthPhase.error)
                            ? null
                            : () {
                                if (!(_formKey.currentState?.validate() ??
                                    false)) {
                                  return;
                                }
                                _run(() async {
                                  if (_auth.phase == TdlibAuthPhase.error) {
                                    await TdLibService.instance.init();
                                  }
                                  await TdLibService.instance
                                      .sendPhoneNumber(_phoneCtrl.text);
                                });
                              },
                        child: _busy
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Enviar código'),
                      ),
                    ],
                    if (_auth.phase == TdlibAuthPhase.waitCode) ...[
                      TextFormField(
                        controller: _codeCtrl,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Código',
                          hintText: _auth.codeInfoHint ?? '12345',
                          border: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        style: AppComponentStyles.primaryFilled,
                        onPressed: _busy
                            ? null
                            : () => _run(() => TdLibService.instance
                                .sendCode(_codeCtrl.text)),
                        child: const Text('Confirmar código'),
                      ),
                    ],
                    if (_auth.phase == TdlibAuthPhase.waitPassword) ...[
                      TextFormField(
                        controller: _passwordCtrl,
                        enabled: !_busy,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Senha 2FA',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        style: AppComponentStyles.primaryFilled,
                        onPressed: _busy
                            ? null
                            : () => _run(() => TdLibService.instance
                                .sendPassword(_passwordCtrl.text)),
                        child: const Text('Entrar'),
                      ),
                    ],
                    if (_auth.phase ==
                        TdlibAuthPhase.waitOtherDeviceConfirmation) ...[
                      _infoCard(
                        context,
                        _auth.message ??
                            'Confirme o login em outro dispositivo.',
                      ),
                    ],
                    if (_auth.phase == TdlibAuthPhase.waitRegistration) ...[
                      _infoCard(
                        context,
                        'Esta conta ainda não existe. '
                        'Conclua o cadastro e volte aqui.',
                      ),
                    ],
                    if (_auth.phase == TdlibAuthPhase.initializing) ...[
                      const SizedBox(height: 12),
                      const Center(child: CircularProgressIndicator()),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _statusLabel(TdlibAuthSnapshot auth) {
    switch (auth.phase) {
      case TdlibAuthPhase.unsupported:
        return auth.message ?? 'Plataforma sem suporte';
      case TdlibAuthPhase.ready:
        return 'Conectado';
      default:
        return auth.message ?? 'Preparando…';
    }
  }

  Widget _infoCard(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text),
    );
  }

  Widget _errorCard(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}
