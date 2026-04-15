/**
 * Lote na nuvem: um único PDF (pdf-lib), fotos via Storage/HTTP + sharp (~300 dpi no slot),
 * grava em temporario/{loteId}.pdf e devolve URL assinada.
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import type { Bucket } from "@google-cloud/storage";
import type { DocumentData } from "firebase-admin/firestore";
import { PDFDocument, StandardFonts, rgb } from "pdf-lib";
import sharp from "sharp";
import * as https from "https";
import * as http from "http";

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

/** Caminho no bucket a partir de URL do Firebase Storage (download). */
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

/** ~300 dpi em slot de ~3" na página: borda longa ~900 px. */
async function sharpForPdfSlot(buf: Buffer): Promise<Uint8Array | null> {
  try {
    const out = await sharp(buf)
      .rotate()
      .resize({
        width: 900,
        height: 900,
        fit: "inside",
        withoutEnlargement: false,
      })
      .jpeg({ quality: 88, chromaSubsampling: "4:4:4", mozjpeg: true })
      .toBuffer();
    return new Uint8Array(out);
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

export const processarCertificadosLote = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 300, memory: "1GB" })
  .https.onCall(async (data, context) => {
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
        "igrejaId (ou tenantId) e listaMembrosId (ou memberIds) são obrigatórios"
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

    const templateStoragePath = String(certData.pdfTemplateStoragePath || certData.certPdfTemplatePath || "").trim();

    let templateDoc: PDFDocument | null = null;
    if (templateStoragePath) {
      try {
        const [tbytes] = await bucket.file(templateStoragePath).download();
        if (tbytes.length > 200) {
          templateDoc = await PDFDocument.load(tbytes);
        }
      } catch {
        templateDoc = null;
      }
    }

    const rawList = certData.defaultSignatoryMemberIds;
    const defaultSigIds: string[] = Array.isArray(rawList)
      ? rawList.map((x: unknown) => String(x || "").trim()).filter(Boolean)
      : [];
    const nSigCfg = Number(certData.defaultSignaturesCount);
    const sigCount = Math.max(
      1,
      Math.min(
        Number.isFinite(nSigCfg) && nSigCfg > 0 ? Math.floor(nSigCfg) : defaultSigIds.length || 1,
        defaultSigIds.length || 1
      )
    );
    const useDigital = String(certData.defaultSignatureMode || "digital").trim() !== "manual";

    let pastorNome = String(tdata.gestorNome || tdata.gestor_nome || "").trim();
    let pastorCargo = "Pastor(a) Presidente";
    const signatureJpegs: Uint8Array[] = [];

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
          if (buf) {
            const j = await sharpForPdfSlot(buf);
            if (j) signatureJpegs.push(j);
          }
        }
      }
    }
    if (!pastorNome) pastorNome = "_______________________";

    const dh = dataHojeBr();
    const outDoc = await PDFDocument.create();
    const fontBold = await outDoc.embedFont(StandardFonts.HelveticaBold);
    const font = await outDoc.embedFont(StandardFonts.Helvetica);

    let pagesAdded = 0;
    const W = 842;
    const H = 595;

    for (const mid of memberIds) {
      const mSnap = await db.doc(`igrejas/${igrejaId}/membros/${mid}`).get();
      if (!mSnap.exists) continue;
      const md = mSnap.data() || {};
      const nome = String(md.NOME_COMPLETO || md.nome || "Membro").trim();
      const cpf = String(md.CPF || md.cpf || "").trim();
      const texto = fillTextoModelo(textoModelo, nome, cpf, dh);

      let page;
      if (templateDoc && templateDoc.getPageCount() > 0) {
        const [copied] = await outDoc.copyPages(templateDoc, [0]);
        outDoc.addPage(copied);
        const pages = outDoc.getPages();
        page = pages[pages.length - 1];
      } else {
        page = outDoc.addPage([W, H]);
        page.drawRectangle({
          x: 36,
          y: 36,
          width: W - 72,
          height: H - 72,
          borderColor: rgb(0.15, 0.35, 0.65),
          borderWidth: 2,
        });
      }

      const { width, height } = page.getSize();

      page.drawText(titulo, {
        x: 50,
        y: height - 72,
        size: 20,
        font: fontBold,
        color: rgb(0.1, 0.2, 0.45),
        maxWidth: width - 100,
      });

      page.drawText(texto, {
        x: 50,
        y: height - 200,
        size: 11,
        font,
        color: rgb(0.15, 0.15, 0.15),
        maxWidth: width - 100,
        lineHeight: 14,
      });

      page.drawText(nome, {
        x: 50,
        y: height - 130,
        size: 16,
        font: fontBold,
        color: rgb(0, 0, 0),
        maxWidth: width - 100,
      });

      page.drawText(churchName, {
        x: 50,
        y: 120,
        size: 13,
        font: fontBold,
        color: rgb(0.1, 0.2, 0.45),
        maxWidth: width - 100,
      });

      if (localLine) {
        page.drawText(localLine, {
          x: 50,
          y: 100,
          size: 10,
          font,
          color: rgb(0.35, 0.35, 0.35),
        });
      }

      const photoUrl = memberPhotoUrl(md);
      if (photoUrl) {
        const pbuf = await downloadImageBuffer(bucket, photoUrl);
        if (pbuf) {
          const jpg = await sharpForPdfSlot(pbuf);
          if (jpg) {
            try {
              const img = await outDoc.embedJpg(jpg);
              const iw = 72;
              const ih = 72;
              page.drawImage(img, {
                x: width - 36 - iw,
                y: height - 36 - ih,
                width: iw,
                height: ih,
              });
            } catch {
              /* ignore */
            }
          }
        }
      }

      let sigX = width / 2 - Math.min(signatureJpegs.length, 3) * 55;
      for (let si = 0; si < Math.min(signatureJpegs.length, 3); si++) {
        try {
          const img = await outDoc.embedJpg(signatureJpegs[si]);
          page.drawImage(img, {
            x: sigX + si * 110,
            y: 52,
            width: 90,
            height: 36,
          });
        } catch {
          /* ignore */
        }
      }

      page.drawText(pastorNome, {
        x: 50,
        y: 40,
        size: 10,
        font: fontBold,
        color: rgb(0, 0, 0),
        maxWidth: width - 100,
      });
      page.drawText(pastorCargo, {
        x: 50,
        y: 26,
        size: 9,
        font,
        color: rgb(0.3, 0.3, 0.3),
        maxWidth: width - 100,
      });

      pagesAdded += 1;
    }

    if (pagesAdded === 0) {
      throw new functions.https.HttpsError("not-found", "Nenhum membro encontrado para os IDs informados");
    }

    const pdfBytes = await outDoc.save();
    const loteId = `${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    const storagePath = `temporario/${loteId}.pdf`;
    const file = bucket.file(storagePath);
    await file.save(Buffer.from(pdfBytes), {
      metadata: {
        contentType: "application/pdf",
        cacheControl: "private, max-age=0",
      },
    });

    const [downloadUrl] = await file.getSignedUrl({
      action: "read",
      expires: Date.now() + 7 * 24 * 3600 * 1000,
    });

    return {
      ok: true,
      jobId: loteId,
      downloadUrl,
      pageCount: pagesAdded,
    };
  });
