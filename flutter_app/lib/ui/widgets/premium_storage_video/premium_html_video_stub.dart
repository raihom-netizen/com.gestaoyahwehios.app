import 'package:flutter/material.dart';

/// Fora da web: não usar — o chamador deve preferir [VideoPlayer].
Widget buildPremiumHtmlVideo(
  String url, {
  bool autoplay = false,
  bool loop = false,
  bool muted = false,
  bool controls = true,
}) {
  return const SizedBox.shrink();
}
