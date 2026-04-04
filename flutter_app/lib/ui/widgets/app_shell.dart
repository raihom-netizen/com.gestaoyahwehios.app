import 'package:flutter/material.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const AppShell({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: SizedBox.expand(child: child),
    );
  }
}
