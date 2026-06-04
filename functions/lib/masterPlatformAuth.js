"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.isPlatformOperatorToken = isPlatformOperatorToken;
/** Alinhado a `firestore.rules` → isPlatformOperator / isAdminPanel. */
function isPlatformOperatorToken(token) {
    if (!token)
        return false;
    const email = String(token.email ?? "").trim().toLowerCase();
    if (email === "raihom@gmail.com")
        return true;
    const role = String(token.role ?? token.ROLE ?? "").toUpperCase();
    return role === "MASTER" || role === "ADM" || role === "ADMIN";
}
//# sourceMappingURL=masterPlatformAuth.js.map