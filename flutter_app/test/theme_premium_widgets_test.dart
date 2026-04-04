import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';

void main() {
  testWidgets('premiumEmptyState renderiza título e subtítulo', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThemeCleanPremium.premiumEmptyState(
            icon: Icons.inbox_outlined,
            title: 'Nada aqui',
            subtitle: 'Descrição auxiliar',
          ),
        ),
      ),
    );
    expect(find.text('Nada aqui'), findsOneWidget);
    expect(find.text('Descrição auxiliar'), findsOneWidget);
  });

  testWidgets('premiumErrorState mostra retry quando onRetry não é nulo',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThemeCleanPremium.premiumErrorState(
            title: 'Falha ao carregar',
            onRetry: () => tapped = true,
          ),
        ),
      ),
    );
    expect(find.text('Falha ao carregar'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    expect(tapped, isTrue);
  });
}
