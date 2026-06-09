# AUDITORIA LEGADO — Gestão YAHWEH

Gerado: 2026-06-09 14:18

## Padrão: `collection\('tenants'\)`

_Nenhuma ocorrência._

## Padrão: `collection\('church_aliases'\)`

```
flutter_app/lib\services\multi_tenant_diagnostic_service.dart:133:          .collection('church_aliases')
```
Total linhas (cap 80): 1

## Padrão: `collection\('church_roots'\)`

_Nenhuma ocorrência._

## Padrão: `tenantResolver`

```
flutter_app/lib\services\debug_church_audit_service.dart:115:    'tenantResolver',
```
Total linhas (cap 80): 1

## Padrão: `aliasResolver`

```
flutter_app/lib\services\debug_church_audit_service.dart:116:    'aliasResolver',
```
Total linhas (cap 80): 1

## Padrão: `canonicalTenant`

```
functions/src\churchCanonicalResolve.ts:27:      for (const k of ["canonicalTenantId", "igrejaId", "churchId", "tenantId"]) {
functions/src\churchTenantProvisioning.ts:101:  if (!str(d["canonicalTenantId"])) patch.canonicalTenantId = canonical;
functions/src\churchTenantProvisioning.ts:116:    patch.canonicalTenantId = BPC_CANONICAL_IGREJA_ID;
functions/src\consolidateBpcCluster.ts:101:    canonicalTenantId: canonical,
functions/src\consolidateBpcCluster.ts:299:          canonicalTenantId: canonical,
functions/src\consolidateBpcCluster.ts:632:    canonicalTenantId: canonical,
flutter_app/lib\services\debug_church_audit_service.dart:117:    'canonicalTenant',
```
Total linhas (cap 80): 7

## Padrão: `operationalTenant`

