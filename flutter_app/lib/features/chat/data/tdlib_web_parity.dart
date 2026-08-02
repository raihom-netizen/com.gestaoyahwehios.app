import 'package:gestao_yahweh/services/church_telegram_launcher.dart';

/// Paridade Web = Android = iOS na UX: na Web o motor é o **Telegram Web
/// oficial** embutido (TDLib nativo não existe em browsers).
///
/// Mesma conta Telegram do pastor/líder — grupos e DMs abrem no cliente web.
abstract final class TdlibWebParity {
  TdlibWebParity._();

  static const homeUrl = 'https://web.telegram.org/k/';

  static String conversationsHome() => homeUrl;

  static String? departmentUrl(Map<String, dynamic> deptData) {
    final invite = ChurchTelegramLauncher.inviteFromDeptData(deptData);
    if (invite == null || invite.isEmpty) return homeUrl;
    return ChurchTelegramLauncher.toWebClientUrl(invite);
  }

  static String? memberDmUrl(String phoneRaw) {
    final dm = ChurchTelegramLauncher.dmUrlFromPhone(phoneRaw);
    if (dm == null) return null;
    return ChurchTelegramLauncher.toWebClientUrl(dm);
  }

  static const bannerTitle = 'Web · Telegram oficial';
  static const bannerBody =
      'Na web o Yahweh Chat usa o Telegram Web (mesma conta). '
      'No Android/iOS o motor TDLib nativo fica no aparelho — push e sync locais.';
}
