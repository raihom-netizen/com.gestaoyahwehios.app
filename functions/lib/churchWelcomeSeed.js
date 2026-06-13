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
 * Kit oficial: 11 departamentos + 6 cargos + módulos financeiro/visitantes — espelho de
 * flutter_app/lib/core/department_template.dart,
 * flutter_app/lib/ui/pages/cargos_page.dart (_welcomeCargos),
 * flutter_app/lib/services/finance_despesas_categorias_tenant.dart (categorias).
 * Idempotente: só grava se subcoleções estiverem vazias / doc ainda não existir.
 */
const admin = __importStar(require("firebase-admin"));
const churchMercadoPago_1 = require("./churchMercadoPago");
const panelDashboardCache_1 = require("./panelDashboardCache");
const panelFinanceSummary_1 = require("./panelFinanceSummary");
const panelStatisticsCache_1 = require("./panelStatisticsCache");
/** Categorias padrão — alinhadas ao Flutter (`kCategoriasDespesaPadrao`). */
const CATEGORIAS_DESPESA_PADRAO = [
    "Água",
    "Ajuda Social",
    "Energia Elétrica",
    "Eventos",
    "Impostos",
    "Internet",
    "Investimentos em Mídia",
    "Manutenção",
    "Material de Limpeza",
    "Oferta Missionária",
    "Pagamento de Obreiros",
    "Prebenda",
    "Salários",
    "Material de Escritório",
    "Transporte",
    "Alimentação",
    "Outros",
];
/** Categorias receita — alinhadas a `finance_page.dart` (_categoriasReceitaPadrao). */
const CATEGORIAS_RECEITA_PADRAO = [
    "Aluguéis Recebidos",
    "Dízimos",
    "Doações",
    "Inscrições em Eventos",
    "Ofertas Missionárias",
    "Ofertas Voluntárias",
    "Vendas de Produtos",
    "Campanhas",
    "Outros",
];
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
function categoriaDocId(nome) {
    return ("welcome_" +
        String(nome || "")
            .normalize("NFD")
            .replace(/[\u0300-\u036f]/g, "")
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, "_")
            .replace(/^_|_$/g, "")
            .slice(0, 48));
}
/** Registo canónico — `igrejas/{id}/_tenant_modules/{modulo}`. */
async function ensureTenantModuleRegistry(churchRef, tenantId, now) {
    const registered = [];
    const modCol = churchRef.collection("_tenant_modules");
    const modules = [
        {
            id: "finance",
            collection: "finance",
            storageSubpath: "financeiro/",
            extra: {
                contasCollection: "contas",
                configDoc: "config/finance_settings",
                categoriasDespesa: "categorias_despesas",
                categoriasReceita: "categorias_receitas",
            },
        },
        {
            id: "visitantes",
            collection: "visitantes",
            extra: { followupsSubcollection: "followups" },
        },
    ];
    for (const mod of modules) {
        const ref = modCol.doc(mod.id);
        const snap = await ref.get();
        if (snap.exists)
            continue;
        await ref.set({
            enabled: true,
            module: mod.id,
            collection: mod.collection,
            firestorePath: `igrejas/${tenantId}/${mod.collection}`,
            storagePath: mod.storageSubpath
                ? `igrejas/${tenantId}/${mod.storageSubpath}`
                : "",
            isWelcomeKit: true,
            provisionedAt: now,
            schemaVersion: 1,
            ...(mod.extra ?? {}),
        }, { merge: true });
        registered.push(mod.id);
    }
    return registered;
}
async function ensureFinanceSettingsSeed(churchRef, now) {
    const ref = churchRef.collection("config").doc("finance_settings");
    const snap = await ref.get();
    if (snap.exists)
        return false;
    await ref.set({
        limiteAprovacaoDespesa: 0,
        orcamentosDespesa: {},
        isWelcomeKit: true,
        createdAt: now,
        updatedAt: now,
    }, { merge: true });
    return true;
}
async function seedCategoriasIfEmpty(churchRef, collectionId, nomes, now) {
    const col = churchRef.collection(collectionId);
    const probe = await col.limit(1).get();
    if (!probe.empty)
        return 0;
    const batch = churchRef.firestore.batch();
    let n = 0;
    for (let i = 0; i < nomes.length; i++) {
        const nome = nomes[i];
        batch.set(col.doc(categoriaDocId(nome)), {
            nome,
            ordem: i,
            isWelcomeKit: true,
            isDefaultPreset: true,
            createdAt: now,
            updatedAt: now,
        });
        n++;
    }
    if (n > 0)
        await batch.commit();
    return n;
}
async function ensureChurchModuleDefaults(_firestore, tenantId, churchRef, now) {
    const tenantModulesRegistered = await ensureTenantModuleRegistry(churchRef, tenantId, now);
    const financeSettingsCreated = await ensureFinanceSettingsSeed(churchRef, now);
    const categoriasDespesaCreated = await seedCategoriasIfEmpty(churchRef, "categorias_despesas", CATEGORIAS_DESPESA_PADRAO, now);
    const categoriasReceitaCreated = await seedCategoriasIfEmpty(churchRef, "categorias_receitas", CATEGORIAS_RECEITA_PADRAO, now);
    try {
        await (0, panelFinanceSummary_1.recomputePanelFinanceSummary)(tenantId);
    }
    catch (e) {
        console.warn("ensureChurchModuleDefaults recomputePanelFinanceSummary:", e);
    }
    try {
        await (0, panelDashboardCache_1.recomputePanelDashboardSummary)(tenantId);
    }
    catch (e) {
        console.warn("ensureChurchModuleDefaults recomputePanelDashboardSummary:", e);
    }
    try {
        await (0, panelStatisticsCache_1.writePanelStatisticsCache)(tenantId, {
            membersTotalCount: 0,
            activeMembersCount: 0,
            pendingMembersCount: 0,
            newVisitorsCount: 0,
            openPrayerRequestsCount: 0,
            birthdaysTodayCount: 0,
            birthdaysWeekCount: 0,
            birthdaysMonthCount: 0,
            avisosCount: 0,
            eventsCount: 0,
            upcomingEventsCount: 0,
            departmentsCount: 0,
        });
    }
    catch (e) {
        console.warn("ensureChurchModuleDefaults writePanelStatisticsCache:", e);
    }
    return {
        financeSettingsCreated,
        categoriasDespesaCreated,
        categoriasReceitaCreated,
        tenantModulesRegistered,
    };
}
async function ensureChurchWelcomeSeed(firestore, tenantId) {
    const empty = {
        departmentsCreated: 0,
        cargosCreated: 0,
        financeSettingsCreated: false,
        categoriasDespesaCreated: 0,
        categoriasReceitaCreated: 0,
        tenantModulesRegistered: [],
    };
    const tid = String(tenantId || "").trim();
    if (!tid)
        return empty;
    const churchRef = firestore.collection("igrejas").doc(tid);
    const churchSnap = await churchRef.get();
    if (!churchSnap.exists) {
        console.warn(`ensureChurchWelcomeSeed: igrejas/${tid} inexistente — ignorado.`);
        return empty;
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
    try {
        const contasN = await (0, churchMercadoPago_1.ensureDefaultTreasuryContasForNewChurch)(tid);
        if (contasN > 0) {
            console.log(`ensureChurchWelcomeSeed: ${contasN} conta(s) tesouraria em igrejas/${tid}/contas`);
        }
    }
    catch (e) {
        console.warn("ensureChurchWelcomeSeed ensureDefaultTreasuryContasForNewChurch:", e);
    }
    let moduleDefaults = {
        financeSettingsCreated: false,
        categoriasDespesaCreated: 0,
        categoriasReceitaCreated: 0,
        tenantModulesRegistered: [],
    };
    try {
        moduleDefaults = await ensureChurchModuleDefaults(firestore, tid, churchRef, now);
        if (moduleDefaults.tenantModulesRegistered.length > 0) {
            console.log(`ensureChurchWelcomeSeed: módulos registados ${moduleDefaults.tenantModulesRegistered.join(", ")} em igrejas/${tid}/_tenant_modules`);
        }
        if (moduleDefaults.financeSettingsCreated) {
            console.log(`ensureChurchWelcomeSeed: config/finance_settings criado em igrejas/${tid}`);
        }
        if (moduleDefaults.categoriasDespesaCreated > 0) {
            console.log(`ensureChurchWelcomeSeed: ${moduleDefaults.categoriasDespesaCreated} categorias_despesas em igrejas/${tid}`);
        }
        if (moduleDefaults.categoriasReceitaCreated > 0) {
            console.log(`ensureChurchWelcomeSeed: ${moduleDefaults.categoriasReceitaCreated} categorias_receitas em igrejas/${tid}`);
        }
    }
    catch (e) {
        console.warn("ensureChurchWelcomeSeed ensureChurchModuleDefaults:", e);
    }
    return {
        departmentsCreated,
        cargosCreated,
        financeSettingsCreated: moduleDefaults.financeSettingsCreated,
        categoriasDespesaCreated: moduleDefaults.categoriasDespesaCreated,
        categoriasReceitaCreated: moduleDefaults.categoriasReceitaCreated,
        tenantModulesRegistered: moduleDefaults.tenantModulesRegistered,
    };
}
//# sourceMappingURL=churchWelcomeSeed.js.map