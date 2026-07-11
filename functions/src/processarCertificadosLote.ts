/**
 * Lote na nuvem: um único PDF multi-página (PDFKit — UTF-8/pt-BR),
 * fotos via Storage/HTTP + sharp, grava em igrejas/{id}/certificados_lote/.
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import type { Bucket } from "@google-cloud/storage";
import type { DocumentData } from "firebase-admin/firestore";
import { randomUUID } from "crypto";
import sharp from "sharp";
import * as https from "https";
import * as http from "http";

// eslint-disable-next-line @typescript-eslint/no-require-imports
const PDFDocument = require("pdfkit");

function canEmitCertificatesRole(role: string): boolean {
  const r = role.toUpperCase();
  return r === "MASTER" || r === "ADM" || r === "ADMIN" || r === "GESTOR";
}

function formatCpf(cpf: string): string {
  const d = String(cpf || "").replace(/\D/g, "");
  if (d.length !== 11) return String(cpf || "");
  return `${d.slice(0, 3)}.${d.slice(3, 6)}.${d.slice(6, 9)}-${d.slice(9)}`;
}

function dataHojeBr(): string {
  const n = new Date();
  const dd = String(n.getDate()).padStart(2, "0");
  const mm = String(n.getMonth() + 1).padStart(2, "0");
  return `${dd}/${mm}/${n.getFullYear()}`;
}

const TEXTO_MODELO_PADRAO: Record<string, string> = {
  batismo:
    "Certificamos que {NOME}, portador(a) do CPF {CPF}, foi batizado(a) nas águas conforme a ordenança bíblica de Mateus 28:19, nesta igreja, na data de {DATA_CERTIFICADO}.\n\nQue o Senhor abençoe e guarde os passos deste(a) irmão(ã) em sua caminhada cristã.",
  membro:
    "Certificamos que {NOME}, portador(a) do CPF {CPF}, é membro ativo desta igreja, tendo sido recebido(a) em nosso rol de membros.\n\nEste certificado é emitido para os devidos fins em {DATA_CERTIFICADO}.",
  apresentacao:
    "Certificamos que a criança {NOME} foi apresentada ao Senhor nesta igreja, em cerimônia realizada na data de {DATA_CERTIFICADO}, conforme o exemplo bíblico de Lucas 2:22.\n\nQue Deus abençoe e proteja esta criança e sua família.",
  casamento:
    "Certificamos que {NOME} contraiu matrimônio nesta igreja na data de {DATA_CERTIFICADO}, tendo a cerimônia sido celebrada conforme os preceitos cristãos.\n\nQue o Senhor abençoe este lar com amor, paz e fidelidade.",
  participacao:
    "Certificamos que {NOME} participou do evento/curso realizado por esta igreja na data de {DATA_CERTIFICADO}.\n\nAgradecemos sua presença e dedicação.",
  lideranca:
    "Certificamos que {NOME}, portador(a) do CPF {CPF}, exerce a função de líder nesta igreja, contribuindo para o crescimento espiritual da comunidade.\n\nEste certificado é emitido em {DATA_CERTIFICADO} como reconhecimento por sua dedicação.",
  conclusao_curso:
    "Certificamos que {NOME} concluiu com aproveitamento o curso ministrado por esta igreja na data de {DATA_CERTIFICADO}.\n\nParabéns pelo empenho e dedicação.",
  ordenacao:
    "Certificamos que {NOME}, portador(a) do CPF {CPF}, foi ordenado(a) ao ministério nesta igreja na data de {DATA_CERTIFICADO}, após cumprir todos os requisitos estabelecidos pela liderança eclesiástica.\n\nQue o Senhor o(a) capacite e fortaleça no exercício do ministério.",
  reconhecimento:
    "Certificamos que {NOME} recebe o presente reconhecimento por relevantes serviços prestados a esta igreja, em {DATA_CERTIFICADO}.\n\nAgradecemos sua dedicação e parceria.",
  honra_merito:
    "A igreja outorga a {NOME} a Honra ao Mérito em {DATA_CERTIFICADO}, em reconhecimento ao seu destacado empenho e contribuição.\n\nQue o Senhor continue abençoando seus passos.",
};

const TITULO_PADRAO: Record<string, string> = {
  batismo: "Certificado de Batismo",
  membro: "Certificado de Membro",
  apresentacao: "Certificado de Apresentação",
  casamento: "Certificado de Casamento",
  participacao: "Certificado de Participação",
  lideranca: "Certificado de Liderança",
  conclusao_curso: "Certificado de Conclusão de Curso",
  ordenacao: "Certificado de Ordenação",
  reconhecimento: "Certificado de Reconhecimento",
  honra_merito: "Honra ao Mérito",
};

async function downloadUrlBuffer(url: string): Promise<Buffer | null> {
  const u = String(url || "").trim();
  if (!u.startsWith("http")) return null;
  return new Promise((resolve) => {
    try {
      const lib = u.startsWith("https") ? https : http;
      lib
        .get(u, (res) => {
          if (res.statusCode && res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
            void downloadUrlBuffer(res.headers.location).then(resolve);
            res.resume();
            return;
          }
          const chunks: Buffer[] = [];
          res.on("data", (c: Buffer) => chunks.push(c));
          res.on("end", () => {
            const b = Buffer.concat(chunks);
            resolve(b.length > 32 ? b : null);
          });
        })
        .on("error", () => resolve(null));
    } catch {
      resolve(null);
    }
  });
}

function storagePathFromFirebaseDownloadUrl(url: string): string | null {
  try {
    const u = new URL(url);
    if (!u.hostname.includes("firebasestorage") && !u.hostname.includes("googleapis.com")) {
      return null;
    }
    const marker = "/o/";
    const i = u.pathname.indexOf(marker);
    if (i < 0) return null;
    let path = u.pathname.slice(i + marker.length);
    path = decodeURIComponent(path.split("?")[0] || "");
    return path || null;
  } catch {
    return null;
  }
}

async function downloadImageBuffer(bucket: Bucket, urlOrPath: string): Promise<Buffer | null> {
  const raw = String(urlOrPath || "").trim();
  if (!raw) return null;
  if (!raw.startsWith("http")) {
    try {
      const [buf] = await bucket.file(raw).download();
      return buf.length > 32 ? buf : null;
    } catch {
      return null;
    }
  }
  const path = storagePathFromFirebaseDownloadUrl(raw);
  if (path) {
    try {
      const [buf] = await bucket.file(path).download();
      if (buf.length > 32) return buf;
    } catch {
      /* HTTP fallback */
    }
  }
  return downloadUrlBuffer(raw);
}

