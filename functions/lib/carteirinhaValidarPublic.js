"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.carteirinhaValidarHttp = void 0;
exports.buildChurchPublicInfo = buildChurchPublicInfo;
exports.parseCarteirinhaQueryParams = parseCarteirinhaQueryParams;
exports.validateCarteirinhaCore = validateCarteirinhaCore;
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const PUBLIC_WEB_BASE = "https://gestaoyahweh.com.br";
function firestoreDb() {
    return admin.firestore();
}
function maskNomePublico(nome) {
    const parts = String(nome || "")
        .trim()
        .split(/\s+/)
        .filter(Boolean);
    if (parts.length === 0)
        return "";
    if (parts.length === 1) {
        const p0 = parts[0];
        return p0.length > 0 ? `${p0.charAt(0)}***` : "";
    }
    const last = parts[parts.length - 1];
    return `${parts[0]} ${last.length > 0 ? last.charAt(0) : ""}.`;
}
function memberActiveFromData(m) {
    const statusRaw = m.STATUS ?? m.status ?? m.ativo ?? m.active;
    if (typeof statusRaw === "boolean")
        return statusRaw;
    if (typeof statusRaw === "string") {
        const s = statusRaw.toLowerCase().trim();
        if (["inativo", "inactive", "false", "0", "desligado", "bloqueado"].includes(s)) {
            return false;
        }
        if (["ativo", "active", "true", "1", "membro"].includes(s))
            return true;
    }
    if (typeof statusRaw === "number" && statusRaw === 0)
        return false;
    return true;
}
function carteiraValidityHint(m) {
    const perm = m.CARTEIRA_PERMANENTE === true ||
        String(m.CARTEIRA_PERMANENTE || "").toLowerCase() === "true";
    if (perm)
        return "Permanente";
    const v = m.CARTEIRA_VALIDADE;
    if (v && typeof v.toDate === "function") {
        try {
            const d = v.toDate();
            if (d && !Number.isNaN(d.getTime())) {
                return d.toISOString().slice(0, 10);
            }
        }
        catch {
            /* ignore */
        }
    }
    return "";
}
function pickFirstString(source, keys) {
    for (const k of keys) {
        const v = String(source[k] ?? "").trim();
        if (v)
            return v;
    }
    return "";
}
function str(v) {
    return String(v ?? "").trim();
}
function normalizePublicSiteBase(church) {
    for (const k of [
        "customPublicDomain",
        "publicSiteDomain",
        "dominioPublico",
        "publicDomain",
        "siteCustomDomain",
    ]) {
        let t = str(church[k]);
        if (!t)
            continue;
        if (!/^https?:\/\//i.test(t))
            t = `https://${t}`;
        try {
            const u = new URL(t);
            return `${u.protocol}//${u.host}`;
        }
        catch {
            /* ignore */
        }
    }
    return PUBLIC_WEB_BASE;
}
function churchPublicFormattedAddress(data) {
    const rua = str(data.rua ?? data.address ?? data.logradouro);
    const qd = str(data.quadraLoteNumero ?? data.quadra_lote_numero);
    const ruaCompleta = rua ? (qd ? `${rua}, ${qd}` : rua) : qd;
    const bairro = str(data.bairro ?? data.BAIRRO);
    const cidade = str(data.cidade ?? data.CIDADE ?? data.localidade ?? data.LOCALIDADE);
    const estado = str(data.estado ?? data.ESTADO ?? data.uf ?? data.UF);
    const cep = str(data.cep ?? data.CEP);
    const cidadeEstado = cidade && estado ? `${cidade} - ${estado}` : cidade || estado;
    const lista = [];
    if (ruaCompleta)
        lista.push(ruaCompleta);
    if (bairro)
        lista.push(bairro);
    if (cidadeEstado)
        lista.push(cidadeEstado);
    if (cep)
        lista.push(`CEP ${cep}`);
    if (lista.length > 0)
        return lista.join(", ");
    return str(data.endereco ?? data.ENDERECO);
}
function churchPublicPhoneRaw(data) {
    const whatsapp = pickFirstString(data, [
        "whatsappIgreja",
        "whatsapp_igreja",
        "whatsapp",
        "telefoneIgreja",
        "telefone",
        "phone",
    ]);
    if (whatsapp)
        return whatsapp;
    return pickFirstString(data, [
        "whatsappGestor",
        "whatsapp_gestor",
        "gestorWhatsapp",
        "gestorTelefone",
        "gestor_telefone",
    ]);
}
function formatPhoneBr(raw) {
    const d = raw.replace(/\D/g, "");
    if (d.length === 11) {
        return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
    }
    if (d.length === 10) {
        return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
    }
    return raw.trim();
}
function buildWhatsappUrl(data, fallbackPhone, churchName) {
    const direct = pickFirstString(data, [
        "whatsappChatUrl",
        "socialWhatsappUrl",
        "whatsappLink",
        "linkWhatsapp",
    ]);
    const msg = churchName
        ? `Olá! Validei uma carteirinha da ${churchName} no Gestão YAHWEH e gostaria de mais informações.`
        : "Olá! Validei uma carteirinha no Gestão YAHWEH e gostaria de mais informações.";
    const encoded = encodeURIComponent(msg);
    if (direct) {
        if (/^[0-9]+$/.test(direct)) {
            const phone = direct.startsWith("55") ? direct : `55${direct}`;
            return `https://wa.me/${phone}?text=${encoded}`;
        }
        let url = direct;
        if (!/^https?:\/\//i.test(url))
            url = `https://${url}`;
        if (url.includes("wa.me") || url.includes("api.whatsapp.com"))
            return url;
        return url;
    }
    const digits = fallbackPhone.replace(/\D/g, "");
    if (!digits)
        return "";
    const phone = digits.startsWith("55") ? digits : `55${digits}`;
    return `https://wa.me/${phone}?text=${encoded}`;
}
function churchPublicHomeUrl(church, tenantId) {
    const slug = pickFirstString(church, ["slug", "slugId", "churchSlug"]);
    const base = normalizePublicSiteBase(church);
    if (!slug)
        return base === PUBLIC_WEB_BASE ? `${PUBLIC_WEB_BASE}/` : base;
    return `${base.replace(/\/$/, "")}/${encodeURIComponent(slug)}`;
}
function churchLogoUrl(church) {
    return pickFirstString(church, [
        "logoUrl",
        "logo_url",
        "logoProcessedUrl",
        "logoProcessed",
        "fotoUrl",
        "foto_url",
    ]);
}
function churchMapsUrl(church, address) {
    const lat = Number(church.latitude ?? church.lat);
    const lng = Number(church.longitude ?? church.lng ?? church.lon);
    if (Number.isFinite(lat) && Number.isFinite(lng)) {
        return `https://maps.google.com/?q=${lat},${lng}`;
    }
    if (address) {
        return `https://maps.google.com/?q=${encodeURIComponent(address)}`;
    }
    return "";
}
function pastorFromMember(m) {
    const name = pickFirstString(m, [
        "carteirinhaAssinadaPorNome",
        "carteirinha_assinada_por_nome",
    ]);
    const role = pickFirstString(m, [
        "carteirinhaAssinadaPorCargo",
        "carteirinha_assinada_por_cargo",
    ]);
    return { name, role: role || "Pastor(a)" };
}
function buildChurchPublicInfo(church, tenantId, memberData) {
    const churchName = pickFirstString(church, ["nome", "name", "slug"]) || tenantId;
    const address = churchPublicFormattedAddress(church);
    const phoneRaw = churchPublicPhoneRaw(church);
    const phoneDisplay = phoneRaw ? formatPhoneBr(phoneRaw) : "";
    const whatsappUrl = buildWhatsappUrl(church, phoneRaw, churchName);
    let pastorName = pickFirstString(church, [
        "gestorNome",
        "gestor_nome",
        "pastor",
        "pastorNome",
        "nomePastor",
    ]);
    let pastorRole = "Pastor(a)";
    if (memberData) {
        const fromMember = pastorFromMember(memberData);
        if (fromMember.name) {
            pastorName = fromMember.name;
            pastorRole = fromMember.role;
        }
    }
    if (!pastorRole)
        pastorRole = "Pastor(a)";
    return {
        churchName,
        logoUrl: churchLogoUrl(church),
        address,
        mapsUrl: churchMapsUrl(church, address),
        pastorName,
        pastorRole,
        phoneDisplay,
        whatsappUrl,
        publicSiteUrl: churchPublicHomeUrl(church, tenantId),
    };
}
function parseCarteirinhaQueryParams(raw) {
    const tenantId = pickFirstString(raw, [
        "tenantId",
        "igrejaId",
        "igreja",
        "churchId",
        "tid",
    ]);
    const memberKey = pickFirstString(raw, [
        "memberId",
        "membroId",
        "membro",
        "id",
        "codigoMembro",
        "COD_MEMBRO",
        "codigo_membro",
        "codigo",
        "code",
    ]);
    return { tenantId, memberKey };
}
async function resolveTenantDocId(tenantKey) {
    const key = tenantKey.trim();
    if (!key)
        return "";
    const direct = await firestoreDb().collection("igrejas").doc(key).get();
    if (direct.exists)
        return key;
    const slug = key.toLowerCase();
    for (const field of ["slug", "churchSlug", "slugPublico"]) {
        const q = await firestoreDb()
            .collection("igrejas")
            .where(field, "==", slug)
            .limit(1)
            .get();
        if (!q.empty)
            return q.docs[0].id;
    }
    return key;
}
async function findMemberSnapshot(tenantId, memberKey) {
    const key = memberKey.trim();
    if (!key)
        return null;
    const membros = firestoreDb().collection("igrejas").doc(tenantId).collection("membros");
    const members = firestoreDb().collection("igrejas").doc(tenantId).collection("members");
    for (const col of [membros, members]) {
        const byId = await col.doc(key).get();
        if (byId.exists)
            return byId;
    }
    const codeFields = ["codigoMembro", "COD_MEMBRO", "codigo_membro", "numeroMembro"];
    for (const field of codeFields) {
        const q = await membros.where(field, "==", key).limit(1).get();
        if (!q.empty)
            return q.docs[0];
    }
    const cpfDigits = key.replace(/\D/g, "");
    if (cpfDigits.length === 11) {
        for (const field of ["CPF", "cpf"]) {
            const q = await membros.where(field, "==", cpfDigits).limit(1).get();
            if (!q.empty)
                return q.docs[0];
            const qFmt = await membros.where(field, "==", key).limit(1).get();
            if (!qFmt.empty)
                return qFmt.docs[0];
        }
    }
    return null;
}
/** Validação pública (Admin SDK) — usada pelo callable e pelo HTTP do QR. */
async function validateCarteirinhaCore(tenantKey, memberKey) {
    const tenantId = await resolveTenantDocId(tenantKey);
    const memberId = memberKey.trim();
    if (!tenantId || !memberId) {
        return {
            ok: false,
            found: false,
            active: false,
            churchName: "",
            titularMascarado: "",
            validityHint: "",
            message: "Parâmetros inválidos. Verifique o QR Code da carteirinha.",
            church: null,
        };
    }
    const igrejaSnap = await firestoreDb().collection("igrejas").doc(tenantId).get();
    if (!igrejaSnap.exists) {
        return {
            ok: true,
            found: false,
            active: false,
            churchName: "",
            titularMascarado: "",
            validityHint: "",
            message: "Igreja não encontrada no sistema.",
            church: null,
        };
    }
    const church = igrejaSnap.data() || {};
    const churchInfoBase = buildChurchPublicInfo(church, tenantId);
    const churchName = churchInfoBase.churchName;
    const snap = await findMemberSnapshot(tenantId, memberId);
    if (!snap || !snap.exists) {
        return {
            ok: true,
            found: false,
            active: false,
            churchName,
            titularMascarado: "",
            validityHint: "",
            message: "Credencial não encontrada nesta igreja.",
            church: churchInfoBase,
        };
    }
    const m = (snap.data() || {});
    const churchInfo = buildChurchPublicInfo(church, tenantId, m);
    const active = memberActiveFromData(m);
    const nomeFull = String(m.NOME_COMPLETO || m.nome || m.name || "").trim();
    const titularMascarado = maskNomePublico(nomeFull);
    const validityHint = carteiraValidityHint(m);
    return {
        ok: true,
        found: true,
        active,
        churchName,
        titularMascarado,
        validityHint,
        message: active
            ? "Credencial localizada e situação ativa no sistema."
            : "Credencial localizada, porém o cadastro não está ativo.",
        church: churchInfo,
    };
}
function escapeHtml(s) {
    return s
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;");
}
function infoRow(icon, label, value, href) {
    if (!value)
        return "";
    const inner = href
        ? `<a href="${escapeHtml(href)}" target="_blank" rel="noopener noreferrer">${escapeHtml(value)}</a>`
        : escapeHtml(value);
    return `<div class="info-row">
    <span class="info-ico" aria-hidden="true">${icon}</span>
    <div class="info-body">
      <span class="info-label">${escapeHtml(label)}</span>
      <span class="info-value">${inner}</span>
    </div>
  </div>`;
}
function renderChurchBlock(ch) {
    const logo = ch.logoUrl
        ? `<img class="church-logo" src="${escapeHtml(ch.logoUrl)}" alt="" loading="lazy" referrerpolicy="no-referrer"/>`
        : `<div class="church-logo ph" aria-hidden="true">⛪</div>`;
    const rows = [
        infoRow("📍", "Localização", ch.address, ch.mapsUrl || undefined),
        ch.pastorName
            ? infoRow("✝️", ch.pastorRole || "Pastor(a)", ch.pastorName)
            : "",
        ch.phoneDisplay
            ? infoRow("💬", "WhatsApp", ch.phoneDisplay, ch.whatsappUrl || undefined)
            : "",
        ch.publicSiteUrl
            ? infoRow("🌐", "Site público", "Acessar site da igreja", ch.publicSiteUrl)
            : "",
    ].filter(Boolean);
    const waBtn = ch.whatsappUrl
        ? `<a class="btn wa" href="${escapeHtml(ch.whatsappUrl)}" target="_blank" rel="noopener noreferrer">Falar no WhatsApp</a>`
        : "";
    const siteBtn = ch.publicSiteUrl
        ? `<a class="btn site" href="${escapeHtml(ch.publicSiteUrl)}" target="_blank" rel="noopener noreferrer">Ver site da igreja</a>`
        : "";
    const mapBtn = ch.mapsUrl
        ? `<a class="btn map" href="${escapeHtml(ch.mapsUrl)}" target="_blank" rel="noopener noreferrer">Abrir no mapa</a>`
        : "";
    return `<section class="church-card">
    <div class="church-head">
      ${logo}
      <div>
        <p class="church-kicker">Igreja emissora</p>
        <h2 class="church-name">${escapeHtml(ch.churchName)}</h2>
      </div>
    </div>
    <div class="info-list">${rows.join("")}</div>
    <div class="church-actions">${waBtn}${siteBtn}${mapBtn}</div>
  </section>`;
}
function renderCarteirinhaHtml(result) {
    const valid = result.ok && result.found && result.active;
    const partial = result.ok && result.found && !result.active;
    const notFound = result.ok && !result.found;
    const badParams = !result.ok;
    let statusClass = "status-warn";
    let statusIcon = "⚠";
    let title = "Validação indisponível";
    let subtitle = result.message || "";
    if (valid) {
        statusClass = "status-ok";
        statusIcon = "✓";
        title = "Credencial verificada";
        subtitle = "Situação ativa no cadastro da igreja.";
    }
    else if (partial) {
        statusClass = "status-warn";
        statusIcon = "!";
        title = "Cadastro inativo";
        subtitle = result.message || "A credencial existe, mas o membro não está ativo.";
    }
    else if (notFound) {
        statusClass = "status-warn";
        statusIcon = "?";
        title = "Credencial não encontrada";
        subtitle = result.message || "Não localizamos este código nesta igreja.";
    }
    else if (badParams) {
        statusClass = "status-err";
        statusIcon = "×";
        title = "Link inválido";
        subtitle = result.message || "Parâmetros ausentes no QR Code.";
    }
    const memberRows = [];
    if (result.titularMascarado) {
        memberRows.push(`<div class="member-pill"><span class="pill-label">Titular</span><span class="pill-value">${escapeHtml(result.titularMascarado)}</span></div>`);
    }
    if (result.validityHint) {
        memberRows.push(`<div class="member-pill"><span class="pill-label">Validade</span><span class="pill-value">${escapeHtml(result.validityHint)}</span></div>`);
    }
    const memberBlock = memberRows.length > 0
        ? `<div class="member-strip">${memberRows.join("")}</div>`
        : "";
    const churchBlock = result.church ? renderChurchBlock(result.church) : "";
    return `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover"/>
  <meta name="theme-color" content="#0b1f3a"/>
  <meta name="robots" content="noindex"/>
  <title>Validar carteirinha — Gestão YAHWEH</title>
  <link rel="preconnect" href="https://fonts.googleapis.com"/>
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin/>
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@500;600;700;800&display=swap" rel="stylesheet"/>
  <style>
    :root {
      --bg0: #060d18;
      --bg1: #0f2744;
      --bg2: #1a4d8c;
      --card: rgba(255,255,255,.97);
      --muted: #64748b;
      --text: #0f172a;
      --ok: #15803d;
      --ok-bg: #dcfce7;
      --warn: #c2410c;
      --warn-bg: #ffedd5;
      --err: #b91c1c;
      --err-bg: #fee2e2;
      --accent: #1565c0;
      --shadow: 0 24px 60px rgba(0,0,0,.35);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100dvh;
      font-family: "Plus Jakarta Sans", system-ui, -apple-system, sans-serif;
      color: var(--text);
      background:
        radial-gradient(ellipse 80% 50% at 50% -10%, rgba(56,189,248,.22), transparent),
        linear-gradient(165deg, var(--bg0) 0%, var(--bg1) 45%, var(--bg2) 100%);
    }
    .shell { max-width: 480px; margin: 0 auto; padding: 0 0 40px; }
    .top {
      padding: calc(16px + env(safe-area-inset-top)) 20px 20px;
      color: #fff;
      display: flex;
      align-items: center;
      gap: 12px;
    }
    .top-back {
      width: 40px; height: 40px; border-radius: 12px;
      background: rgba(255,255,255,.12);
      display: flex; align-items: center; justify-content: center;
      color: #fff; text-decoration: none; font-size: 20px;
      border: 1px solid rgba(255,255,255,.15);
    }
    .top h1 { margin: 0; font-size: 1.05rem; font-weight: 800; letter-spacing: -.02em; }
    .top p { margin: 2px 0 0; font-size: .72rem; opacity: .75; font-weight: 600; }
    .main { padding: 0 16px; }
    .hero {
      background: var(--card);
      border-radius: 20px;
      padding: 22px 20px 18px;
      box-shadow: var(--shadow);
      margin-bottom: 14px;
      border: 1px solid rgba(255,255,255,.6);
    }
    .status-badge {
      display: inline-flex; align-items: center; gap: 8px;
      font-size: .72rem; font-weight: 800; letter-spacing: .08em;
      text-transform: uppercase; padding: 8px 14px; border-radius: 999px;
      margin-bottom: 14px;
    }
    .status-ok { background: var(--ok-bg); color: var(--ok); }
    .status-warn { background: var(--warn-bg); color: var(--warn); }
    .status-err { background: var(--err-bg); color: var(--err); }
    .status-ico {
      width: 22px; height: 22px; border-radius: 50%;
      display: inline-flex; align-items: center; justify-content: center;
      font-weight: 900; font-size: .85rem;
      background: currentColor; color: #fff;
    }
    .status-ok .status-ico { background: var(--ok); }
    .status-warn .status-ico { background: var(--warn); }
    .status-err .status-ico { background: var(--err); }
    .hero h2 { margin: 0 0 6px; font-size: 1.45rem; font-weight: 800; letter-spacing: -.03em; line-height: 1.2; }
    .hero .sub { margin: 0; color: var(--muted); font-size: .92rem; line-height: 1.5; font-weight: 500; }
    .member-strip {
      display: flex; flex-wrap: wrap; gap: 8px; margin-top: 16px;
    }
    .member-pill {
      flex: 1 1 120px; min-width: 0;
      background: #f1f5f9; border-radius: 12px; padding: 10px 12px;
    }
    .pill-label { display: block; font-size: .68rem; font-weight: 700; color: var(--muted); text-transform: uppercase; letter-spacing: .06em; }
    .pill-value { display: block; font-size: .95rem; font-weight: 800; margin-top: 2px; }
    .church-card {
      background: var(--card);
      border-radius: 20px;
      padding: 20px;
      box-shadow: var(--shadow);
      border: 1px solid rgba(255,255,255,.55);
    }
    .church-head { display: flex; gap: 14px; align-items: center; margin-bottom: 16px; }
    .church-logo {
      width: 56px; height: 56px; border-radius: 14px; object-fit: cover;
      background: #e2e8f0; flex-shrink: 0; border: 2px solid #e2e8f0;
    }
    .church-logo.ph {
      display: flex; align-items: center; justify-content: center;
      font-size: 1.6rem; background: linear-gradient(135deg,#e0f2fe,#dbeafe);
    }
    .church-kicker { margin: 0; font-size: .68rem; font-weight: 700; color: var(--muted); text-transform: uppercase; letter-spacing: .08em; }
    .church-name { margin: 2px 0 0; font-size: 1.15rem; font-weight: 800; letter-spacing: -.02em; line-height: 1.25; }
    .info-list { display: flex; flex-direction: column; gap: 12px; }
    .info-row { display: flex; gap: 12px; align-items: flex-start; }
    .info-ico { font-size: 1.1rem; line-height: 1.4; flex-shrink: 0; }
    .info-label { display: block; font-size: .68rem; font-weight: 700; color: var(--muted); text-transform: uppercase; letter-spacing: .05em; }
    .info-value { display: block; font-size: .9rem; font-weight: 600; margin-top: 2px; line-height: 1.4; color: var(--text); }
    .info-value a { color: var(--accent); text-decoration: none; font-weight: 700; }
    .info-value a:hover { text-decoration: underline; }
    .church-actions { display: flex; flex-direction: column; gap: 8px; margin-top: 16px; }
    .btn {
      display: block; text-align: center; padding: 13px 16px;
      border-radius: 14px; font-weight: 800; font-size: .9rem;
      text-decoration: none; border: none; cursor: pointer;
      font-family: inherit;
    }
    .btn.wa { background: #25d366; color: #fff; }
    .btn.site { background: linear-gradient(135deg,#1565c0,#0d47a1); color: #fff; }
    .btn.map { background: #fff; color: var(--accent); border: 2px solid #bfdbfe; }
    .btn.retry { background: #f1f5f9; color: var(--text); margin-top: 14px; width: 100%; }
    .footer {
      text-align: center; padding: 20px 16px 8px;
      font-size: .7rem; color: rgba(255,255,255,.55); font-weight: 600;
    }
    .footer strong { color: rgba(255,255,255,.85); }
  </style>
</head>
<body>
  <div class="shell">
    <header class="top">
      <a class="top-back" href="/" aria-label="Voltar">←</a>
      <div>
        <h1>Validar carteirinha</h1>
        <p>Gestão YAHWEH · verificação oficial</p>
      </div>
    </header>
    <main class="main">
      <section class="hero">
        <div class="status-badge ${statusClass}">
          <span class="status-ico">${statusIcon}</span>
          ${valid ? "Válida" : partial ? "Inativa" : notFound ? "Não encontrada" : "Inválida"}
        </div>
        <h2>${escapeHtml(title)}</h2>
        <p class="sub">${escapeHtml(subtitle)}</p>
        ${memberBlock}
        <button type="button" class="btn retry" onclick="location.reload()">Atualizar validação</button>
      </section>
      ${churchBlock}
    </main>
    <p class="footer">Validação em tempo real · <strong>Gestão YAHWEH</strong></p>
  </div>
</body>
</html>`;
}
/**
 * HTTP para o QR da carteirinha — lê query string completa (Hosting rewrite).
 * Corrige perda de `?tenantId=&memberId=` no SPA Flutter web.
 */
exports.carteirinhaValidarHttp = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 30, memory: "256MB" })
    .https.onRequest(async (req, res) => {
    try {
        const q = { ...req.query };
        if (req.url && req.url.includes("?")) {
            const parsed = new URL(req.url, "https://gestaoyahweh.com.br");
            parsed.searchParams.forEach((v, k) => {
                if (!q[k])
                    q[k] = v;
            });
        }
        const { tenantId, memberKey } = parseCarteirinhaQueryParams(q);
        const result = await validateCarteirinhaCore(tenantId, memberKey);
        res.set("Cache-Control", "no-store");
        res.status(200).send(renderCarteirinhaHtml(result));
    }
    catch (e) {
        functions.logger.error("carteirinhaValidarHttp", e);
        res.status(500).send(renderCarteirinhaHtml({
            ok: false,
            found: false,
            active: false,
            churchName: "",
            titularMascarado: "",
            validityHint: "",
            message: "Erro temporário no servidor. Tente novamente em instantes.",
            church: null,
        }));
    }
});
//# sourceMappingURL=carteirinhaValidarPublic.js.map