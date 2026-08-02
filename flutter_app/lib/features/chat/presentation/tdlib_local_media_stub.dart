import 'package:flutter/material.dart';
import 'package:gestao_yahweh/features/chat/data/tdlib_auth_state.dart';

class TdlibLocalMedia extends StatelessWidget {
  const TdlibLocalMedia({
    super.key,
    required this.message,
    this.outgoing = false,
  });

  final TdlibMessageItem message;
  final bool outgoing;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
