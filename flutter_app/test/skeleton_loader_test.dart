import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestao_yahweh/ui/widgets/skeleton_loader.dart';

void main() {
  testWidgets('SkeletonLoader renders correct number of items', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SkeletonLoader(itemCount: 5),
        ),
      ),
    );
    expect(find.byType(SkeletonLoader), findsOneWidget);
  });
}
