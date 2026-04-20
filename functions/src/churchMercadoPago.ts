/**
 * Mercado Pago por igreja: dízimos/ofertas via PIX, credenciais em `igrejas/{tid}/private/mp_credentials`.
 * Ponte do webhook: `igrejas/{tid}/mp_payment_bridge/{paymentId}` (collection group + fallback legado `church_mp_payments`).
 * Checkout Pro: `igrejas/{tid}/mp_preference_bridge/{preferenceId}` (+ fallback `church_mp_preferences`).
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

/** Lazy: index.ts chama `initializeApp()` depois de resolver imports; top-level `firestore()` quebrava o analisador do deploy. */
function fs() {
  return admin.firestore();
}

/** Descobre tenant pela ponte PIX (subcoleção por igreja ou legado na raiz). */
async function resolveTenantFromPaymentBridge(paymentId: string): Promise<string | null> {
  const loaded = await loadPaymentBridge(paymentId);
  return loaded?.tenantId || null;
}

/**
 * Ponte PIX: ao criar o pagamento guardamos `donationKind` aqui — o webhook do MP
 * muitas vezes **não** devolve `metadata.donationKind` no objeto payment; sem isto tudo virava "Dízimo".
 */
async function loadPaymentBridge(paymentId: string): Promise<{
  tenantId: string;
  pd: Record<string, unknown>;
} | null> {
  const pid = String(paymentId || "").trim();
  if (!pid) return null;
  try {
    const cg = await fs()
      .collectionGroup("mp_payment_bridge")
      .where(admin.firestore.FieldPath.documentId(), "==", pid)
      .limit(1)
      .get();
    if (!cg.empty) {
      const doc = cg.docs[0];
      const tid = String(doc.ref.parent.parent?.id || "").trim();
      if (tid) {
        return { tenantId: tid, pd: (doc.data() || {}) as Record<string, unknown> };
      }
    }
  } catch (e) {
    console.warn("loadPaymentBridge collectionGroup", e);
  }
  const legacy = await fs().collection("church_mp_payments").doc(pid).get();
  if (!legacy.exists) return null;
  const d = legacy.data() || {};
  const tenantId = String(d.tenantId || "").trim();
  if (!tenantId) return null;
  return { tenantId, pd: d as Record<string, unknown> };
}

/** Preferência Checkout Pro: dados + tenant (path ou legado). */
async function loadPreferenceBridge(prefId: string): Promise<{
  tenantId: string;
  pd: Record<string, unknown>;
} | null> {
  const id = String(prefId || "").trim();
  if (!id) return null;
  try {
    const cg = await fs()
      .collectionGroup("mp_preference_bridge")
      .where(admin.firestore.FieldPath.documentId(), "==", id)
      .limit(1)
      .get();
    if (!cg.empty) {
      const doc = cg.docs[0];
      const tid = String(doc.ref.parent.parent?.id || "").trim();
      if (tid) {
        return { tenantId: tid, pd: (doc.data() || {}) as Record<string, unknown> };
      }
    }
  } catch (e) {
    console.warn("loadPreferenceBridge collectionGroup", e);
  }
  const legacy = await fs().collection("church_mp_preferences").doc(id).get();
  if (!legacy.exists) return null;
  const d = legacy.data() || {};
  const tenantId = String(d.tenantId || "").trim();
  if (!tenantId) return null;
  return { tenantId, pd: d as Record<string, unknown> };
}

function getFetch(): (input: string, init?: any) => Promise<any> {
  const f = (globalThis as any).fetch;
  if (!f) throw new Error("fetch nao disponivel");
  return f;
}

async function resolveRoleFromTokenOrDb(uid: string, tokenRole: unknown): Promise<string> {
  const tokenNormalized = String(tokenRole || "").trim().toUpperCase();
  if (tokenNormalized) return tokenNormalized;
  try {
    const userDoc = await fs().collection("users").doc(uid).get();
    const data = userDoc.exists ? userDoc.data() || {} : {};
    return String(data.role ?? data.nivel ?? data.perfil ?? data.NIVEL ?? "").trim().toUpperCase();
  } catch {
    return "";
  }
}

function isPrivilegedRole(role: string): boolean {
  return ["MASTER", "ADMIN", "ADM"].includes(role);
}

function isChurchManagerRole(role: string): boolean {
  return ["MASTER", "ADMIN", "ADM", "GESTOR"].includes(role);
}

async function canManageTenant(
  uid: string,
  tokenRole: unknown,
  tokenTenantId: unknown,
  tenantId: string
): Promise<boolean> {
  const role = await resolveRoleFromTokenOrDb(uid, tokenRole);
  if (isPrivilegedRole(role)) return true;
  if (!isChurchManagerRole(role)) return false;
  const tokenTenant = String(tokenTenantId || "").trim();
  if (tokenTenant && tokenTenant === tenantId) return true;
  try {
    const u = await fs().collection("users").doc(uid).get();
    const data = u.exists ? u.data() || {} : {};
    const userTenant = String(data.tenantId || data.igrejaId || "").trim();
    if (userTenant && userTenant === tenantId) return true;
  } catch {
    /* ignore */
  }
  return false;
}

