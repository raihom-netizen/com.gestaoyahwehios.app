import 'package:flutter/material.dart';

/// Mantém estado da aba (scroll, formulário, busca) ao trocar [TabBarView] / [IndexedStack].
class KeepAliveTabChild extends StatefulWidget {
  const KeepAliveTabChild({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAliveTabChild> createState() => _KeepAliveTabChildState();
}

class _KeepAliveTabChildState extends State<KeepAliveTabChild>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