async function sharpForPdfSlot(buf: Buffer): Promise<Buffer | null> {
  try {
    return await sharp(buf)
      .rotate()
      .resize({
        width: 900,
        height: 900,
        fit: "inside",
        withoutEnlargement: false,
      })
      .jpeg({ quality: 88, chromaSubsampling: "4:4:4", mozjpeg: true })
      .toBuffer();
  } catch {
    return null;
  }
}

function memberPhotoUrl(md: DocumentData): string {
  const tryStr = (v: unknown): string => (typeof v === "string" ? v.trim() : "");
  const keys = [
    "fotoProcessadaUrl",
    "foto_processada_url",
    "FOTO_PROCESSADA_URL",
    "fotoUrl",
    "foto_url",
    "FOTO_URL",
    "photoUrl",
    "photo_url",
    "avatarUrl",
    "imagemUrl",
  ];
  for (const k of keys) {
    const s = tryStr(md[k]);
    if (s.startsWith("http")) return s;
  }
  const foto = md.foto;
  if (foto && typeof foto === "object") {
    const m = foto as Record<string, unknown>;
    const s = tryStr(m.url || m.downloadUrl || m.downloadURL);
    if (s.startsWith("http")) return s;
  }
  return "";
}

function cargoFromMemberData(md: DocumentData): string {
  const c =
    String(md.cargo_lideranca || md.CARGO_LIDERANCA || md.cargo || md.CARGO || "")
      .trim();
  return c || "Líder";
}

function fillTextoModelo(tpl: string, nome: string, cpf: string, dh: string): string {
  return tpl.split("{NOME}").join(nome).split("{CPF}").join(formatCpf(cpf)).split("{DATA_CERTIFICADO}").join(dh);
}

type PageDrawOpts = {
  titulo: string;
  nome: string;
  texto: string;
  nomeIgreja: string;
  localLine: string;
  signatureImages: Buffer[];
  pastorNome: string;
  pastorCargo: string;
  memberPhotoJpeg: Buffer | null;
};