export async function getChurchMpAccessToken(tenantId: string): Promise<string | null> {
  const snap = await fs().collection("igrejas").doc(tenantId).collection("private").doc("mp_credentials").get();
  if (!snap.exists) return null;
  const d = snap.data() || {};
  const out = String(d.accessToken || "").trim();
  return out || null;
}

function mpWebhookUrl(): string {
  const projectId = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "";
  if (!projectId) return "";
  return `https://us-central1-${projectId}.cloudfunctions.net/mpWebhook`;
}

/** Permite ao webhook buscar o pagamento com o token da igreja (GET /payments exige o seller). */
function appendTenantToNotificationUrl(url: string, tenantId: string): string {
  const u = url.trim();
  if (!u || !tenantId) return u;
  const sep = u.includes("?") ? "&" : "?";
  return `${u}${sep}tenantId=${encodeURIComponent(tenantId)}`;
}

/** Líquido recebido na conta MP + taxas (fallback se a API não enviar net_received_amount). */
function computeMpNetAmounts(payment: any): { gross: number; net: number; fee: number } {
  const gross = Number(payment?.transaction_amount ?? 0);
  const td = payment?.transaction_details || {};
  let net = Number(td.net_received_amount);
  const feeDetails = Array.isArray(payment?.fee_details) ? payment.fee_details : [];
  let feesSum = 0;
  for (const f of feeDetails) {
    feesSum += Math.abs(Number((f as any)?.amount ?? 0));
  }
  if (!Number.isFinite(net) || net < 0) {
    net = Number(td.total_paid_amount);
  }
  if (!Number.isFinite(net) || net < 0) {
    net = gross;
  }
  if (feesSum > 0 && (net >= gross - 1e-6 || !Number.isFinite(Number(td.net_received_amount)))) {
    net = Math.max(0, gross - feesSum);
  }
  const fee = feesSum > 0 ? feesSum : Math.max(0, gross - net);
  return { gross, net, fee };
}

/** Nome para exibição: metadata (preferência/PIX), payer MP, descrição «Doação — Nome», additional_info. */
function resolveDonorDisplayName(payment: any, meta: Record<string, any>): string {
  const fromMeta = String(
    meta?.donorName ??
      meta?.donor_full_name ??
      meta?.donorFullName ??
      meta?.full_name ??
      meta?.payer_name ??
      ""
  ).trim();
  if (fromMeta && fromMeta.toLowerCase() !== "doador") return fromMeta.slice(0, 160);

  const payer = payment?.payer || {};
  const fn = String(payer.first_name ?? "").trim();
  const ln = String(payer.last_name ?? "").trim();
  const combined = `${fn} ${ln}`.trim();
  if (combined) return combined.slice(0, 160);

  const name = String(payer.name ?? "").trim();
  if (name) return name.slice(0, 160);

  const desc = String(payment?.description ?? "").trim();
  const dm =
    desc.match(/Doa[cç][aã]o\s*[—\-]\s*(.+)/i) || desc.match(/Doação\s*[—\-]\s*(.+)/i);
  if (dm?.[1]) {
    const t = dm[1].trim();
    if (t && t.toLowerCase() !== "doador") return t.slice(0, 160);
  }

  const add = payment?.additional_info;
  if (add && typeof add === "object") {
    const pAdd = (add as Record<string, unknown>).payer;
    if (pAdd && typeof pAdd === "object") {
      const pa = pAdd as Record<string, unknown>;
      const f2 = String(pa.first_name ?? "").trim();
      const l2 = String(pa.last_name ?? "").trim();
      const c2 = `${f2} ${l2}`.trim();
      if (c2) return c2.slice(0, 160);
      const n2 = String(pa.name ?? "").trim();
      if (n2) return n2.slice(0, 160);
    }
  }

  const email = String(payer.email ?? "").trim();
  if (email.includes("@")) {
    const local = (email.split("@")[0] ?? "").trim();
    if (local && !/^doacao\+/i.test(local)) return local.slice(0, 160);
  }

  return fromMeta || "Doador";
}

/** PIX / Checkout: `dizimo` | `oferta` (sem valor: dízimo — compatível com fluxo antigo). */
function normalizeDonationKind(raw: unknown): "dizimo" | "oferta" {
  const s = String(raw || "")
    .trim()
    .toLowerCase();
  if (s === "dizimo" || s === "dízimo" || s === "diezmo") return "dizimo";
  if (
    s === "oferta" ||
    s === "offer" ||
    s === "oferta_voluntaria" ||
    s === "oferta voluntária" ||
    s === "oferta_missionaria" ||
    s === "oferta missionaria" ||
    s === "oferta missionária"
  ) {
    return "oferta";
  }
  return "dizimo";
}

/** Categoria no módulo Financeiro — alinhado a `_categoriasReceitaPadrao` no app. */
function categoriaForDonationKind(kind: "dizimo" | "oferta"): string {
  return kind === "dizimo" ? "Dízimos" : "Oferta Missionária";
}

