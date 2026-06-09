import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gestao_yahweh/services/church_module_firestore_audit.dart';
import 'package:gestao_yahweh/services/debug_church_audit_service.dart';
import 'package:gestao_yahweh/ui/theme_clean_premium.dart';
import 'package:gestao_yahweh/ui/widgets/church_panel_ui_helpers.dart';

/// Tela temporária DEBUG CHURCH — prova Web = Android = iOS.
class DebugChurchPage extends StatefulWidget {
  const DebugChurchPage({
    super.key,
    required this.tenantId,
  });

  final String tenantId;

  @override
  State<DebugChurchPage> createState() => _DebugChurchPageState();
}

class _DebugChurchPageState extends State<DebugChurchPage> {
  DebugChurchAuditSnapshot? _snap;
  DebugChurchCrossPlatformProof? _crossProof;
  bool _loading = true;
  bool _publishing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await DebugChurchAuditService.runFullAudit(widget.tenantId)
          .timeout(const Duration(seconds: 12));
      final churchId = snap.churchId;
      final byPlatform = await DebugChurchAuditService.loadCrossPlatformProof(churchId);
      byPlatform[snap.platform] = snap;
      final cross = DebugChurchAuditService.buildCrossPlatformProof(churchId, byPlatform);
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _crossProof = cross;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _copyReport() async {
    final s = _snap;
    if (s == null) return;
    await Clipboard.setData(ClipboardData(text: s.toClipboardText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.successSnackBar('Relatório desta plataforma copiado.'),
    );
  }

  Future<void> _copyAcceptanceReport() async {
    final proof = _crossProof;
    if (proof == null) return;
    await Clipboard.setData(ClipboardData(text: proof.toAcceptanceReportTable()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.successSnackBar(
        'Relatório de aceite copiado — obrigatório para encerrar tarefa.',
      ),
    );
  }

  Future<void> _copyMandatoryProof() async {
    final proof = _crossProof;
    if (proof == null) return;
    await Clipboard.setData(ClipboardData(text: proof.toMandatoryProveText()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ThemeCleanPremium.successSnackBar(
        'Prova obrigatória copiada — cole no Cursor (WEB=ANDROID=IOS).',
      ),
    );
  }

  Future<void> _publishProof() async {
    final s = _snap;
    if (s == null || _publishing) return;
    setState(() => _publishing = true);
    try {
      await DebugChurchAuditService.publishPlatformProof(s);
      final byPlatform = await DebugChurchAuditService.loadCrossPlatformProof(s.churchId);
      final cross = DebugChurchAuditService.buildCrossPlatformProof(s.churchId, byPlatform);
      if (!mounted) return;
      setState(() {
        _crossProof = cross;
        _publishing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        ThemeCleanPremium.successSnackBar(
          'Prova ${s.platform} publicada — abra DEBUG CHURCH nas outras plataformas.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _publishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Falha ao publicar prova: $e'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Color _verdictColor(String v) =>
      v == 'APROVADO' ? const Color(0xFF16A34A) : const Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ThemeCleanPremium.surface,
      appBar: AppBar(
        title: const Text('DEBUG CHURCH'),
        actions: [
          IconButton(
            tooltip: 'Copiar relatório de aceite (tabela final)',
            onPressed: _crossProof == null ? null : _copyAcceptanceReport,
            icon: const Icon(Icons.table_chart_rounded),
          ),
          IconButton(
            tooltip: 'Copiar prova obrigatória (WEB=ANDROID=IOS)',
            onPressed: _crossProof == null ? null : _copyMandatoryProof,
            icon: const Icon(Icons.fact_check_rounded),
          ),
          IconButton(
            tooltip: 'Copiar relatório desta plataforma',
            onPressed: _snap == null ? null : _copyReport,
            icon: const Icon(Icons.copy_all_rounded),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _loading ? null : _run,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ChurchPanelErrorBody(
                  title: 'Falha na auditoria DEBUG CHURCH',
                  error: _error,
                  onRetry: _run,
                )
              : _buildBody(context, _snap!),
    );
  }

  Widget _buildBody(BuildContext context, DebugChurchAuditSnapshot s) {
    final verdict = s.verdict;
    final cross = _crossProof;
    return ListView(
      padding: ThemeCleanPremium.pagePadding(context),
      children: [
        _banner(verdict, s),
        if (cross != null) ...[
          const SizedBox(height: 12),
          _crossPlatformSection(context, cross),
        ],
        const SizedBox(height: 16),
        _section('Identidade', [
          _row('PLATAFORMA', s.platform),
          _row('churchId', s.churchId),
          _row('Firestore Path', s.firestorePath),
          _row('Storage Path', s.storagePath),
          _row('Seed hint', s.seedHint),
          _row('Context bound', s.contextBound ? 'SIM' : 'NÃO'),
          _row('Capturado em', s.capturedAt.toIso8601String()),
        ]),
        _section('Cadastro Igreja', [
          _row('Nome Igreja', s.nome ?? '-'),
          _row('Cidade', s.cidade ?? '-'),
          _row('Estado', s.estado ?? '-'),
          _row('Telefone', s.telefone ?? '-'),
          _row('Email', s.email ?? '-'),
          _row('LogoPath', s.logoPath ?? '-'),
          _row('Campos doc', '${s.churchFieldCount}'),
        ]),
        _section('Contagens (consulta real)', [
          _row('Departamentos', '${s.countFor('Departamentos') ?? "-"}'),
          _row('Cargos', '${s.countFor('Cargos') ?? "-"}'),
          _row('Membros', '${s.countFor('Membros') ?? "-"}'),
          _row('Eventos (noticias)', '${s.countFor('Eventos') ?? "-"}'),
          _row('Avisos', '${s.countFor('Avisos') ?? "-"}'),
          _row('Fornecedores', '${s.countFor('Fornecedores') ?? "-"}'),
          _row('Lançamentos Financeiros', '${s.countFor('Financeiro') ?? "-"}'),
          _row('Chat threads', '${s.countFor('Chat') ?? "-"}'),
          _row('Patrimônio', '${s.countFor('Patrimônio') ?? "-"}'),
        ]),
        _section('PATH por módulo (console: MODULO / churchId / PATH)', [
          for (final p in s.probes) _probeTile(p),
        ]),
        if (s.legacyHitsInLogs.isNotEmpty)
          _section('LEGADO DETECTADO NOS LOGS — REPROVADO', [
            for (final l in s.legacyHitsInLogs)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(l, style: const TextStyle(color: Color(0xFFDC2626))),
              ),
          ]),
        const SizedBox(height: 12),
        Text(
          '1) Toque Publicar prova nesta plataforma. '
          '2) Repita em Web, Android e iOS. '
          '3) Copie a prova obrigatória e cole no Cursor. '
          'PATH diferente entre plataformas = REPROVADO.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _crossPlatformSection(BuildContext context, DebugChurchCrossPlatformProof proof) {
    final color = _verdictColor(
      proof.verdict == 'APROVADO' ? 'APROVADO' : 'REPROVADO',
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: ThemeCleanPremium.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Prova obrigatória — ${proof.verdict}',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(height: 8),
          for (final key in DebugChurchAuditService.platformKeys)
            _row(
              key,
              proof.byPlatform[key] == null
                  ? '(ausente — publicar nesta plataforma)'
                  : '${proof.byPlatform[key]!.capturedAt.toIso8601String()}',
            ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _publishing ? null : _publishProof,
              icon: _publishing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_upload_rounded),
              label: Text(_publishing ? 'Publicando…' : 'Publicar prova ${_snap?.platform ?? ""}'),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _copyAcceptanceReport,
            icon: const Icon(Icons.table_chart_outlined),
            label: const Text('Copiar relatório de aceite (tabela final)'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _copyMandatoryProof,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Copiar prova PATH (WEB:… ANDROID:… IOS:…)'),
          ),
          const SizedBox(height: 12),
          for (final row in proof.moduleRows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row.label} — MATCH: ${row.match ? "SIM" : "NÃO"}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: row.match ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    ),
                  ),
                  SelectableText('WEB:${row.webPath}', style: const TextStyle(fontSize: 12)),
                  SelectableText('ANDROID:${row.androidPath}', style: const TextStyle(fontSize: 12)),
                  SelectableText('IOS:${row.iosPath}', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _banner(String verdict, DebugChurchAuditSnapshot s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _verdictColor(verdict).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _verdictColor(verdict).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            verdict,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _verdictColor(verdict),
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            'igrejas/${s.churchId}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _probeTile(ChurchModuleProbeResult p) {
    final ok = p.ok && !p.usedLegacyPath && p.error == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ok ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p.module,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          SelectableText('PATH: ${p.collectionPath}', style: const TextStyle(fontSize: 12)),
          Text(
            'count=${p.count ?? "-"} | ${p.durationMs ?? 0}ms | ok=$ok',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          if (p.error != null)
            Text(p.error!, style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626))),
        ],
      ),
    );
  }
}
