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
exports.gerarCarteirinhaPdf = exports.gerarCertificadoPdf = void 0;
/**
 * Geração de PDF no servidor — certificado individual e carteirinha premium.
 * Evita trabalho pesado no telemóvel/Web (pilar #9).
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
const https = __importStar(require("https"));
const http = __importStar(require("http"));
// eslint-disable-next-line @typescript-eslint/no-require-imports
const PDFDocument = require("pdfkit");
// eslint-disable-next-line @typescript-eslint/no-require-imports
const QRCode = require("qrcode");
const tenantCallableResolve_1 = require("./tenantCallableResolve");
const PUBLIC_WEB_BASE = "https://gestaoyahweh.com.br";
function canEmitCertificatesRole(role) {
    const r = role.toUpperCase();
    return (r === "MASTER" ||
        r === "ADM" ||
        r === "ADMIN" ||
        r === "GESTOR" ||
        r === "PASTOR" ||
        r === "SECRETARIO" ||
        r === "SECRETÁRIO");
}
function canEmitCarteirinhaRole(role) {
    return canEmitCertificatesRole(role) || role.toUpperCase() === "LIDER";
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
                if (res.statusCode &&
                    res.statusCode >= 300 &&
                    res.statusCode < 400 &&
                    res.headers.location) {
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
async function downloadStoragePathBuffer(storagePath) {
    const p = String(storagePath || "").trim().replace(/^\/+/, "");
    if (!p)
        return null;
    try {
        const bucket = admin.storage().bucket();
        const [buf] = await bucket.file(p).download();
        return buf.length > 32 ? buf : null;
    }
    catch {
        return null;
    }
}
async function qrPngBuffer(text) {
    try {
        return await QRCode.toBuffer(text, {
            type: "png",
            margin: 1,
            width: 180,
            errorCorrectionLevel: "M",
        });
    }
    catch {
        return null;
    }
}
function cargoFromMemberData(md) {
    const c = String(md.cargo_lideranca || md.CARGO_LIDERANCA || md.cargo || md.CARGO || "").trim();
    return c || "Membro";
}
function departamentoFromMemberData(md) {
    const d = String(md.departamento ||
        md.DEPARTAMENTO ||
        md.department ||
        md.departmentName ||
        "").trim();
    return d;
}
function carteiraValidityLabel(md) {
    const perm = md.CARTEIRA_PERMANENTE === true ||
        String(md.CARTEIRA_PERMANENTE || "").toLowerCase() === "true";
    if (perm)
        return "Permanente";
    const v = md.CARTEIRA_VALIDADE;
    if (v && typeof v.toDate === "function") {
        try {
            const d = v.toDate();
            if (d && !Number.isNaN(d.getTime())) {
                const dd = String(d.getDate()).padStart(2, "0");
                const mm = String(d.getMonth() + 1).padStart(2, "0");
                return `${dd}/${mm}/${d.getFullYear()}`;
            }
        }
        catch {
            /* ignore */
        }
    }
    return "—";
}
function buildCertificatePdfBuffer(opts) {
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
            doc
                .fontSize(10)
                .fillColor("#666666")
                .text(opts.localLine, { align: "center" });
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
        doc
            .fontSize(9)
            .fillColor("#555555")
            .text(opts.pastorCargo, { align: "center" });
        doc.fillColor("#000000");
        if (opts.qrUrl) {
            void qrPngBuffer(opts.qrUrl).then((qr) => {
                if (qr) {
                    try {
                        const qrSize = 72;
                        doc.image(qr, doc.page.width - 48 - qrSize, 48, {
                            fit: [qrSize, qrSize],
                        });
                    }
                    catch {
                        /* ignore */
                    }
                }
                doc.end();
            });
            return;
        }
        doc.end();
    });
}
async function buildCarteirinhaPdfBuffer(opts) {
    const qr = await qrPngBuffer(opts.qrUrl);
    return new Promise((resolve, reject) => {
        const chunks = [];
        const doc = new PDFDocument({
            size: [340, 214],
            margin: 14,
        });
        doc.on("data", (c) => chunks.push(c));
        doc.on("error", reject);
        doc.on("end", () => resolve(Buffer.concat(chunks)));
        doc.roundedRect(0, 0, 340, 214, 12).lineWidth(1).stroke("#E2E8F0");
        doc.fontSize(8).fillColor("#64748B").text("GESTÃO YAHWEH", 14, 12);
        doc.fontSize(9).fillColor("#0F172A").text(opts.nomeIgreja, 14, 24, {
            width: 200,
            ellipsis: true,
        });
        const photoX = 14;
        const photoY = 44;
        const photoW = 72;
        const photoH = 88;
        doc.roundedRect(photoX, photoY, photoW, photoH, 8).fill("#F1F5F9");
        if (opts.photo) {
            try {
                doc.image(opts.photo, photoX + 2, photoY + 2, {
                    fit: [photoW - 4, photoH - 4],
                    align: "center",
                    valign: "center",
                });
            }
            catch {
                doc.fillColor("#94A3B8").fontSize(8).text("Sem foto", photoX + 18, photoY + 40);
            }
        }
        else {
            doc.fillColor("#94A3B8").fontSize(8).text("Sem foto", photoX + 22, photoY + 40);
        }
        const tx = 96;
        doc.fillColor("#0F172A").fontSize(11).text(opts.nome, tx, 48, { width: 170 });
        doc.fillColor("#475569").fontSize(8).text(`Cargo: ${opts.cargo}`, tx, 78, { width: 170 });
        doc.text(`Departamento: ${opts.departamento || "—"}`, tx, 92, { width: 170 });
        doc.text(`Validade: ${opts.validade}`, tx, 106, { width: 170 });
        if (qr) {
            try {
                doc.image(qr, 250, 130, { fit: [72, 72] });
            }
            catch {
                /* ignore */
            }
        }
        doc.fillColor("#94A3B8").fontSize(6).text("Carteirinha digital — valide pelo QR", 14, 198);
        doc.end();
    });
}
async function uploadPdfAndSign(storagePath, buffer) {
    const bucket = admin.storage().bucket();
    const file = bucket.file(storagePath);
    await file.save(buffer, {
        metadata: {
            contentType: "application/pdf",
            cacheControl: "private, max-age=0",
        },
    });
    const [downloadUrl] = await file.getSignedUrl({
        action: "read",
        expires: Date.now() + 24 * 3600 * 1000,
    });
    return { storagePath, downloadUrl };
}
function certificadoValidationUrl(certificadoId) {
    const cid = String(certificadoId || "").trim();
    return `${PUBLIC_WEB_BASE}/#/validar?cid=${encodeURIComponent(cid)}`;
}
function carteirinhaValidationUrl(tenantId, memberId) {
    const q = new URLSearchParams({
        tenantId: tenantId.trim(),
        memberId: memberId.trim(),
    }).toString();
    return `${PUBLIC_WEB_BASE}/carteirinha-validar?${q}`;
}
async function loadCertificateConfig(db, tenantId, templateId) {
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
    return {
        churchName,
        localLine,
        textoModelo,
        titulo,
        pastorNome,
        pastorCargo,
        signatureBuffers,
    };
}
/** Certificado individual — PDF no Storage + URL assinada (24 h). */
exports.gerarCertificadoPdf = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 120, memory: "512MB" })
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessário");
    }
    const roleCaller = String(context.auth.token?.role || "").toUpperCase();
    if (!canEmitCertificatesRole(roleCaller)) {
        throw new functions.https.HttpsError("permission-denied", "Acesso restrito a gestores");
    }
    const tenantId = await (0, tenantCallableResolve_1.resolveTenantIdForCallable)({ uid: context.auth.uid, token: context.auth.token }, String(data?.tenantId || ""));
    const memberId = String(data?.memberId || "").trim();
    const templateId = String(data?.templateId || "batismo").trim();
    const certificadoId = String(data?.certificadoId || "").trim();
    if (!tenantId || !memberId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e memberId são obrigatórios");
    }
    const db = admin.firestore();
    const mSnap = await db.doc(`igrejas/${tenantId}/membros/${memberId}`).get();
    if (!mSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Membro não encontrado");
    }
    const md = mSnap.data() || {};
    const nome = String(md.NOME_COMPLETO || md.nome || "Membro").trim();
    const cpf = String(md.CPF || md.cpf || "").trim();
    const cfg = await loadCertificateConfig(db, tenantId, templateId);
    const dh = dataHojeBr();
    const texto = cfg.textoModelo
        .split("{NOME}")
        .join(nome)
        .split("{CPF}")
        .join(formatCpf(cpf))
        .split("{DATA_CERTIFICADO}")
        .join(dh);
    const certId = certificadoId ||
        `${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
    const qrUrl = certificadoValidationUrl(certId);
    const pdfBuf = await buildCertificatePdfBuffer({
        titulo: cfg.titulo,
        texto,
        nomeIgreja: cfg.churchName,
        localLine: cfg.localLine,
        signatureImages: cfg.signatureBuffers,
        pastorNome: cfg.pastorNome,
        pastorCargo: cfg.pastorCargo,
        qrUrl,
    });
    const safeStub = memberId.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 40) || "membro";
    const storagePath = `igrejas/${tenantId}/certificados_emitidos/${certId}_${safeStub}.pdf`;
    const uploaded = await uploadPdfAndSign(storagePath, pdfBuf);
    return {
        ok: true,
        certificadoId: certId,
        memberId,
        templateId,
        storagePath: uploaded.storagePath,
        downloadUrl: uploaded.downloadUrl,
        qrValidationUrl: qrUrl,
    };
});
/** Carteirinha premium individual — PDF no Storage + URL assinada (24 h). */
exports.gerarCarteirinhaPdf = functions
    .region("us-central1")
    .runWith({ timeoutSeconds: 120, memory: "512MB" })
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessário");
    }
    const roleCaller = String(context.auth.token?.role || "").toUpperCase();
    if (!canEmitCarteirinhaRole(roleCaller)) {
        throw new functions.https.HttpsError("permission-denied", "Sem permissão para emitir carteirinha");
    }
    const tenantId = await (0, tenantCallableResolve_1.resolveTenantIdForCallable)({ uid: context.auth.uid, token: context.auth.token }, String(data?.tenantId || ""));
    const memberId = String(data?.memberId || "").trim();
    if (!tenantId || !memberId) {
        throw new functions.https.HttpsError("invalid-argument", "tenantId e memberId são obrigatórios");
    }
    const db = admin.firestore();
    const [tenantSnap, memberSnap] = await Promise.all([
        db.doc(`igrejas/${tenantId}`).get(),
        db.doc(`igrejas/${tenantId}/membros/${memberId}`).get(),
    ]);
    if (!memberSnap.exists) {
        throw new functions.https.HttpsError("not-found", "Membro não encontrado");
    }
    const tdata = tenantSnap.data() || {};
    const md = memberSnap.data() || {};
    const churchName = String(tdata.name || tdata.nome || "Igreja").trim();
    const nome = String(md.NOME_COMPLETO || md.nome || "Membro").trim();
    const cargo = cargoFromMemberData(md);
    const departamento = departamentoFromMemberData(md);
    const validade = carteiraValidityLabel(md);
    let photo = null;
    const photoPath = String(md.fotoStoragePath ||
        md.photoStoragePath ||
        md.fotoPath ||
        md.imageStoragePath ||
        "").trim();
    if (photoPath) {
        photo = await downloadStoragePathBuffer(photoPath);
    }
    if (!photo) {
        const photoUrl = String(md.foto_url || md.fotoUrl || md.photoURL || md.photoUrl || "").trim();
        if (photoUrl)
            photo = await downloadUrlBuffer(photoUrl);
    }
    const qrUrl = carteirinhaValidationUrl(tenantId, memberId);
    const pdfBuf = await buildCarteirinhaPdfBuffer({
        nomeIgreja: churchName,
        nome,
        cargo,
        departamento,
        validade,
        photo,
        qrUrl,
    });
    const safeStub = memberId.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 40) || "membro";
    const storagePath = `igrejas/${tenantId}/membros/carteirinhas/${safeStub}.pdf`;
    const uploaded = await uploadPdfAndSign(storagePath, pdfBuf);
    return {
        ok: true,
        memberId,
        storagePath: uploaded.storagePath,
        downloadUrl: uploaded.downloadUrl,
        qrValidationUrl: qrUrl,
    };
});
//# sourceMappingURL=churchPdfGeneration.js.map