function labelForDonationKind(kind: "dizimo" | "oferta"): string {
  return kind === "dizimo" ? "Dízimo" : "Oferta Missionária";
}

/** Nome completo do cadastro de membro (extrato / conciliação). */
async function resolveMemberFullNameForDonation(
  tenantId: string,
  memberId: string
): Promise<string> {
  const mid = String(memberId || "").trim();
  if (!mid) return "";
  try {
    const snap = await fs()
      .collection("igrejas")
      .doc(tenantId)
      .collection("membros")
      .doc(mid)
      .get();
    if (!snap.exists) return "";
    const d = snap.data() || {};
    const nome = String(
      d.NOME_COMPLETO || d.NOME || d.nome || d.name || ""
    )
      .trim()
      .replace(/\s+/g, " ");
    return nome.slice(0, 200);
  } catch {
    return "";
  }
}

async function resolveDefaultMercadoPagoContaId(tenantId: string): Promise<string> {
  try {
    const col = fs().collection("igrejas").doc(tenantId).collection("contas");
    const fixed = await col.doc("mercado_pago").get();
    if (fixed.exists) {
      const fd = fixed.data() || {};
      if (fd.ativo !== false) return fixed.id;
    }
    const snap = await col.limit(120).get();
    for (const d of snap.docs) {
      const data = d.data() || {};
      if (data.ativo === false) continue;
      const cod = String(data.bancoCodigo || "").trim();
      if (cod === "323") return d.id;
      const bn = String(data.bancoNome || "").toLowerCase();
      if (bn.includes("mercado pago")) return d.id;
      if (String(data.seedPreset || "") === "tesouraria_mercado_pago") return d.id;
      const nome = String(data.nome || "").toLowerCase();
      if (nome.includes("mercado pago")) return d.id;
    }
  } catch {
    /* ignore */
  }
  return "";
}

/**
 * Nova igreja: cria `igrejas/{tid}/contas/mercado_pago` (banco 323) para conciliar PIX/cartão.
 * Idempotente. O gestor configura credenciais depois em Configurações.
 */
