import 'package:flutter/material.dart';

/// Lista estática de bancos suportados (Open Finance / legado).
class SupportedBanksScreen extends StatelessWidget {
  const SupportedBanksScreen({super.key});

  static const _banks = [
    'Banco do Brasil',
    'Bradesco',
    'Caixa',
    'Itaú',
    'Nubank',
    'Santander',
    'Sicoob',
    'Sicredi',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bancos suportados')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _banks.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) => ListTile(
          leading: const Icon(Icons.account_balance_rounded),
          title: Text(_banks[i]),
        ),
      ),
    );
  }
}
