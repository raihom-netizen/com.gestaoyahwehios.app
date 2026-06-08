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
exports.ensureConfiguracoesStorageFolder = ensureConfiguracoesStorageFolder;
exports.ensureFinanceiroStorageFolder = ensureFinanceiroStorageFolder;
const admin = __importStar(require("firebase-admin"));
/** PNG 1×1 transparente — materializa pastas vazias no bucket (igual ao app). */
const MIN_PLACEHOLDER_PNG = Buffer.from([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48,
    0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00,
    0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41, 0x54, 0x78,
    0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);
/** `igrejas/{tenantId}/configuracoes/logo_igreja.png` (placeholder mínimo se ausente). */
async function ensureConfiguracoesStorageFolder(tenantId) {
    const tid = String(tenantId || "").trim();
    if (!tid)
        return { created: false, path: "" };
    const bucket = admin.storage().bucket();
    const pngPath = `igrejas/${tid}/configuracoes/logo_igreja.png`;
    const jpgPath = `igrejas/${tid}/configuracoes/logo_igreja.jpg`;
    for (const path of [pngPath, jpgPath]) {
        const file = bucket.file(path);
        const [exists] = await file.exists();
        if (exists)
            return { created: false, path };
    }
    await bucket.file(pngPath).save(MIN_PLACEHOLDER_PNG, {
        contentType: "image/png",
        resumable: false,
        metadata: { cacheControl: "public,max-age=60" },
    });
    return { created: true, path: pngPath };
}
/** `igrejas/{tenantId}/financeiro/_structure/placeholder.png` */
async function ensureFinanceiroStorageFolder(tenantId) {
    const tid = String(tenantId || "").trim();
    if (!tid)
        return { created: false, path: "" };
    const path = `igrejas/${tid}/financeiro/_structure/placeholder.png`;
    const bucket = admin.storage().bucket();
    const file = bucket.file(path);
    const [exists] = await file.exists();
    if (exists)
        return { created: false, path };
    await file.save(MIN_PLACEHOLDER_PNG, {
        contentType: "image/png",
        resumable: false,
        metadata: { cacheControl: "public,max-age=60" },
    });
    return { created: true, path };
}
//# sourceMappingURL=churchStorageStructure.js.map