```
flutter_app/lib\ui\igreja_clean_shell.dart:179:  String? _operationalTenantId;
flutter_app/lib\ui\igreja_clean_shell.dart:188:    final op = _operationalTenantId?.trim() ?? '';
flutter_app/lib\ui\igreja_clean_shell.dart:463:      final changed = effective != (_operationalTenantId ?? '').trim();
flutter_app/lib\ui\igreja_clean_shell.dart:464:      if (changed || _operationalTenantId == null) {
flutter_app/lib\ui\igreja_clean_shell.dart:466:          _operationalTenantId = effective;
flutter_app/lib\ui\igreja_clean_shell.dart:481:      if (_operationalTenantId == null || _operationalTenantId!.trim().isEmpty) {
flutter_app/lib\ui\igreja_clean_shell.dart:485:        setState(() => _operationalTenantId = fallback);
flutter_app/lib\ui\igreja_clean_shell.dart:509:      _operationalTenantId = null;
flutter_app/lib\ui\widgets\church_payment_receiving_settings_section.dart:37:  String? _operationalTenantId;
flutter_app/lib\ui\widgets\church_payment_receiving_settings_section.dart:40:    final op = (_operationalTenantId ?? widget.tenantId).trim();
flutter_app/lib\ui\widgets\church_payment_receiving_settings_section.dart:54:    _operationalTenantId = await TenantResolverService
flutter_app/lib\services\church_cluster_sync_service.dart:14:    String operationalTenantId, {
flutter_app/lib\services\church_cluster_sync_service.dart:17:    final tid = operationalTenantId.trim();
flutter_app/lib\services\church_chat_uploads_service.dart:21:  static CollectionReference<Map<String, dynamic>> _col(String operationalTenantId) =>
flutter_app/lib\services\church_chat_uploads_service.dart:22:      ChurchOperationalPaths.churchDoc(operationalTenantId.trim())
flutter_app/lib\ui\widgets\instagram_mural.dart:3693:  String? _operationalTenantId;
flutter_app/lib\ui\widgets\instagram_mural.dart:3708:    _operationalTenantId = widget.resolvedTenantId.trim();
flutter_app/lib\ui\widgets\instagram_mural.dart:3781:      setState(() => _operationalTenantId = tid.trim());
flutter_app/lib\ui\widgets\instagram_mural.dart:3786:      (_operationalTenantId ?? widget.resolvedTenantId).trim();
flutter_app/lib\ui\widgets\instagram_mural.dart:3807:    if (mounted) setState(() => _operationalTenantId = igrejaId);
flutter_app/lib\ui\widgets\instagram_mural.dart:3823:    if (mounted) setState(() => _operationalTenantId = igrejaId);
flutter_app/lib\ui\widgets\instagram_mural.dart:3937:          _operationalTenantId = bundle.firestoreTenantId;
flutter_app/lib\services\church_member_contact_chat.dart:91:        operational = await ChurchTenantResilientReads.operationalTenantId(tid);
flutter_app/lib\services\church_member_contact_chat.dart:222:        operational = await ChurchTenantResilientReads.operationalTenantId(tid);
flutter_app/lib\services\church_member_contact_chat.dart:270:    var operationalTenant = tenantId.trim();
flutter_app/lib\services\church_member_contact_chat.dart:272:      operationalTenant = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\services\church_member_contact_chat.dart:279:      tenantId: operationalTenant,
flutter_app/lib\services\church_member_contact_chat.dart:318:      tenantId: operationalTenant,
flutter_app/lib\services\church_member_contact_chat.dart:344:              tenantId: operationalTenant,
flutter_app/lib\ui\widgets\mercado_pago_church_settings_section.dart:42:  String? _operationalTenantId;
flutter_app/lib\ui\widgets\mercado_pago_church_settings_section.dart:45:    final op = (_operationalTenantId ?? widget.tenantId).trim();
flutter_app/lib\ui\widgets\mercado_pago_church_settings_section.dart:67:        _operationalTenantId = await TenantResolverService
flutter_app/lib\ui\pages\church_donations_page.dart:130:  String? _operationalTenantId;
flutter_app/lib\ui\pages\church_donations_page.dart:146:      (_operationalTenantId ?? widget.tenantId).trim();
flutter_app/lib\ui\pages\church_donations_page.dart:157:      _operationalTenantId = seed;
flutter_app/lib\ui\pages\church_donations_page.dart:184:      final resolved = await ChurchTenantResilientReads.operationalTenantId(
flutter_app/lib\ui\pages\church_donations_page.dart:189:        setState(() => _operationalTenantId = resolved.trim());
flutter_app/lib\ui\pages\dashboard_page.dart:57:  String? _operationalTenantId;
flutter_app/lib\ui\pages\dashboard_page.dart:60:      (_operationalTenantId ?? widget.tenantId).trim();
flutter_app/lib\ui\pages\dashboard_page.dart:70:          setState(() => _operationalTenantId = op);
flutter_app/lib\services\church_tenant_resilient_reads.dart:60:          operational = await operationalTenantId(seed, userUid: userUid);
flutter_app/lib\services\church_tenant_resilient_reads.dart:62:          operational = await operationalTenantId(seed, userUid: userUid);
flutter_app/lib\services\church_tenant_resilient_reads.dart:102:  static Future<String> operationalTenantId(
flutter_app/lib\services\debug_church_audit_service.dart:118:    'operationalTenant',
flutter_app/lib\ui\pages\configuracoes_page.dart:86:  String? _operationalTenantId;
flutter_app/lib\ui\pages\configuracoes_page.dart:91:      (_operationalTenantId ?? widget.tenantId).trim();
flutter_app/lib\ui\pages\configuracoes_page.dart:128:      if (op.isNotEmpty) _operationalTenantId = op;
flutter_app/lib\ui\pages\configuracoes_page.dart:1550:      setState(() => _operationalTenantId = op);
flutter_app/lib\ui\pages\completar_cadastro_membro_page.dart:59:  String? _operationalTenantId;
flutter_app/lib\ui\pages\completar_cadastro_membro_page.dart:62:      (_operationalTenantId ?? widget.tenantId).trim();
flutter_app/lib\ui\pages\completar_cadastro_membro_page.dart:74:      if (mounted) setState(() => _operationalTenantId = op);
flutter_app/lib\ui\pages\events_manager_page.dart:2467:  Future<String> _operationalTenantId() =>
flutter_app/lib\ui\pages\events_manager_page.dart:2511:      final tid = await _operationalTenantId();
flutter_app/lib\ui\pages\events_manager_page.dart:6182:  String? _operationalTenantId;
flutter_app/lib\ui\pages\events_manager_page.dart:6185:      (_operationalTenantId ?? widget.resolvedTenantId).trim();
flutter_app/lib\ui\pages\events_manager_page.dart:6288:          _operationalTenantId = bundle.firestoreTenantId;
flutter_app/lib\ui\pages\events_manager_page.dart:6439:    if (mounted) setState(() => _operationalTenantId = igrejaId);
flutter_app/lib\ui\pages\events_manager_page.dart:6484:    _operationalTenantId = widget.resolvedTenantId.trim();
flutter_app/lib\ui\pages\events_manager_page.dart:6595:        setState(() => _operationalTenantId = tid.trim());
flutter_app/lib\ui\pages\internal_new_member_page.dart:60:  String? _operationalTenantId;
flutter_app/lib\ui\pages\internal_new_member_page.dart:63:      (_operationalTenantId ?? widget.tenantId).trim();
flutter_app/lib\ui\pages\internal_new_member_page.dart:129:      if (mounted) _operationalTenantId = op;
flutter_app/lib\ui\pages\igreja_cadastro_page.dart:228:  String? _operationalTenantId;
flutter_app/lib\ui\pages\igreja_cadastro_page.dart:344:    _operationalTenantId = resolved;
flutter_app/lib\ui\pages\igreja_cadastro_page.dart:567:    _operationalTenantId = null;
flutter_app/lib\ui\pages\igreja_cadastro_page.dart:1853:    final resolvedId = (_operationalTenantId ?? widget.tenantId).trim();
flutter_app/lib\ui\pages\igreja_cadastro_page.dart:1901:    final cached = (_operationalTenantId ?? '').trim();
flutter_app/lib\ui\pages\igreja_cadastro_page.dart:2136:          : (_operationalTenantId ?? _hydratedTenantId ?? '').trim();
flutter_app/lib\ui\pages\igreja_cadastro_page.dart:2714:        (_operationalTenantId ?? '').trim().isEmpty) {
flutter_app/lib\ui\pages\igreja_cadastro_page.dart:2726:    final resolvedId = (_operationalTenantId ?? widget.tenantId).trim().isEmpty
flutter_app/lib\ui\pages\igreja_cadastro_page.dart:2728:        : (_operationalTenantId ?? widget.tenantId).trim();
flutter_app/lib\ui\pages\usuarios_permissoes_page.dart:40:  String? _operationalTenantId;
flutter_app/lib\ui\pages\usuarios_permissoes_page.dart:46:      (_operationalTenantId ?? widget.tenantId).trim();
flutter_app/lib\ui\pages\usuarios_permissoes_page.dart:60:      _operationalTenantId = op;
flutter_app/lib\ui\pages\patrimonio_page.dart:784:  String? _operationalTenantId;
flutter_app/lib\ui\pages\patrimonio_page.dart:788:    final op = _operationalTenantId?.trim() ?? '';
flutter_app/lib\ui\pages\patrimonio_page.dart:921:      if (!mounted || tid == _operationalTenantId) return;
flutter_app/lib\ui\pages\patrimonio_page.dart:922:      setState(() => _operationalTenantId = tid);
flutter_app/lib\ui\pages\patrimonio_page.dart:947:      setState(() => _operationalTenantId = null);
flutter_app/lib\ui\pages\relatorios_page.dart:560:  String? _operationalTenantId;
```
Total linhas (cap 80): 105

