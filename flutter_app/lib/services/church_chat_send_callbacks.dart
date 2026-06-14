/// Callbacks canónicos do envio de chat — uma assinatura em todo o pipeline.
///
/// Evita divergência entre engine, serviços e UI (ex.: web build falhar por
/// `void Function(bool)?` vs `void Function(bool, {String? messageId})?`).
typedef ChurchChatSendCompleteCallback = void Function(
  bool ok, {
  String? messageId,
});

typedef ChurchChatSendErrorCallback = void Function(String message);
