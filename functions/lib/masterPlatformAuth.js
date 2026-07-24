"use strict";
/** Alinhado a AppConstants + firestore.rules → isPlatformOperator / isAdminPanel. */
Object.defineProperty(exports, "__esModule", { value: true });
exports.PLATFORM_MASTER_UIDS = exports.PLATFORM_MASTER_EMAILS = void 0;
exports.isPlatformMasterEmail = isPlatformMasterEmail;
exports.isPlatformMasterUid = isPlatformMasterUid;
exports.isPlatformOperatorToken = isPlatformOperatorToken;
exports.PLATFORM_MASTER_EMAILS = [
    'raihom@gmail.com',
    'isabellecardoso@gmail.com',
    'isabelle.cardoso@gmail.com',
];
/** UIDs Auth conhecidos dos operadores SaaS (escudo Painel Master). */
exports.PLATFORM_MASTER_UIDS = [
    'O0qRLmLER2hwBFqvlzqSdtAUC3D3', // raihom@gmail.com
    'PljAYp6FBuWlGNl69Q2vnRp6gZh2', // isabellecardoso@gmail.com
];
function isPlatformMasterEmail(email) {
    const e = String(email ?? '').trim().toLowerCase();
    return exports.PLATFORM_MASTER_EMAILS.includes(e);
}
function isPlatformMasterUid(uid) {
    const u = String(uid ?? '').trim();
    return exports.PLATFORM_MASTER_UIDS.includes(u);
}
/** Token Auth + UID opcional — operador SaaS (não confundir com ADM local da igreja). */
function isPlatformOperatorToken(token, uid) {
    if (isPlatformMasterUid(uid))
        return true;
    if (!token)
        return false;
    if (isPlatformMasterEmail(token.email))
        return true;
    const role = String(token.role ?? token.ROLE ?? '').toUpperCase();
    // Só MASTER de plataforma nos claims — ADM/ADMIN da igreja NÃO são SaaS.
    return role === 'MASTER';
}
//# sourceMappingURL=masterPlatformAuth.js.map