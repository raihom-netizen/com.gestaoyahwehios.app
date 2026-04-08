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
exports.gerarCertificadosEmLote = void 0;
/**
 * Gera ZIP com PDFs de certificados no servidor (lotes grandes).
 * Layout simplificado (texto + nome + igreja); assinaturas digitais como imagem quando configuradas.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const stream_1 = require("stream");
const https = __importStar(require("https"));
const http = __importStar(require("http"));
// eslint-disable-next-line @typescript-eslint/no-require-imports
const PDFDocument = require("pdfkit");
// eslint-disable-next-line @typescript-eslint/no-require-imports
const archiver = require("archiver");
function canEmitCertificatesRole(role) {
    const r = role.toUpperCase();
    return r === "MASTER" || r === "ADM" || r === "ADMIN" || r === "GESTOR";
}
function formatCpf(cpf) {
    const d = String(cpf || "").replace(/\D/g, "");
    if (d.length !== 11)
        return String(cpf || "");
    return `${d.slice(0, 3)}.${d.slice(3, 6)}.${d.slice(6, 9)}-${d.slice(9)}`;
}
function dataHojeBr() {
    const n = new Date();
    const dd = String(n.getDate()).padStart(2, "0");
    const mm = String(n.getMonth() + 1).padStart(2, "0");
    return `${dd}/${mm}/${n.getFullYear()}`;
}
/** Fallback quando Firestore não tem textoModelo do template. */
const TEXTO_MODELO_PADRAO = {
    batismo: "Certificamos que {NOME}, portador(a) do CPF {CPF}, foi batizado(a) nas águas conforme a ordenança bíblica de Mateus 28:19, nesta igreja, na data de {DATA_CERTIFICADO}.\n\nQue o Senhor abençoe e guarde os passos deste(a) irmão(ã) em sua caminhada cristã.",
    membro: "Certificamos que {NOME}, portador(a) do CPF {CPF}, é membro ativo desta igreja, tendo sido recebido(a) em nosso rol de membros.\n\nEste certificado é emitido para os devidos fins em {DATA_CERTIFICADO}.",
    apresentacao: "Certificamos que a criança {NOME} foi apresentada ao Senhor nesta igreja, em cerimônia realizada na data de {DATA_CERTIFICADO}, conforme o exemplo bíblico de Lucas 2:22.\n\nQue Deus abençoe e proteja esta criança e sua família.",
    casamento: "Certificamos que {NOME} contraiu matrimônio nesta igreja na data de {DATA_CERTIFICADO}, tendo a cerimônia sido celebrada conforme os preceitos cristãos.\n\nQue o Senhor abençoe este lar com amor, paz e fidelidade.",
    participacao: "Certificamos que {NOME} participou do evento/curso realizado por esta igreja na data de {DATA_CERTIFICADO}.\n\nAgradecemos sua presença e dedicação.",
    lideranca: "Certificamos que {NOME}, portador(a) do CPF {CPF}, exerce a função de líder nesta igreja, contribuindo para o crescimento espiritual da comunidade.\n\nEste certificado é emitido em {DATA_CERTIFICADO} como reconhecimento por sua dedicação.",
    conclusao_curso: "Certificamos que {NOME} concluiu com aproveitamento o curso ministrado por esta igreja na data de {DATA_CERTIFICADO}.\n\nParabéns pelo empenho e dedicação.",
};
const TITULO_PADRAO = {
    batismo: "Certificado de Batismo",
    membro: "Certificado de Membro",
    apresentacao: "Certificado de Apresentação",
    casamento: "Certificado de Casamento",
    participacao: "Certificado de Participação",
    lideranca: "Certificado de Liderança",
    conclusao_curso: "Certificado de Conclusão de Curso",
};
async function downloadUrlBuffer(url) {
    const u = String(url || "").trim();
    if (!u.startsWith("http"))
        return null;
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
                const chunks = [];
                res.on("data", (c) => chunks.push(c));
                res.on("end", () => {
                    const b = Buffer.concat(chunks);
                    resolve(b.length > 32 ? b : null);
                });
            })
                .on("error", () => resolve(null));
        }
        catch {
            resolve(null);
        }
    });
}
function cargoFromMemberData(md) {
    const c = String(md.cargo_lideranca || md.CARGO_LIDERANCA || md.cargo || md.CARGO || "")
        .trim();
    return c || "Líder";
}
function buildPdfBuffer(opts) {
    return new Promise((resolve, reject) => {
        const chunks = [];
        const doc = new PDFDocument({
            size: "A4",
            layout: "landscape",
            margin: 48,
        });
        doc.on("data", (c) => chunks.push(c));
        doc.on("error", reject);
        doc.on("end", () => resolve(Buffer.concat(chunks)));
        doc.fontSize(20).text(opts.titulo, { align: "center" });
        doc.moveDown(0.8);
        doc.fontSize(11).text(opts.texto, {
            align: "center",
            width: doc.page.width - 96,
        });
        doc.moveDown(1.2);
        doc.fontSize(14).text(opts.nomeIgreja, { align: "center" });
        if (opts.localLine) {
            doc.moveDown(0.3);
            doc.fontSize(10).fillColor("#666666").text(opts.localLine, { align: "center" });
            doc.fillColor("#000000");
        }
        doc.moveDown(1.5);
        const imgs = opts.signatureImages.filter(Boolean);
        if (imgs.length > 0) {
            const startY = doc.y;
            let x = 48;
            const slotW = (doc.page.width - 96) / Math.min(imgs.length, 3) - 8;
            for (let i = 0; i < Math.min(imgs.length, 3); i++) {
                try {
                    doc.image(imgs[i], x, startY, { fit: [Math.min(slotW, 120), 48] });
                }
                catch {
                    /* ignore bad image */
                }
                x += slotW + 16;
            }
            doc.y = startY + 56;
            doc.moveDown(0.5);
        }
        doc.fontSize(10).text(opts.pastorNome, { align: "center" });
        doc.fontSize(9).fillColor("#555555").text(opts.pastorCargo, { align: "center" });
        doc.end();
    });
}
async function zipBuffers(files) {
    return new Promise((resolve, reject) => {
        const passthrough = new stream_1.PassThrough();
        const chunks = [];
        passthrough.on("data", (c) => chunks.push(c));
        passthrough.on("end", () => resolve(Buffer.concat(chunks)));
        passthrough.on("error", reject);
        const archive = archiver("zip", { zlib: { level: 6 } });
        archive.on("error", reject);
        archive.pipe(passthrough);
        for (const f of files) {
            if (f.buffer.length > 0)
                archive.append(f.buffer, { name: f.name });
        }
        void archive.finalize();
    });
}
exports.gerarCertificadosEmLote = functions
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
    const tenantId = String(data?.tenantId || "").trim();
    const memberIds = Array.isArray(data?.memberIds)
        ? data.memberIds.map((x) => String(x || "").trim()).filter(Boolean)
        : [];
    const templateId = String(data?.templateId || "batismo").trim();
    if (!tenantId || memberIds.length === 0) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e memberIds são obrigatórios");
    }
    if (memberIds.length > 150) {
        throw new functions.https.HttpsError("invalid-argument", "Máximo 150 certificados por lote");
    }
    if (roleCaller !== "MASTER" && callerTenantId !== tenantId) {
        throw new functions.https.HttpsError("permission-denied", "Sem permissão para outra igreja");
    }
    const db = admin.firestore();
    const bucket = admin.storage().bucket();
    const tenantSnap = await db.doc(`igrejas/${tenantId}`).get();
    const tdata = tenantSnap.data() || {};
    const churchName = String(tdata.name || tdata.nome || "Igreja").trim();
    const cidade = String(tdata.cidade || "").trim();
    const estado = String(tdata.estado || "").trim();
    const localLine = cidade ? `${cidade}/${estado}` : "";
    const certSnap = await db.doc(`igrejas/${tenantId}/config/certificados`).get();
    const certData = certSnap.data() || {};
    const templates = (certData.templates || {});
    const tcfg = templates[templateId] || {};
    let textoModelo = String(tcfg.textoModelo || "").trim();
    let titulo = String(tcfg.titulo || "").trim();
    if (!textoModelo)
        textoModelo = TEXTO_MODELO_PADRAO[templateId] || TEXTO_MODELO_PADRAO.batismo;
    if (!titulo)
        titulo = TITULO_PADRAO[templateId] || "Certificado";
    const rawList = certData.defaultSignatoryMemberIds;
    const defaultSigIds = Array.isArray(rawList)
        ? rawList.map((x) => String(x || "").trim()).filter(Boolean)
        : [];
    const nSigCfg = Number(certData.defaultSignaturesCount);
    const sigCount = Math.max(1, Math.min(Number.isFinite(nSigCfg) && nSigCfg > 0 ? Math.floor(nSigCfg) : defaultSigIds.length || 1, defaultSigIds.length || 1));
    const useDigital = String(certData.defaultSignatureMode || "digital").trim() !== "manual";
    let pastorNome = String(tdata.gestorNome || tdata.gestor_nome || "").trim();
    let pastorCargo = "Pastor(a) Presidente";
    const signatureBuffers = [];
    const idsToLoad = defaultSigIds.slice(0, sigCount);
    for (const mid of idsToLoad) {
        const mSnap = await db.doc(`igrejas/${tenantId}/membros/${mid}`).get();
        const md = mSnap.data() || {};
        const nome = String(md.NOME_COMPLETO || md.nome || "").trim();
        const cargo = cargoFromMemberData(md);
        if (!pastorNome && nome)
            pastorNome = nome;
        if (pastorCargo === "Pastor(a) Presidente" && cargo)
            pastorCargo = cargo;
        if (useDigital) {
            const raw = String(md.assinaturaUrl || md.assinatura_url || "").trim();
            if (raw) {
                const buf = await downloadUrlBuffer(raw);
                if (buf)
                    signatureBuffers.push(buf);
            }
        }
    }
    if (!pastorNome)
        pastorNome = "_______________________";
    const dh = dataHojeBr();
    const pdfFiles = [];
    for (const mid of memberIds) {
        const mSnap = await db.doc(`igrejas/${tenantId}/membros/${mid}`).get();
        if (!mSnap.exists)
            continue;
        const md = mSnap.data() || {};
        const nome = String(md.NOME_COMPLETO || md.nome || "Membro").trim();
        const cpf = String(md.CPF || md.cpf || "").trim();
        const texto = textoModelo
            .split("{NOME}")
            .join(nome)
            .split("{CPF}")
            .join(formatCpf(cpf))
            .split("{DATA_CERTIFICADO}")
            .join(dh);
        const safeStub = mid.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 40) || "membro";
        const pdfBuf = await buildPdfBuffer({
            titulo,
            texto,
            nomeIgreja: churchName,
            localLine,
            signatureImages: signatureBuffers,
            pastorNome,
            pastorCargo,
        });
        pdfFiles.push({ name: `certificado_${safeStub}.pdf`, buffer: pdfBuf });
    }
    if (pdfFiles.length === 0) {
        throw new functions.https.HttpsError("not-found", "Nenhum membro encontrado para os IDs informados");
    }
    const zipBuffer = await zipBuffers(pdfFiles);
    const jobId = `${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    const storagePath = `igrejas/${tenantId}/certificados_lote/${jobId}.zip`;
    const file = bucket.file(storagePath);
    await file.save(zipBuffer, {
        metadata: {
            contentType: "application/zip",
            cacheControl: "private, max-age=0",
        },
    });
    const [downloadUrl] = await file.getSignedUrl({
        action: "read",
        expires: Date.now() + 7 * 24 * 3600 * 1000,
    });
    return {
        ok: true,
        jobId,
        downloadUrl,
        count: pdfFiles.length,
    };
});
//# sourceMappingURL=certificadosLote.js.map