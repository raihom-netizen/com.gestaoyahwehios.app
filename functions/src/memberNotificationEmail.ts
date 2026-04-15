/**
 * Modelos HTML de e-mail — Gestão YAHWEH (avisos, escalas, eventos, aniversariantes).
 * Envio via SendGrid (mesmas variáveis que publicSignupEmail: SENDGRID_API_KEY, SENDGRID_FROM_EMAIL).
 */
import * as functions from "firebase-functions/v1";
import { defineString } from "firebase-functions/params";

const SENDGRID_KEY = defineString("SENDGRID_API_KEY", { default: "" });
const SENDGRID_FROM = defineString("SENDGRID_FROM_EMAIL", { default: "" });
const SENDGRID_FROM_NAME = defineString("SENDGRID_FROM_NAME", {
  default: "Gestão YAHWEH",
});
const PUBLIC_WEB_BASE = defineString("PUBLIC_WEB_BASE_URL", {
  default: "https://gestaoyahweh.com.br",
});

/** Azul menu lateral / identidade (YahwehDesignSystem.navSidebar). */
const BRAND_NAV = "#0A3D91";
/** Botões e destaques (YahwehDesignSystem.brandPrimary). */
const BRAND_CTA = "#0052CC";
const TEXT_MUTED = "#64748B";
const BG_PAGE = "#F1F5F9";

const FOOTER_VERSE =
  "Consagre ao Senhor tudo o que você faz, e os seus planos serão bem-sucedidos. — Provérbios 16:3";