## Padrão: `syncStorageTenantId`

```
flutter_app/lib\services\church_tenant_media_service.dart:242:        TenantResolverService.syncStorageTenantId(pathChurchId);
flutter_app/lib\services\debug_church_audit_service.dart:120:    'syncStorageTenantId',
flutter_app/lib\services\tenant_resolver_service.dart:74:  static String syncStorageTenantId(String seedId) {
```
Total linhas (cap 80): 3

## Padrão: `resolveOperationalChurchDocId`

```
flutter_app/lib\ui\igreja_painel_page.dart:192:      final op = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\ui\busca_global_widget.dart:41:      final tid = await TenantResolverService.resolveOperationalChurchDocId(hint);
flutter_app/lib\ui\igreja_clean_shell.dart:545:          await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\ui\pages\aprovar_membros_pendentes_page.dart:127:      final op = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\ui\pages\church_chat_thread_page.dart:239:      final tid = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\ui\pages\church_chat_thread_page.dart:304:      final tid = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\ui\pages\calendar_page.dart:854:      final op = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\ui\widgets\church_global_search_dialog.dart:179:      final op = await TenantResolverService.resolveOperationalChurchDocId(tid);
flutter_app/lib\ui\pages\igreja_dashboard_moderno.dart:3072:          await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\ui\pages\igreja_dashboard_moderno.dart:6874:    tid = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\ui\widgets\church_payment_receiving_settings_section.dart:55:        .resolveOperationalChurchDocId(seed, userUid: uid)
flutter_app/lib\ui\widgets\instagram_mural.dart:367:      final tid = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\ui\widgets\instagram_mural.dart:3776:      final tid = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\ui\pages\public_member_signup_page.dart:410:      operational = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\ui\pages\my_schedules_page.dart:955:        tid = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\ui\widgets\mercado_pago_church_settings_section.dart:68:            .resolveOperationalChurchDocId(
flutter_app/lib\services\church_tenant_resilient_reads.dart:131:        await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\services\church_tenant_resilient_reads.dart:190:        await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\services\church_tenant_resilient_reads.dart:360:    final tid = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\services\church_tenant_offline_warmup_service.dart:87:        final r = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\services\church_tenant_media_service.dart:105:    final churchId = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\services\church_cluster_sync_service.dart:36:      operational = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\services\church_member_contact_chat.dart:272:      operationalTenant = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\services\fcm_service.dart:53:      final op = await TenantResolverService.resolveOperationalChurchDocId(
flutter_app/lib\services\multi_tenant_diagnostic_service.dart:204:      final canonical = await TenantResolverService.resolveOperationalChurchDocId(seed);
flutter_app/lib\services\multi_tenant_diagnostic_service.dart:242:        await TenantResolverService.resolveOperationalChurchDocId(seed, userUid: uid),
flutter_app/lib\services\tenant_resolver_service.dart:111:    final operational = await resolveOperationalChurchDocId(
flutter_app/lib\services\tenant_resolver_service.dart:266:    final canonical = await resolveOperationalChurchDocId(
flutter_app/lib\services\tenant_resolver_service.dart:388:    return resolveOperationalChurchDocId(
flutter_app/lib\services\tenant_resolver_service.dart:546:  static Future<String> resolveOperationalChurchDocId(
flutter_app/lib\services\tenant_resolver_service.dart:587:      origin: 'TenantResolverService.resolveOperationalChurchDocId',
flutter_app/lib\services\tenant_resolver_service.dart:880:    final operational = await resolveOperationalChurchDocId(
```
Total linhas (cap 80): 32

