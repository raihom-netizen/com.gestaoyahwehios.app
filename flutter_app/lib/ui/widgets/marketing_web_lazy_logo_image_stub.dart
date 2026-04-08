import 'package:flutter/material.dart';
import 'package:gestao_yahweh/ui/widgets/safe_network_image.dart';

/// Fora da web: [SafeNetworkImage] (app / painel). [webpUrl] é ignorado — usar só [imageUrl].
Widget marketingClienteShowcaseImage({
  required String imageUrl,
  String? webpUrl,
  required double width,
  required double height,
  required BoxFit fit,
  required Widget placeholder,
  required Widget errorWidget,
  int? memCacheWidth,
  int? memCacheHeight,
}) {
  return SafeNetworkImage(
    key: ValueKey<String>('mkt_showcase_${imageUrl}_$webpUrl'),
    imageUrl: imageUrl,
    width: width,
    height: height,
    fit: fit,
    memCacheWidth: memCacheWidth,
    memCacheHeight: memCacheHeight,
    placeholder: placeholder,
    errorWidget: errorWidget,
    skipFreshDisplayUrl: false,
  );
}
