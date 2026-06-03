import 'package:gestao_yahweh/core/church_shell_indices.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Retornar onde parou» — rota, aba do painel, chat, membro, etc. (offline-first UX).
///
/// Limpar só em [LoginPreferences.prepareChurchAccountSwitch] / troca de conta.
abstract final class AppResumeStateService {
  AppResumeStateService._();

  static const _kLastRoute = 'last_route';
  static const _kShellIndex = 'gv_resume_shell_index_v1';
  static const _kTenantId = 'gv_resume_tenant_id_v1';
  static const _kChatThreadId = 'gv_resume_chat_thread_v1';
  static const _kMemberDocId = 'gv_resume_member_doc_v1';
  static const _kPatrimonioDocId = 'gv_resume_patrimonio_doc_v1';
  static const _kEventDocId = 'gv_resume_event_doc_v1';
  static const _kAvisoDocId = 'gv_resume_aviso_doc_v1';

  static Future<void> saveLastRoute(String route) async {
    final r = route.trim();
    if (r.isEmpty) return;
    if (r == '/' || r.startsWith('/login') || r.startsWith('/igreja/login')) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastRoute, r);
  }

  static Future<String?> readLastRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final v = (prefs.getString(_kLastRoute) ?? '').trim();
    return v.isEmpty ? null : v;
  }

  static Future<void> saveShellContext({
    required String tenantId,
    required int shellIndex,
  }) async {
    final tid = tenantId.trim();
    if (tid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTenantId, tid);
    await prefs.setInt(_kShellIndex, shellIndex);
  }

  static Future<({String tenantId, int shellIndex})?> readShellContext() async {
    final prefs = await SharedPreferences.getInstance();
    final tid = (prefs.getString(_kTenantId) ?? '').trim();
    if (tid.isEmpty) return null;
    if (!prefs.containsKey(_kShellIndex)) return null;
    return (tenantId: tid, shellIndex: prefs.getInt(_kShellIndex) ?? 0);
  }

  static Future<void> saveChatThread({
    required String tenantId,
    required String threadId,
  }) async {
    final tid = tenantId.trim();
    final th = threadId.trim();
    if (tid.isEmpty || th.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTenantId, tid);
    await prefs.setString(_kChatThreadId, th);
    await prefs.setInt(_kShellIndex, ChurchShellIndices.chatIgreja);
  }

  static Future<({String tenantId, String threadId})?> readChatThread() async {
    final prefs = await SharedPreferences.getInstance();
    final tid = (prefs.getString(_kTenantId) ?? '').trim();
    final th = (prefs.getString(_kChatThreadId) ?? '').trim();
    if (tid.isEmpty || th.isEmpty) return null;
    return (tenantId: tid, threadId: th);
  }

  static Future<void> saveOpenMember({
    required String tenantId,
    required String memberDocId,
  }) async {
    final tid = tenantId.trim();
    final mid = memberDocId.trim();
    if (tid.isEmpty || mid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTenantId, tid);
    await prefs.setString(_kMemberDocId, mid);
    await prefs.setInt(_kShellIndex, ChurchShellIndices.membros);
  }

  static Future<void> saveOpenPatrimonio({
    required String tenantId,
    required String itemDocId,
  }) async {
    final tid = tenantId.trim();
    final id = itemDocId.trim();
    if (tid.isEmpty || id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTenantId, tid);
    await prefs.setString(_kPatrimonioDocId, id);
    await prefs.setInt(_kShellIndex, ChurchShellIndices.patrimonio);
  }

  static Future<void> saveOpenEvent({
    required String tenantId,
    required String eventDocId,
  }) async {
    final tid = tenantId.trim();
    final id = eventDocId.trim();
    if (tid.isEmpty || id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTenantId, tid);
    await prefs.setString(_kEventDocId, id);
    await prefs.setInt(_kShellIndex, ChurchShellIndices.muralEventos);
  }

  static Future<void> saveOpenAviso({
    required String tenantId,
    required String avisoDocId,
  }) async {
    final tid = tenantId.trim();
    final id = avisoDocId.trim();
    if (tid.isEmpty || id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTenantId, tid);
    await prefs.setString(_kAvisoDocId, id);
    await prefs.setInt(_kShellIndex, ChurchShellIndices.muralAvisos);
  }

  static Future<({String tenantId, String memberDocId})?> readOpenMember() async {
    final prefs = await SharedPreferences.getInstance();
    final tid = (prefs.getString(_kTenantId) ?? '').trim();
    final mid = (prefs.getString(_kMemberDocId) ?? '').trim();
    if (tid.isEmpty || mid.isEmpty) return null;
    return (tenantId: tid, memberDocId: mid);
  }

  static Future<({String tenantId, String itemDocId})?> readOpenPatrimonio() async {
    final prefs = await SharedPreferences.getInstance();
    final tid = (prefs.getString(_kTenantId) ?? '').trim();
    final id = (prefs.getString(_kPatrimonioDocId) ?? '').trim();
    if (tid.isEmpty || id.isEmpty) return null;
    return (tenantId: tid, itemDocId: id);
  }

  static Future<({String tenantId, String eventDocId})?> readOpenEvent() async {
    final prefs = await SharedPreferences.getInstance();
    final tid = (prefs.getString(_kTenantId) ?? '').trim();
    final id = (prefs.getString(_kEventDocId) ?? '').trim();
    if (tid.isEmpty || id.isEmpty) return null;
    return (tenantId: tid, eventDocId: id);
  }

  static Future<({String tenantId, String avisoDocId})?> readOpenAviso() async {
    final prefs = await SharedPreferences.getInstance();
    final tid = (prefs.getString(_kTenantId) ?? '').trim();
    final id = (prefs.getString(_kAvisoDocId) ?? '').trim();
    if (tid.isEmpty || id.isEmpty) return null;
    return (tenantId: tid, avisoDocId: id);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLastRoute);
    await prefs.remove(_kShellIndex);
    await prefs.remove(_kTenantId);
    await prefs.remove(_kChatThreadId);
    await prefs.remove(_kMemberDocId);
    await prefs.remove(_kPatrimonioDocId);
    await prefs.remove(_kEventDocId);
    await prefs.remove(_kAvisoDocId);
  }
}
