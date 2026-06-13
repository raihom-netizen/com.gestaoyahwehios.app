"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CHURCH_COLLECTION = void 0;
exports.churchDocRef = churchDocRef;
exports.churchUsersIndexRef = churchUsersIndexRef;
exports.churchMembrosRef = churchMembrosRef;
exports.legacyTenantDocRef = legacyTenantDocRef;
exports.readChurchRootData = readChurchRootData;
exports.readUsersIndexSnapshot = readUsersIndexSnapshot;
exports.CHURCH_COLLECTION = "igrejas";
function churchDocRef(db, churchId) {
    return db.collection(exports.CHURCH_COLLECTION).doc(String(churchId || "").trim());
}
function churchUsersIndexRef(db, churchId, docId) {
    return churchDocRef(db, churchId).collection("usersIndex").doc(String(docId || "").trim());
}
function churchMembrosRef(db, churchId, docId) {
    return churchDocRef(db, churchId).collection("membros").doc(String(docId || "").trim());
}
/** Legado — não gravar; só fallback de leitura enquanto existir lixo antigo. */
function legacyTenantDocRef(db, churchId) {
    return db.collection("tenants").doc(String(churchId || "").trim());
}
async function readChurchRootData(db, churchId) {
    const canonical = await churchDocRef(db, churchId).get();
    if (canonical.exists) {
        return (canonical.data() ?? {});
    }
    const legacy = await legacyTenantDocRef(db, churchId).get();
    return legacy.exists ? (legacy.data() ?? {}) : {};
}
async function readUsersIndexSnapshot(db, churchId, docId) {
    const canonical = await churchUsersIndexRef(db, churchId, docId).get();
    if (canonical.exists)
        return canonical;
    return legacyTenantDocRef(db, churchId).collection("usersIndex").doc(docId).get();
}
//# sourceMappingURL=churchFirestorePaths.js.map