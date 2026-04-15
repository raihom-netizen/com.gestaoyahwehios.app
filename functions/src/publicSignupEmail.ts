/**
 * E-mail de confirmação pós-cadastro público (acompanhar aprovação).
 * Opcional: configure SENDGRID_API_KEY + SENDGRID_FROM_EMAIL nas variáveis da função (GCP).
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

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export async function trySendPublicSignupConfirmationEmail(opts: {
  to: string;
  memberName: string;
  churchName: string;
  protocol: string;
  slugForUrl: string;
}): Promise<boolean> {
  const key = SENDGRID_KEY.value().trim();
  const from = SENDGRID_FROM.value().trim();
  // Placeholder "unset" no .env permite deploy não-interativo sem chave SendGrid real.
  if (!key || !from || key === "unset" || from === "unset") {
    functions.logger.info("publicSignupEmail: SENDGRID_API_KEY ou SENDGRID_FROM_EMAIL vazios — e-mail não enviado.");
    return false;
  }
  const to = String(opts.to || "").trim().toLowerCase();
  if (!to.includes("@")) return false;

  const base = PUBLIC_WEB_BASE.value().trim().replace(/\/$/, "");
  const slug = encodeURIComponent(opts.slugForUrl.trim() || "igreja");
  const proto = encodeURIComponent(opts.protocol.trim());
  const trackUrl = `${base}/igreja/${slug}/acompanhar-cadastro?protocolo=${proto}`;

  const nome = escapeHtml(opts.memberName.trim() || "Olá");
  const igreja = escapeHtml(opts.churchName.trim() || "sua igreja");
  const subject = `Cadastro recebido — ${opts.churchName.trim() || "Igreja"} — acompanhe a aprovação`;

  const html = `
<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"/></head>
<body style="font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;line-height:1.5;color:#111827;background:#f8fafc;padding:24px;">
  <div style="max-width:560px;margin:0 auto;background:#fff;border-radius:16px;padding:28px 24px;box-shadow:0 10px 40px rgba(15,23,42,0.08);border:1px solid #e5e7eb;">
    <p style="margin:0 0 12px;font-size:18px;font-weight:700;color:#059669;">Cadastro enviado com sucesso</p>
    <p style="margin:0 0 16px;font-size:15px;">Olá, <strong>${nome}</strong>,</p>
    <p style="margin:0 0 12px;font-size:14px;color:#374151;">Seu cadastro em <strong>${igreja}</strong> foi recebido e está <strong>aguardando aprovação</strong> da liderança.</p>
    <p style="margin:0 0 8px;font-size:13px;color:#6b7280;"><strong>Protocolo:</strong> ${escapeHtml(opts.protocol.trim())}</p>
    <p style="margin:16px 0 12px;font-size:14px;">Use o link abaixo para acompanhar se o cadastro foi aprovado:</p>
    <p style="margin:0 0 20px;"><a href="${trackUrl}" style="display:inline-block;background:#2563eb;color:#fff;text-decoration:none;padding:12px 20px;border-radius:12px;font-weight:600;font-size:14px;">Acompanhar meu cadastro</a></p>
    <p style="margin:0;font-size:12px;color:#9ca3af;word-break:break-all;">${escapeHtml(trackUrl)}</p>
    <hr style="border:none;border-top:1px solid #e5e7eb;margin:20px 0;"/>
    <p style="margin:0;font-size:12px;color:#9ca3af;">Quando aprovado, o gestor poderá liberar seu acesso ao sistema (senha inicial costuma ser <strong>123456</strong>, salvo orientação da igreja).</p>
    <p style="margin:12px 0 0;font-size:11px;color:#d1d5db;">Gestão YAHWEH — mensagem automática</p>
  </div>
</body></html>`;

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
      subject,
      content: [{ type: "text/html", value: html }],
    }),
  });

  if (!res.ok) {
    const t = await res.text().catch(() => "");
    functions.logger.error("publicSignupEmail SendGrid HTTP", res.status, t);
    return false;
  }
  functions.logger.info("publicSignupEmail sent", { to });
  return true;
}