export function escapeHtml(s: string): string {
  return String(s || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** URL do painel (login web / PWA) para CTAs. */
export function panelLoginUrl(): string {
  return `${PUBLIC_WEB_BASE.value().trim().replace(/\/$/, "")}/igreja/login`;
}

function wrapEmail(opts: {
  preheader: string;
  innerHtml: string;
  ctaLabel: string;
  ctaUrl: string;
}): string {
  const cta = escapeHtml(opts.ctaUrl);
  const pre = escapeHtml(opts.preheader.slice(0, 140));
  return `<!DOCTYPE html>
<html lang="pt-BR"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width"/><meta name="description" content="${pre}"/></head>
<body style="margin:0;padding:0;background:${BG_PAGE};font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#0F172A;line-height:1.55;">
  <div style="display:none;max-height:0;overflow:hidden;">${pre}</div>
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:${BG_PAGE};padding:24px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" style="max-width:560px;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 12px 40px rgba(15,23,42,0.08);border:1px solid #E2E8F0;">
        <tr><td style="background:${BRAND_NAV};padding:18px 22px;">
          <p style="margin:0;font-size:17px;font-weight:800;color:#fff;letter-spacing:-0.3px;">Gestão YAHWEH</p>
          <p style="margin:6px 0 0;font-size:12px;color:rgba(255,255,255,0.88);">Equipe Gestão YAHWEH</p>
        </td></tr>
        <tr><td style="padding:26px 22px 8px;">
          ${opts.innerHtml}
        </td></tr>
        <tr><td style="padding:8px 22px 28px;" align="center">
          <a href="${cta}" style="display:inline-block;background:${BRAND_CTA};color:#fff!important;text-decoration:none;padding:14px 26px;border-radius:12px;font-weight:700;font-size:15px;">${escapeHtml(
            opts.ctaLabel
          )}</a>
        </td></tr>
        <tr><td style="padding:0 22px 22px;">
          <p style="margin:0;font-size:12px;color:${TEXT_MUTED};line-height:1.45;font-style:italic;text-align:center;border-top:1px solid #E2E8F0;padding-top:16px;">${escapeHtml(
            FOOTER_VERSE
          )}</p>
          <p style="margin:12px 0 0;font-size:11px;color:#94A3B8;text-align:center;">Mensagem automática — não responda este e-mail.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

/** 1 — Avisos gerais */
export function buildAvisoEmail(opts: {
  memberName: string;
  avisoTitle: string;
  publishedDatePt: string;
  ctaUrl?: string;
}): { subject: string; html: string } {
  const nome = escapeHtml(opts.memberName.trim() || "Olá");
  const titulo = escapeHtml(opts.avisoTitle.trim() || "Novo aviso");
  const data = escapeHtml(opts.publishedDatePt.trim());
  const url = opts.ctaUrl?.trim() || panelLoginUrl();
  const inner = `
    <p style="margin:0 0 14px;font-size:16px;">Olá, <strong>${nome}</strong>!</p>
    <p style="margin:0 0 14px;font-size:14px;color:#334155;">Há uma nova atualização importante para você no painel de avisos da nossa comunidade.</p>
    <p style="margin:0 0 6px;font-size:13px;color:${TEXT_MUTED};"><strong>Título do aviso:</strong></p>
    <p style="margin:0 0 14px;font-size:15px;font-weight:700;color:${BRAND_NAV};">${titulo}</p>
    <p style="margin:0 0 18px;font-size:13px;color:#475569;"><strong>Data de publicação:</strong> ${data}</p>
    <p style="margin:0;font-size:14px;color:#334155;">Para ler o conteúdo completo e ficar por dentro das novidades, use o botão abaixo.</p>`;
  return {
    subject: `📢 Importante: Novo aviso no Gestão YAHWEH`,
    html: wrapEmail({
      preheader: `Novo aviso: ${opts.avisoTitle}`,
      innerHtml: inner,
      ctaLabel: "Acessar painel de avisos",
      ctaUrl: url,
    }),
  };
}

/** 2 — Escala / serviço */
export function buildEscalaEmail(opts: {
  volunteerName: string;
  funcao: string;
  dataEventoPt: string;
  horarioChegada: string;
  local: string;
  ctaUrl?: string;
}): { subject: string; html: string } {
  const nome = escapeHtml(opts.volunteerName.trim() || "Olá");
  const fn = escapeHtml(opts.funcao.trim() || "—");
  const dt = escapeHtml(opts.dataEventoPt.trim());
  const hr = escapeHtml(opts.horarioChegada.trim() || "—");
  const loc = escapeHtml(opts.local.trim() || "—");
  const url = opts.ctaUrl?.trim() || panelLoginUrl();
  const inner = `
    <p style="margin:0 0 14px;font-size:16px;">Olá, <strong>${nome}</strong>!</p>
    <p style="margin:0 0 14px;font-size:14px;color:#334155;">Sua escala de serviço foi atualizada. Confira os detalhes do seu próximo compromisso:</p>
    <table role="presentation" width="100%" style="font-size:14px;color:#334155;margin-bottom:16px;">
      <tr><td style="padding:6px 0;"><strong>Função:</strong></td><td>${fn}</td></tr>
      <tr><td style="padding:6px 0;"><strong>Data:</strong></td><td>${dt}</td></tr>
      <tr><td style="padding:6px 0;"><strong>Horário de chegada:</strong></td><td>${hr}</td></tr>
      <tr><td style="padding:6px 0;vertical-align:top;"><strong>Local:</strong></td><td>${loc}</td></tr>
    </table>
    <p style="margin:0;font-size:14px;color:#334155;">Por favor, confirme sua disponibilidade no sistema o quanto antes para que possamos nos organizar.</p>`;
  return {
    subject: `🗓️ Sua escala: compromisso em ${opts.dataEventoPt}`,
    html: wrapEmail({
      preheader: `Escala: ${opts.funcao} em ${opts.dataEventoPt}`,
      innerHtml: inner,
      ctaLabel: "Confirmar presença na escala",
      ctaUrl: url,
    }),
  };
}

/** 3 — Eventos */
export function buildEventoEmail(opts: {
  memberName: string;
  eventName: string;
  dataHoraPt: string;
  local: string;
  ctaUrl?: string;
}): { subject: string; html: string } {
  const nome = escapeHtml(opts.memberName.trim() || "Olá");
  const ev = escapeHtml(opts.eventName.trim() || "Evento");
  const dh = escapeHtml(opts.dataHoraPt.trim());
  const loc = escapeHtml(opts.local.trim() || "—");
  const url = opts.ctaUrl?.trim() || panelLoginUrl();
  const inner = `
    <p style="margin:0 0 14px;font-size:16px;">Olá, <strong>${nome}</strong>!</p>
    <p style="margin:0 0 14px;font-size:14px;color:#334155;">Temos um novo evento programado e gostaríamos muito da sua participação!</p>
    <p style="margin:0 0 6px;font-size:13px;color:${TEXT_MUTED};"><strong>Evento</strong></p>
    <p style="margin:0 0 12px;font-size:16px;font-weight:800;color:${BRAND_NAV};">${ev}</p>
    <p style="margin:0 0 8px;font-size:14px;"><strong>Data e hora:</strong> ${dh}</p>
    <p style="margin:0 0 18px;font-size:14px;"><strong>Local:</strong> ${loc}</p>
    <p style="margin:0;font-size:14px;color:#334155;">Prepare-se para um tempo especial. Mais detalhes estão no sistema.</p>`;
  return {
    subject: `🚩 Novo evento: ${opts.eventName.trim() || "Evento"} — inscreva-se!`,
    html: wrapEmail({
      preheader: opts.eventName,
      innerHtml: inner,
      ctaLabel: "Ver detalhes do evento",
      ctaUrl: url,
    }),
  };
}

/** 4 — Aniversariante do dia (e-mail individual) */
export function buildAniversarianteEmail(opts: {
  nomeDestinatario: string;
  ctaUrl?: string;
}): { subject: string; html: string } {
  const nome = escapeHtml(opts.nomeDestinatario.trim() || "Olá");
  const url = opts.ctaUrl?.trim() || panelLoginUrl();
  const inner = `
    <p style="margin:0 0 14px;font-size:16px;">Olá, <strong>${nome}</strong>!</p>
    <p style="margin:0 0 14px;font-size:14px;color:#334155;">Hoje é um dia de alegria para toda a equipe da Gestão YAHWEH! Queremos desejar a você um <strong>feliz aniversário</strong>, com muita saúde, paz e bênçãos.</p>
    <p style="margin:0 0 18px;font-size:14px;color:#334155;font-style:italic;">"O Senhor te abençoe e te guarde; o Senhor faça resplandecer o seu rosto sobre ti…" — Números 6:24-25</p>
    <p style="margin:0;font-size:14px;color:#334155;">Tenha um dia abençoado!</p>`;
  return {
    subject: "🎂 Parabéns! Celebramos a sua vida hoje!",
    html: wrapEmail({
      preheader: `Feliz aniversário, ${opts.nomeDestinatario}`,
      innerHtml: inner,
      ctaLabel: "Abrir o Gestão YAHWEH",
      ctaUrl: url,
    }),
  };
}

/** Envia HTML via API SendGrid (retorna false se desconfigurado ou erro). */
export async function sendGestaoYahwehHtmlEmail(opts: {
  to: string;
  subject: string;
  html: string;
}): Promise<boolean> {
  const key = SENDGRID_KEY.value().trim();
  const from = SENDGRID_FROM.value().trim();
  if (!key || !from || key === "unset" || from === "unset") {
    functions.logger.info("memberNotificationEmail: SendGrid não configurado — e-mail não enviado.");
    return false;
  }
  const to = String(opts.to || "")
    .trim()
    .toLowerCase();
  if (!to.includes("@")) return false;

  const res = await fetch("https://api.sendgrid.com/v3/mail/send", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      personalizations: [{ to: [{ email: to }] }],
      from: {
        email: from,
        name: SENDGRID_FROM_NAME.value().trim() || "Gestão YAHWEH",
      },
      subject: opts.subject,
      content: [{ type: "text/html", value: opts.html }],
    }),
  });

  if (!res.ok) {
    const t = await res.text().catch(() => "");
    functions.logger.error("memberNotificationEmail SendGrid", res.status, t);
    return false;
  }
  functions.logger.info("memberNotificationEmail sent", { to: opts.subject.slice(0, 40) });
  return true;
}