function drawCertificatePage(doc: typeof PDFDocument.prototype, opts: PageDrawOpts): void {
  const pageW = doc.page.width;
  const margin = 48;

  doc
    .lineWidth(2)
    .strokeColor("#264D8C")
    .rect(margin - 12, margin - 12, pageW - 2 * (margin - 12), doc.page.height - 2 * (margin - 12))
    .stroke();

  doc.fontSize(20).fillColor("#1A3366").text(opts.titulo, margin, margin, {
    align: "center",
    width: pageW - 2 * margin,
  });
  doc.moveDown(0.6);
  doc.fontSize(16).fillColor("#000000").text(opts.nome, {
    align: "center",
    width: pageW - 2 * margin,
  });
  doc.moveDown(0.8);

  const textWidth = pageW - 2 * margin - (opts.memberPhotoJpeg ? 90 : 0);
  doc.fontSize(11).fillColor("#262626").text(opts.texto, {
    align: "justify",
    width: textWidth,
  });

  if (opts.memberPhotoJpeg) {
    try {
      const photoX = pageW - margin - 72;
      const photoY = margin + 8;
      doc.image(opts.memberPhotoJpeg, photoX, photoY, { fit: [72, 72] });
    } catch {
      /* ignore bad image */
    }
  }

  doc.moveDown(1.2);
  doc.fontSize(14).fillColor("#1A3366").text(opts.nomeIgreja, {
    align: "center",
    width: pageW - 2 * margin,
  });
  if (opts.localLine) {
    doc.moveDown(0.3);
    doc.fontSize(10).fillColor("#666666").text(opts.localLine, {
      align: "center",
      width: pageW - 2 * margin,
    });
    doc.fillColor("#000000");
  }

  const bottomY = doc.page.height - margin - 70;
  doc.y = bottomY;

  const imgs = opts.signatureImages.filter(Boolean);
  if (imgs.length > 0) {
    const startY = doc.y;
    let x = margin;
    const slotW = (pageW - 2 * margin) / Math.min(imgs.length, 3) - 8;
    for (let i = 0; i < Math.min(imgs.length, 3); i++) {
      try {
        doc.image(imgs[i], x, startY, { fit: [Math.min(slotW, 120), 48] });
      } catch {
        /* ignore */
      }
      x += slotW + 16;
    }
    doc.y = startY + 56;
    doc.moveDown(0.3);
  }

  doc.fontSize(10).fillColor("#000000").text(opts.pastorNome, {
    align: "center",
    width: pageW - 2 * margin,
  });
  doc.fontSize(9).fillColor("#555555").text(opts.pastorCargo, {
    align: "center",
    width: pageW - 2 * margin,
  });
}

function buildMultiPagePdfBuffer(pages: PageDrawOpts[]): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    const doc = new PDFDocument({
      size: "A4",
      layout: "landscape",
      margin: 48,
      autoFirstPage: false,
    });
    doc.on("data", (c: Buffer) => chunks.push(c));
    doc.on("error", reject);
    doc.on("end", () => resolve(Buffer.concat(chunks)));

    for (let i = 0; i < pages.length; i++) {
      doc.addPage();
      drawCertificatePage(doc, pages[i]);
    }
    doc.end();
  });
}

