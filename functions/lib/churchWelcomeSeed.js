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
exports.ensureChurchWelcomeSeed = ensureChurchWelcomeSeed;
/**
 * Kit oficial: 11 departamentos + 6 cargos — espelho de
 * flutter_app/lib/core/department_template.dart e
 * flutter_app/lib/ui/pages/cargos_page.dart (_welcomeCargos).
 * Idempotente: só grava se subcoleções estiverem vazias.
 */
const admin = __importStar(require("firebase-admin"));
const churchMercadoPago_1 = require("./churchMercadoPago");
const WELCOME_DEPARTMENTS = [
    { docId: "pastoral", name: "Pastoral", iconKey: "pastoral", bgColor1: 0xff0d47a1, bgColor2: 0xff1976d2, description: "Direção espiritual e pastoreio", sortOrder: 0 },
    { docId: "louvor", name: "Louvor", iconKey: "louvor", bgColor1: 0xffff6f00, bgColor2: 0xffffa726, description: "Adoração e ministério de música", sortOrder: 1 },
    { docId: "jovens", name: "Jovens", iconKey: "jovens", bgColor1: 0xffff5722, bgColor2: 0xffff7043, description: "Ministério com jovens", sortOrder: 2 },
    { docId: "criancas", name: "Crianças", iconKey: "criancas", bgColor1: 0xff00acc1, bgColor2: 0xff4dd0e1, description: "Ministério infantil", sortOrder: 3 },
    { docId: "evangelismo", name: "Evangelismo", iconKey: "evangelismo", bgColor1: 0xff6a1b9a, bgColor2: 0xffab47bc, description: "Alcance e novos convertidos", sortOrder: 4 },
    { docId: "intercessao", name: "Intercessão", iconKey: "intercessao", bgColor1: 0xffe53935, bgColor2: 0xffff5252, description: "Oração e intercessão", sortOrder: 5 },
    { docId: "media", name: "Mídia", iconKey: "media", bgColor1: 0xff1565c0, bgColor2: 0xff42a5f5, description: "Som, imagem e comunicação digital", sortOrder: 6 },
    { docId: "recepcao", name: "Recepção", iconKey: "recepcao", bgColor1: 0xffff9800, bgColor2: 0xffffb74d, description: "Boas-vindas e acolhimento", sortOrder: 7 },
    { docId: "finance", name: "Financeiro", iconKey: "finance", bgColor1: 0xff37474f, bgColor2: 0xff546e7a, description: "Recursos e tesouraria", sortOrder: 8 },
    { docId: "escola_biblica", name: "Escola Bíblica", iconKey: "escola_biblica", bgColor1: 0xff00695c, bgColor2: 0xff26a69a, description: "Ensino da Palavra e EBD", sortOrder: 9 },
    { docId: "varoes", name: "Varões", iconKey: "varoes", bgColor1: 0xff283593, bgColor2: 0xff3f51b5, description: "Ministério com homens", sortOrder: 10 },
];
const WELCOME_CARGOS = [
    { docId: "welcome_pastor_presidente", name: "Pastor Presidente / Administrador", key: "pastor_presidente", permissionTemplate: "pastor_presidente", hierarchyLevel: 100, accentColor: 0xff1565c0, requiresConsecrationDate: true },
    { docId: "welcome_pastor_auxiliar", name: "Pastor Auxiliar / Ministerial", key: "pastor_auxiliar", permissionTemplate: "pastor_auxiliar", hierarchyLevel: 88, accentColor: 0xff5e35b1, requiresConsecrationDate: true },
    { docId: "welcome_secretario", name: "Secretário(a)", key: "secretario", permissionTemplate: "secretario", hierarchyLevel: 72, accentColor: 0xff00897b, requiresConsecrationDate: false },
    { docId: "welcome_tesoureiro", name: "Tesoureiro(a)", key: "tesoureiro", permissionTemplate: "tesoureiro", hierarchyLevel: 65, accentColor: 0xff2e7d32, requiresConsecrationDate: false },
    { docId: "welcome_lider_departamento", name: "Líder de Departamento", key: "lider_departamento", permissionTemplate: "lider_departamento", hierarchyLevel: 55, accentColor: 0xff6a1b9a, requiresConsecrationDate: false },
    { docId: "welcome_membro", name: "Membro / Congregado", key: "membro", permissionTemplate: "membro", hierarchyLevel: 12, accentColor: 0xff78909c, requiresConsecrationDate: false },
];
async function ensureChurchWelcomeSeed(firestore, tenantId) {
    const tid = String(tenantId || "").trim();
    if (!tid)
        return { departmentsCreated: 0, cargosCreated: 0 };
    const churchRef = firestore.collection("igrejas").doc(tid);
    const churchSnap = await churchRef.get();
    if (!churchSnap.exists) {
        console.warn(`ensureChurchWelcomeSeed: igrejas/${tid} inexistente — ignorado.`);
        return { departmentsCreated: 0, cargosCreated: 0 };
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    let departmentsCreated = 0;
    let cargosCreated = 0;
    const deptCol = churchRef.collection("departamentos");
    const deptProbe = await deptCol.limit(1).get();
    if (deptProbe.empty) {
        const batch = firestore.batch();
        for (const d of WELCOME_DEPARTMENTS) {
            batch.set(deptCol.doc(d.docId), {
                name: d.name,
                description: d.description,
                iconKey: d.iconKey,
                themeKey: d.iconKey,
                bgColor1: d.bgColor1,
                bgColor2: d.bgColor2,
                bgImageUrl: "",
                leaderCpfs: [],
                leaderCpf: "",
                viceLeaderCpf: "",
                leaderUid: "",
                permissions: [],
                createdAt: now,
                updatedAt: now,
                active: true,
                isDefaultPreset: true,
                isWelcomeKit: true,
                welcomeKitOrder: d.sortOrder,
            });
            departmentsCreated++;
        }
        await batch.commit();
        console.log(`ensureChurchWelcomeSeed: ${departmentsCreated} departamento(s) em igrejas/${tid}/departamentos`);
    }
    const cargosCol = churchRef.collection("cargos");
    const cargoProbe = await cargosCol.limit(1).get();
    if (cargoProbe.empty) {
        const batch = firestore.batch();
        for (let i = 0; i < WELCOME_CARGOS.length; i++) {
            const c = WELCOME_CARGOS[i];
            batch.set(cargosCol.doc(c.docId), {
                name: c.name,
                key: c.key,
                permissionTemplate: c.permissionTemplate,
                hierarchyLevel: c.hierarchyLevel,
                accentColor: c.accentColor,
                requiresConsecrationDate: c.requiresConsecrationDate,
                order: i,
                isDefaultPreset: true,
                isWelcomeKit: true,
                modulePermissions: [],
                createdAt: now,
                updatedAt: now,
            });
            cargosCreated++;
        }
        await batch.commit();
        console.log(`ensureChurchWelcomeSeed: ${cargosCreated} cargo(s) em igrejas/${tid}/cargos`);
    }
    try {
        const ok = await (0, churchMercadoPago_1.ensureMercadoPagoContaForNewChurch)(tid);
        if (ok) {
            console.log(`ensureChurchWelcomeSeed: conta Mercado Pago criada em igrejas/${tid}/contas/mercado_pago`);
        }
    }
    catch (e) {
        console.warn("ensureChurchWelcomeSeed ensureMercadoPagoContaForNewChurch:", e);
    }
    return { departmentsCreated, cargosCreated };
}
//# sourceMappingURL=churchWelcomeSeed.js.map