export async function ensureMercadoPagoContaForNewChurch(tenantId: string): Promise<boolean> {
  const tid = String(tenantId || "").trim();
  if (!tid) return false;
  const col = fs().collection("igrejas").doc(tid).collection("contas");
  const existingId = await resolveDefaultMercadoPagoContaId(tid);
  if (existingId) return false;
  const q = await col.where("seedPreset", "==", "tesouraria_mercado_pago").limit(1).get();
  if (!q.empty) return false;
  await col.doc("mercado_pago").set(
    {
      nome: "Mercado Pago",
      bancoCodigo: "323",
      bancoNome: "Mercado Pago",
      agencia: "",
      numeroConta: "",
      tipoConta: "corrente",
      observacao:
        "Recebimentos via integração Mercado Pago (PIX/cartão). Configure o Access Token em Configurações → Contribuições / Mercado Pago.",
      ativo: true,
      seedPreset: "tesouraria_mercado_pago",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return true;
}

/** Contas de tesouraria sugeridas (sem agência/conta — o gestor completa). Idempotente por [docId]. */
const TREASURY_SEED_CONTAS: ReadonlyArray<{
  docId: string;
  nome: string;
  bancoCodigo: string;
  bancoNome: string;
  tipoConta: string;
  seedPreset: string;
  observacao: string;
}> = [
  {
    docId: "banco_do_brasil",
    nome: "Banco do Brasil",
    bancoCodigo: "001",
    bancoNome: "Banco do Brasil",
    tipoConta: "corrente",
    seedPreset: "tesouraria_bb",
    observacao: "Conta sugerida. Preencha agência e número em Financeiro → Contas.",
  },
  {
    docId: "nubank",
    nome: "Nubank",
    bancoCodigo: "260",
    bancoNome: "Nubank",
    tipoConta: "corrente",
    seedPreset: "tesouraria_nubank",
    observacao: "Conta sugerida. Ajuste dados reais em Financeiro → Contas.",
  },
  {
    docId: "caixa_economica",
    nome: "Caixa Econômica Federal",
    bancoCodigo: "104",
    bancoNome: "Caixa Econômica Federal",
    tipoConta: "corrente",
    seedPreset: "tesouraria_caixa",
    observacao: "Conta sugerida. Preencha agência e operação em Financeiro → Contas.",
  },
  {
    docId: "caixa_numerario",
    nome: "Caixa / numerário (dinheiro físico)",
    bancoCodigo: "",
    bancoNome: "",
    tipoConta: "caixa",
    seedPreset: "tesouraria_numerario",
    observacao: "Movimentos em espécie na igreja. Use para conciliar cofre e arrecadações.",
  },
];

/**
 * Cria contas-padrão (BB, Nubank, Caixa, numerário) se o documento ainda não existir.
 * Mercado Pago: use [ensureMercadoPagoContaForNewChurch] antes ou depois (ids distintos).
 * Devolve quantidade de documentos criados nesta chamada.
 */
export async function ensureDefaultTreasuryContasForNewChurch(tenantId: string): Promise<number> {
  const tid = String(tenantId || "").trim();
  if (!tid) return 0;
  const col = fs().collection("igrejas").doc(tid).collection("contas");
  const batch = fs().batch();
  let n = 0;
  for (const row of TREASURY_SEED_CONTAS) {
    const ref = col.doc(row.docId);
    const snap = await ref.get();
    if (snap.exists) continue;
    batch.set(ref, {
      nome: row.nome,
      bancoCodigo: row.bancoCodigo,
      bancoNome: row.bancoNome,
      agencia: "",
      numeroConta: "",
      tipoConta: row.tipoConta,
      observacao: row.observacao,
      ativo: true,
      seedPreset: row.seedPreset,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    n++;
  }
  if (n > 0) await batch.commit();
  return n;
}

async function mpGetWithToken(accessToken: string, path: string): Promise<any> {
  const res = await getFetch()(`https://api.mercadopago.com${path}`, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`MP API error: ${res.status} ${text}`);
  }
  return res.json() as any;
}

async function mpPostWithToken(
  accessToken: string,
  path: string,
  body: any,
  extraHeaders?: Record<string, string>
): Promise<any> {
  const res = await getFetch()(`https://api.mercadopago.com${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
      ...extraHeaders,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`MP API error: ${res.status} ${text}`);
  }
  return res.json() as any;
}

/** Chamado pelo webhook depois de obter o objeto payment (token correto). */
export async function tryHandleChurchDonationPayment(payment: any): Promise<boolean> {
  const pid = String(payment?.id || "");
  const meta: Record<string, any> = { ...(payment?.metadata || {}) };
  let tenantId = String(meta.tenantId || payment.external_reference || "").trim();

  let isChurch = String(meta.kind || "").toLowerCase() === "church_donation";

  /** Checkout Pro: preference em `mp_preference_bridge` ou legado `church_mp_preferences`. */
  if (!isChurch) {
    const prefId = String(payment?.preference_id || meta.preference_id || "").trim();
    if (prefId) {
      const loaded = await loadPreferenceBridge(prefId);
      if (loaded) {
        isChurch = true;
        if (loaded.tenantId) tenantId = tenantId || loaded.tenantId;
        const pd = loaded.pd;
        if (!meta.donorName && pd.donorName) meta.donorName = pd.donorName;
        if (!meta.contaDestinoId && pd.contaDestinoId) meta.contaDestinoId = pd.contaDestinoId;
        if (!meta.memberId && pd.memberId) meta.memberId = pd.memberId;
        if (!meta.memberCpf && pd.memberCpf) meta.memberCpf = pd.memberCpf;
        if (!meta.donationKind && pd.donationKind) meta.donationKind = pd.donationKind;
      }
    }
  }

  /**
   * PIX: ponte `mp_payment_bridge` — o MP costuma omitir metadata no webhook;
   * mesclamos donationKind / doador para o extrato bater com a escolha no app/site.
   */
  if (pid) {
    const loaded = await loadPaymentBridge(pid);
    if (loaded) {
      const pd = loaded.pd;
      if (!tenantId) tenantId = loaded.tenantId;
      if (!meta.donorName && pd.donorName) meta.donorName = pd.donorName;
      if (!meta.contaDestinoId && pd.contaDestinoId) meta.contaDestinoId = pd.contaDestinoId;
      if (!meta.memberId && pd.memberId) meta.memberId = pd.memberId;
      if (!meta.memberCpf && pd.memberCpf) meta.memberCpf = pd.memberCpf;
      if (!meta.donationKind && pd.donationKind) meta.donationKind = pd.donationKind;
      if (!isChurch) {
        isChurch = true;
      }
    }
  }

  if (!isChurch) return false;

  if (!tenantId) {
    console.warn("church_donation webhook: tenantId ausente", { pid, preference_id: payment?.preference_id });
    return true;
  }

  const status = String(payment.status || "").toLowerCase();

  await fs()
    .collection("igrejas")
    .doc(tenantId)
    .collection("finance_mp_notifications")
    .doc(pid || "unknown")
    .set(
      {
        status: payment.status,
        paymentId: pid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

  if (status !== "approved") {
    return true;
  }

  const { gross, net, fee } = computeMpNetAmounts(payment);

  let donorName = resolveDonorDisplayName(payment, meta);
  const memberId = String(meta.memberId || "").trim();
  const memberFull = await resolveMemberFullNameForDonation(tenantId, memberId);
  if (memberFull) {
    donorName = memberFull;
  }
  const donationKind = normalizeDonationKind(meta.donationKind);
  const categoriaFinanceiro = categoriaForDonationKind(donationKind);
  const tipoLabel = labelForDonationKind(donationKind);

  const memberCpfDigits = String(meta.memberCpf || meta.memberCpfDigits || "")
    .replace(/\D/g, "")
    .slice(0, 11);
  let contaDestinoId = String(meta.contaDestinoId || "").trim();
  if (!contaDestinoId) {
    contaDestinoId = await resolveDefaultMercadoPagoContaId(tenantId);
  }

  const financeId = `mp_donation_${pid}`;
  const ref = fs().collection("igrejas").doc(tenantId).collection("finance").doc(financeId);
  const existing = await ref.get();
  if (existing.exists) {
    return true;
  }

  const approvedAt = payment.date_approved ? new Date(payment.date_approved) : new Date();
  const ts = admin.firestore.Timestamp.fromDate(approvedAt);

  let contaDestinoNome = "";
  if (contaDestinoId) {
    try {
      const cSnap = await fs()
        .collection("igrejas")
        .doc(tenantId)
        .collection("contas")
        .doc(contaDestinoId)
        .get();
      if (cSnap.exists) {
        contaDestinoNome = String(cSnap.data()?.nome || "").trim();
      }
    } catch {
      /* ignore */
    }
  }

  await ref.set({
    type: "entrada",
    tipo: "entrada",
    amount: net,
    valor: net,
    grossAmount: gross,
    mpFees: fee,
    netAmount: net,
    descricao: `${tipoLabel} (Mercado Pago) — ${donorName}`,
    categoria: categoriaFinanceiro,
    donationKind,
    donationKindLabel: tipoLabel,
    /** Alinhado ao Financeiro (saldo por conta e lista): destino da receita */
    contaDestinoId: contaDestinoId || null,
    contaDestinoNome: contaDestinoNome || null,
    /** Legado / referência rápida */
    contaId: contaDestinoId || null,
    recebimentoConfirmado: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    /** Data do pagamento aprovado (extrato / filtros — [financeLancamentoDate] usa `date` ou `createdAt`) */
    date: ts,
    dataCompetencia: ts,
    mpPaymentId: pid,
    mpOrderStatus: payment.status,
    paymentMethod: payment.payment_type_id || payment.payment_method_id || "pix",
    donorName,
    memberId: memberId || null,
    donorDisplaySource: memberFull ? "membro_cadastro" : "informado_ou_mp",
    origem: "mercado_pago_doacao",
    conciliado: true,
    conciliacaoOrigem: "mp_webhook_auto",
  });

  /** Histórico leve para o painel (dízimos/ofertas) — retenção ~5 meses via prune agendado. */
  const ptRaw = String(payment.payment_type_id || payment.payment_method_id || "").toLowerCase();
  let methodKey = "outro";
  if (ptRaw.includes("pix") || ptRaw === "account_money") methodKey = "pix";
  else if (ptRaw.includes("credit") || ptRaw.includes("debit") || ptRaw.includes("card")) methodKey = "cartao";

  await fs()
    .collection("igrejas")
    .doc(tenantId)
    .collection("contribuicoes_dizimo_historico")
    .doc(pid)
    .set({
      mpPaymentId: pid,
      donorName,
      memberId: memberId || null,
      memberCpfDigits: memberCpfDigits || null,
      donationKind,
      donationKindLabel: tipoLabel,
      categoria: categoriaFinanceiro,
      amount: net,
      grossAmount: gross,
      mpFees: fee,
      methodKey,
      paymentTypeId: String(payment.payment_type_id || ""),
      contaDestinoNome: contaDestinoNome || null,
      approvedAt: ts,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  return true;
}

/** Busca pagamento: ponte `mp_payment_bridge` / legado → token da igreja; senão token da plataforma (index). */
export async function fetchPaymentForWebhook(
  dataId: string,
  platformMpGet: (path: string) => Promise<any>,
  tenantHint?: string
): Promise<{ payment: any; usedChurchToken: boolean }> {
  const tenantFromBridge = await resolveTenantFromPaymentBridge(dataId);
  if (tenantFromBridge) {
    const tok = await getChurchMpAccessToken(tenantFromBridge);
    if (tok) {
      const payment = await mpGetWithToken(tok, `/v1/payments/${dataId}`);
      return { payment, usedChurchToken: true };
    }
  }
  const tid = String(tenantHint || "").trim();
  if (tid) {
    const tok = await getChurchMpAccessToken(tid);
    if (tok) {
      try {
        const payment = await mpGetWithToken(tok, `/v1/payments/${dataId}`);
        return { payment, usedChurchToken: true };
      } catch {
        /* tenta token da plataforma */
      }
    }
  }
  const payment = await platformMpGet(`/v1/payments/${dataId}`);
  return { payment, usedChurchToken: false };
}

export const saveChurchMercadoPagoCredentials = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const tenantId = String(data?.tenantId || "").trim();
    const accessToken = String(data?.accessToken || "").trim();
    const publicKey = String(data?.publicKey || "").trim();
    const notificationWebhookUrl = String(data?.notificationWebhookUrl || "").trim();
    const clientId = String(data?.clientId || "").trim();
    const clientSecret = String(data?.clientSecret || "").trim();
    const webhookSecret = String(data?.webhookSecret || "").trim();
    if (!tenantId) {
      throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatorio");
    }
    if (notificationWebhookUrl && !/^https:\/\//i.test(notificationWebhookUrl)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "URL do webhook deve comecar com https://"
      );
    }
    const uid = context.auth.uid;
    const can = await canManageTenant(uid, context.auth.token?.role, context.auth.token?.tenantId, tenantId);
    if (!can) {
      throw new functions.https.HttpsError("permission-denied", "Sem permissao para configurar esta igreja");
    }

    /** Só segredos (Client Secret / assinatura webhook), sem alterar Public Key / Client ID / URL. */
    const secretsOnly =
      !accessToken &&
      (clientSecret.length > 0 || webhookSecret.length > 0) &&
      !publicKey &&
      !clientId &&
      !notificationWebhookUrl;

    /** Só dados públicos (ex.: Client ID) sem recolocar o Access Token no cliente. */
    if (!accessToken) {
      if (!publicKey && !clientId && !notificationWebhookUrl && !clientSecret && !webhookSecret) {
        throw new functions.https.HttpsError(
          "invalid-argument",
          "Access Token obrigatorio na primeira vez, ou preencha Client ID / Public Key / Webhook / Client Secret / Assinatura webhook."
        );
      }

      if (secretsOnly) {
        const priv: Record<string, unknown> = {
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedByUid: uid,
        };
        if (clientSecret) priv.clientSecret = clientSecret;
        if (webhookSecret) priv.webhookSecret = webhookSecret;
        await fs()
          .collection("igrejas")
          .doc(tenantId)
          .collection("private")
          .doc("mp_credentials")
          .set(priv, { merge: true });
        const cfg: Record<string, unknown> = {
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (clientSecret) cfg.hasClientSecret = true;
        if (webhookSecret) cfg.hasWebhookSecret = true;
        await fs()
          .collection("igrejas")
          .doc(tenantId)
          .collection("config")
          .doc("mercado_pago")
          .set(cfg, { merge: true });
        return { ok: true };
      }

      await fs()
        .collection("igrejas")
        .doc(tenantId)
        .collection("config")
        .doc("mercado_pago")
        .set(
          {
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            ...(publicKey ? { publicKey } : { publicKey: admin.firestore.FieldValue.delete() }),
            ...(clientId ? { clientId } : { clientId: admin.firestore.FieldValue.delete() }),
            ...(notificationWebhookUrl
              ? { notificationWebhookUrl }
              : { notificationWebhookUrl: admin.firestore.FieldValue.delete() }),
          },
          { merge: true }
        );

      if (clientSecret || webhookSecret) {
        const priv: Record<string, unknown> = {
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedByUid: uid,
        };
        if (clientSecret) priv.clientSecret = clientSecret;
        if (webhookSecret) priv.webhookSecret = webhookSecret;
        await fs()
          .collection("igrejas")
          .doc(tenantId)
          .collection("private")
          .doc("mp_credentials")
          .set(priv, { merge: true });
        await fs()
          .collection("igrejas")
          .doc(tenantId)
          .collection("config")
          .doc("mercado_pago")
          .set(
            {
              ...(clientSecret ? { hasClientSecret: true } : {}),
              ...(webhookSecret ? { hasWebhookSecret: true } : {}),
            },
            { merge: true }
          );
      }
      return { ok: true };
    }

    const privToken: Record<string, unknown> = {
      accessToken,
      publicKey,
      mode: "production",
      accessTokenTest: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedByUid: uid,
    };
    if (clientSecret) privToken.clientSecret = clientSecret;
    if (webhookSecret) privToken.webhookSecret = webhookSecret;

    await fs()
      .collection("igrejas")
      .doc(tenantId)
      .collection("private")
      .doc("mp_credentials")
      .set(privToken, { merge: true });

    await fs()
      .collection("igrejas")
      .doc(tenantId)
      .collection("config")
      .doc("mercado_pago")
      .set(
        {
          enabled: true,
          mode: "production",
          publicKey,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...(clientId
            ? { clientId }
            : { clientId: admin.firestore.FieldValue.delete() }),
          ...(notificationWebhookUrl
            ? { notificationWebhookUrl }
            : { notificationWebhookUrl: admin.firestore.FieldValue.delete() }),
          ...(clientSecret ? { hasClientSecret: true } : {}),
          ...(webhookSecret ? { hasWebhookSecret: true } : {}),
        },
        { merge: true }
      );

    return { ok: true };
  });

/** Preset alinhado à conta automática `mercado_pago` em [ensureMercadoPagoContaForNewChurch]. */
const PRESET_CONTAS = [
  { presetId: "tesouraria_mercado_pago", nome: "Mercado Pago", codigo: "323", banco: "Mercado Pago" },
];

export const ensureChurchTreasuryAccountPresets = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const tenantId = String(data?.tenantId || "").trim();
    if (!tenantId) {
      throw new functions.https.HttpsError("invalid-argument", "tenantId obrigatorio");
    }
    const uid = context.auth.uid;
    const can = await canManageTenant(uid, context.auth.token?.role, context.auth.token?.tenantId, tenantId);
    if (!can) {
      throw new functions.https.HttpsError("permission-denied", "Sem permissao");
    }
    const col = fs().collection("igrejas").doc(tenantId).collection("contas");

    let created = 0;
    for (const p of PRESET_CONTAS) {
      const q = await col.where("seedPreset", "==", p.presetId).limit(1).get();
      if (!q.empty) continue;
      const existing = await col.doc("mercado_pago").get();
      if (existing.exists) continue;
      await col.doc("mercado_pago").set({
        nome: p.nome,
        bancoCodigo: p.codigo,
        bancoNome: p.banco,
        agencia: "",
        numeroConta: "",
        tipoConta: "corrente",
        observacao:
          "Recebimentos via integração Mercado Pago. Configure o Access Token em Configurações → Contribuições / Mercado Pago.",
        ativo: true,
        seedPreset: p.presetId,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      created++;
    }
    return { ok: true, created };
  });

export const createChurchDonationPix = functions
  .region("us-central1")
  .https.onCall(async (data, context) => {
    const tenantId = String(data?.tenantId || "").trim();
    const amount = Number(data?.amount || 0);
    const donorName = String(data?.donorName || "Doador").trim().slice(0, 120);
    const memberId = String(data?.memberId || "").trim();
    const payerEmail = String(data?.payerEmail || "").trim();
    const contaDestinoId = String(data?.contaDestinoId || "").trim();
    const donationKind = normalizeDonationKind(data?.donationKind);
    const tipoLabel = labelForDonationKind(donationKind);

    if (!tenantId || amount < 1 || amount > 100000) {
      throw new functions.https.HttpsError("invalid-argument", "Valor invalido (min R$1, max R$100.000)");
    }

    const token = await getChurchMpAccessToken(tenantId);
    if (!token) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Mercado Pago da igreja nao configurado. Peça ao gestor para informar o Access Token em Configuracoes."
      );
    }

    const ig = await fs().collection("igrejas").doc(tenantId).get();
    if (!ig.exists) {
      throw new functions.https.HttpsError("not-found", "Igreja nao encontrada");
    }

    const email =
      payerEmail && payerEmail.includes("@")
        ? payerEmail
        : `doacao+${tenantId.slice(0, 18)}@gestaoyahweh.com.br`;

    let notificationUrl = mpWebhookUrl();
    try {
      const cfgMp = await fs()
        .collection("igrejas")
        .doc(tenantId)
        .collection("config")
        .doc("mercado_pago")
        .get();
      const customN = String(cfgMp.data()?.notificationWebhookUrl || "").trim();
      if (customN && /^https:\/\//i.test(customN)) {
        notificationUrl = customN;
      }
    } catch (_) {
      /* mantém URL da plataforma */
    }
    let contaMeta = contaDestinoId;
    if (!contaMeta) {
      contaMeta = await resolveDefaultMercadoPagoContaId(tenantId);
    }
    notificationUrl = appendTenantToNotificationUrl(notificationUrl, tenantId);
    const payload: any = {
      transaction_amount: Number(amount.toFixed(2)),
      description: `${tipoLabel} — ${donorName}`.slice(0, 240),
      payment_method_id: "pix",
      external_reference: tenantId,
      notification_url: notificationUrl,
      payer: { email },
      metadata: {
        tenantId,
        kind: "church_donation",
        donorName,
        memberId,
        donationKind,
        memberCpf: String(data?.memberCpf || "")
          .replace(/\D/g, "")
          .slice(0, 11),
        contaDestinoId: contaMeta,
      },
    };

    const idem = `church-${tenantId}-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;

    const res = await mpPostWithToken(token, "/v1/payments", payload, {
      "X-Idempotency-Key": idem,
    });

    const payId = String(res?.id || "");
    if (payId) {
      await fs()
        .collection("igrejas")
        .doc(tenantId)
        .collection("mp_payment_bridge")
        .doc(payId)
        .set(
          {
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            amount: Number(amount.toFixed(2)),
            donationKind,
            donorName: donorName.slice(0, 120),
            memberId: memberId || "",
            memberCpf: String(data?.memberCpf || "")
              .replace(/\D/g, "")
              .slice(0, 11),
            contaDestinoId: contaMeta || "",
          },
          { merge: true }
        );
    }

    const tx = res?.point_of_interaction?.transaction_data || {};
    const qrCode = String(tx?.qr_code || tx?.pix_copia_cola || tx?.pix_copy_paste || "");

    return {
      ok: true,
      payment_id: payId,
      status: String(res?.status || ""),
      qr_code: qrCode,
      qr_code_base64: String(tx?.qr_code_base64 || ""),
      ticket_url: String(tx?.ticket_url || ""),
    };
  });

/**
 * Checkout Pro (cartão parcelado + PIX na página do Mercado Pago).
 * O webhook usa tenantId na query da notification_url para buscar o pagamento com o token da igreja.
 */
export const createChurchDonationPreference = functions
  .region("us-central1")
  .https.onCall(async (data) => {
    const tenantId = String(data?.tenantId || "").trim();
    const amount = Number(data?.amount || 0);
    const donorName = String(data?.donorName || "Doador").trim().slice(0, 120);
    const memberId = String(data?.memberId || "").trim();
    const payerEmail = String(data?.payerEmail || "").trim();
    let contaDestinoId = String(data?.contaDestinoId || "").trim();
    const returnUrl = String(data?.returnUrl || "").trim();
    const maxInstallments = Math.min(12, Math.max(1, Math.floor(Number(data?.maxInstallments || 12))));
    const donationKind = normalizeDonationKind(data?.donationKind);
    const tipoLabel = labelForDonationKind(donationKind);

    if (!tenantId || amount < 1 || amount > 100000) {
      throw new functions.https.HttpsError("invalid-argument", "Valor invalido (min R$1, max R$100.000)");
    }
    if (!returnUrl || !/^https:\/\//i.test(returnUrl)) {
      throw new functions.https.HttpsError("invalid-argument", "returnUrl https obrigatorio");
    }

    const token = await getChurchMpAccessToken(tenantId);
    if (!token) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Mercado Pago da igreja nao configurado. Peça ao gestor para informar o Access Token em Configuracoes."
      );
    }

    const ig = await fs().collection("igrejas").doc(tenantId).get();
    if (!ig.exists) {
      throw new functions.https.HttpsError("not-found", "Igreja nao encontrada");
    }

    if (!contaDestinoId) {
      contaDestinoId = await resolveDefaultMercadoPagoContaId(tenantId);
    }

    let notificationUrl = mpWebhookUrl();
    try {
      const cfgMp = await fs()
        .collection("igrejas")
        .doc(tenantId)
        .collection("config")
        .doc("mercado_pago")
        .get();
      const customN = String(cfgMp.data()?.notificationWebhookUrl || "").trim();
      if (customN && /^https:\/\//i.test(customN)) {
        notificationUrl = customN;
      }
    } catch (_) {
      /* mantém URL da plataforma */
    }
    notificationUrl = appendTenantToNotificationUrl(notificationUrl, tenantId);

    // Não enviar `payer` no Checkout Pro: evita pré-preencher / vincular à conta MP do gestor
    // (e-mail placeholder doação+tenant@... fazia o MP tratar como comprador identificado).
    // O doador informa nome/e-mail/cartão na própria página do Mercado Pago.
    const prefBody: any = {
      items: [
        {
          title: `${tipoLabel} — ${donorName}`.slice(0, 127),
          quantity: 1,
          unit_price: Number(amount.toFixed(2)),
          currency_id: "BRL",
        },
      ],
      external_reference: tenantId,
      metadata: {
        tenantId,
        kind: "church_donation",
        donorName,
        memberId,
        donationKind,
        memberCpf: String(data?.memberCpf || "")
          .replace(/\D/g, "")
          .slice(0, 11),
        contaDestinoId,
        ...(payerEmail.includes("@") ? { donorEmail: payerEmail.slice(0, 120) } : {}),
      },
      notification_url: notificationUrl,
      back_urls: {
        success: returnUrl,
        failure: returnUrl,
        pending: returnUrl,
      },
      auto_return: "approved",
      payment_methods: {
        installments: maxInstallments,
        excluded_payment_types: [{ id: "ticket" }, { id: "atm" }],
      },
      statement_descriptor: "DOACAO IGREJA".slice(0, 13),
    };

    const pref = await mpPostWithToken(token, "/checkout/preferences", prefBody);

    const prefId = String(pref?.id || "").trim();
    if (prefId) {
      await fs()
        .collection("igrejas")
        .doc(tenantId)
        .collection("mp_preference_bridge")
        .doc(prefId)
        .set({
          donorName,
          memberId,
          donationKind,
          memberCpf: String(data?.memberCpf || "")
            .replace(/\D/g, "")
            .slice(0, 11),
          contaDestinoId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }

    const initPoint = String(pref?.init_point || "").trim();
    const sandboxInit = String(pref?.sandbox_init_point || "").trim();

    return {
      ok: true,
      init_point: initPoint,
      sandbox_init_point: sandboxInit,
      preference_id: prefId,
    };
  });

/** Remove registros do histórico de dízimos/ofertas com mais de 5 meses (não altera `finance`). */
export const pruneContribuicoesDizimoHistorico = functions
  .region("us-central1")
  .pubsub.schedule("every sunday 05:00")
  .timeZone("America/Sao_Paulo")
  .onRun(async () => {
    const cutoff = new Date();
    cutoff.setMonth(cutoff.getMonth() - 5);
    const ts = admin.firestore.Timestamp.fromDate(cutoff);
    const snap = await fs()
      .collectionGroup("contribuicoes_dizimo_historico")
      .where("approvedAt", "<", ts)
      .limit(450)
      .get();
    if (snap.empty) return null;
    const batch = fs().batch();
    for (const d of snap.docs) {
      batch.delete(d.ref);
    }
    await batch.commit();
    functions.logger.info("pruneContribuicoesDizimoHistorico", { deleted: snap.size });
    return null;
  });