async function firebaseDownloadUrlForPath(
  bucket: Bucket,
  objectPath: string,
  downloadToken: string,
): Promise<string> {
  const encoded = encodeURIComponent(objectPath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/${encoded}?alt=media&token=${downloadToken}`;
}

async function processarCertificadosLoteHandler(
  data: Record<string, unknown>,
  context: functions.https.CallableContext,
): Promise<{ ok: boolean; jobId: string; downloadUrl: string; pageCount: number }> {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Login necessário");
  }
  const roleCaller = String(context.auth.token?.role || "").toUpperCase();
  const callerTenantId = String(context.auth.token?.igrejaId || "").trim();
  if (!canEmitCertificatesRole(roleCaller)) {
    throw new functions.https.HttpsError("permission-denied", "Acesso restrito a gestores");
  }

  const igrejaId = String(data?.igrejaId || data?.tenantId || "").trim();
  const listaRaw = data?.listaMembrosId ?? data?.memberIds;
  const memberIds: string[] = Array.isArray(listaRaw)
    ? listaRaw.map((x: unknown) => String(x || "").trim()).filter(Boolean)
    : [];
  const idAssinatura = String(data?.idAssinatura || data?.templateId || "batismo").trim();

  if (!igrejaId || memberIds.length === 0) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "igrejaId (ou tenantId) e listaMembrosId (ou memberIds) são obrigatórios",
    );
  }
  if (memberIds.length > 200) {
    throw new functions.https.HttpsError("invalid-argument", "Máximo 200 certificados por lote");
  }
  if (roleCaller !== "MASTER" && callerTenantId !== igrejaId) {
    throw new functions.https.HttpsError("permission-denied", "Sem permissão para outra igreja");
  }

  const db = admin.firestore();
  const bucket = admin.storage().bucket();

  const tenantSnap = await db.doc(`igrejas/${igrejaId}`).get();
  const tdata = tenantSnap.data() || {};
  const churchName = String(tdata.name || tdata.nome || "Igreja").trim();
  const cidade = String(tdata.cidade || "").trim();
  const estado = String(tdata.estado || "").trim();
  const localLine = cidade ? `${cidade}/${estado}` : "";

  const certSnap = await db.doc(`igrejas/${igrejaId}/config/certificados`).get();
  const certData = certSnap.data() || {};
  const templates = (certData.templates || {}) as Record<string, DocumentData>;
  const tcfg = templates[idAssinatura] || {};
  let textoModelo = String(tcfg.textoModelo || "").trim();
  let titulo = String(tcfg.titulo || "").trim();
  if (!textoModelo) textoModelo = TEXTO_MODELO_PADRAO[idAssinatura] || TEXTO_MODELO_PADRAO.batismo;
  if (!titulo) titulo = TITULO_PADRAO[idAssinatura] || "Certificado";

  const rawList = certData.defaultSignatoryMemberIds;
  const defaultSigIds: string[] = Array.isArray(rawList)
    ? rawList.map((x: unknown) => String(x || "").trim()).filter(Boolean)
    : [];
  const nSigCfg = Number(certData.defaultSignaturesCount);
  const sigCount = Math.max(
    1,
    Math.min(
      Number.isFinite(nSigCfg) && nSigCfg > 0 ? Math.floor(nSigCfg) : defaultSigIds.length || 1,
      defaultSigIds.length || 1,
    ),
  );
  const useDigital = String(certData.defaultSignatureMode || "digital").trim() !== "manual";

  let pastorNome = String(tdata.gestorNome || tdata.gestor_nome || "").trim();
  let pastorCargo = "Pastor(a) Presidente";
  const signatureBuffers: Buffer[] = [];

  for (const mid of defaultSigIds.slice(0, sigCount)) {
    const mSnap = await db.doc(`igrejas/${igrejaId}/membros/${mid}`).get();
    const md = mSnap.data() || {};
    const nome = String(md.NOME_COMPLETO || md.nome || "").trim();
    const cargo = cargoFromMemberData(md);
    if (!pastorNome && nome) pastorNome = nome;
    if (pastorCargo === "Pastor(a) Presidente" && cargo) pastorCargo = cargo;

    if (useDigital) {
      const raw = String(md.assinaturaUrl || md.assinatura_url || "").trim();
      if (raw) {
        const buf = await downloadImageBuffer(bucket, raw);
        if (buf) signatureBuffers.push(buf);
      }
    }
  }
  if (!pastorNome) pastorNome = "_______________________";

  const dh = dataHojeBr();
  const pageOpts: PageDrawOpts[] = [];

  for (const mid of memberIds) {
    const mSnap = await db.doc(`igrejas/${igrejaId}/membros/${mid}`).get();
    if (!mSnap.exists) continue;
    const md = mSnap.data() || {};
    const nome = String(md.NOME_COMPLETO || md.nome || "").trim();
    if (!nome) continue;
    const cpf = String(md.CPF || md.cpf || "").trim();
    const texto = fillTextoModelo(textoModelo, nome, cpf, dh);

    let memberPhotoJpeg: Buffer | null = null;
    const photoUrl = memberPhotoUrl(md);
    if (photoUrl) {
      const pbuf = await downloadImageBuffer(bucket, photoUrl);
      if (pbuf) memberPhotoJpeg = await sharpForPdfSlot(pbuf);
    }

    pageOpts.push({
      titulo,
      nome,
      texto,
      nomeIgreja: churchName,
      localLine,
      signatureImages: signatureBuffers,
      pastorNome,
      pastorCargo,
      memberPhotoJpeg,
    });
  }

  if (pageOpts.length === 0) {
    throw new functions.https.HttpsError("not-found", "Nenhum membro encontrado para os IDs informados");
  }

  const pdfBytes = await buildMultiPagePdfBuffer(pageOpts);
  const loteId = `${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
  const storagePath = `igrejas/${igrejaId}/certificados_lote/${loteId}.pdf`;
  const downloadToken = randomUUID();
  const file = bucket.file(storagePath);
  await file.save(pdfBytes, {
    metadata: {
      contentType: "application/pdf",
      cacheControl: "private, max-age=0",
      metadata: { firebaseStorageDownloadTokens: downloadToken },
    },
  });

  const downloadUrl = await firebaseDownloadUrlForPath(bucket, storagePath, downloadToken);

  return {
    ok: true,
    jobId: loteId,
    downloadUrl,
    pageCount: pageOpts.length,
  };
}

export const processarCertificadosLote = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 300, memory: "1GB" })
  .https.onCall(async (data, context) => {
    try {
      return await processarCertificadosLoteHandler(
        (data || {}) as Record<string, unknown>,
        context,
      );
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      const msg = e instanceof Error ? e.message : String(e);
      functions.logger.error("processarCertificadosLote: falha inesperada", {
        error: msg,
        stack: e instanceof Error ? e.stack : undefined,
        igrejaId: data?.igrejaId || data?.tenantId,
        count: Array.isArray(data?.listaMembrosId) ? data.listaMembrosId.length : 0,
      });
      throw new functions.https.HttpsError(
        "internal",
        `Falha ao gerar certificados em lote: ${msg}`,
      );
    }
  });
