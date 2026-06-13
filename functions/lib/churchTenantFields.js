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
exports.tenantFieldsPatch = tenantFieldsPatch;
exports.withTenantFieldsStamp = withTenantFieldsStamp;
exports.needsTenantFieldsStamp = needsTenantFieldsStamp;
const admin = __importStar(require("firebase-admin"));
/** Campos canónicos — espelho de `flutter_app/lib/core/data/church_tenant_fields.dart`. */
function tenantFieldsPatch(churchId, includeTimestamp = true) {
    const id = String(churchId || "").trim();
    const patch = {
        churchId: id,
        tenantId: id,
    };
    if (includeTimestamp) {
        patch.tenantFieldsStampedAt = admin.firestore.FieldValue.serverTimestamp();
    }
    return patch;
}
function withTenantFieldsStamp(churchId, data) {
    const id = String(churchId || "").trim();
    if (!id)
        return data;
    return { ...data, churchId: id, tenantId: id };
}
function needsTenantFieldsStamp(data, churchId) {
    const id = String(churchId || "").trim();
    if (!id)
        return false;
    const d = data ?? {};
    return String(d.churchId ?? "").trim() !== id || String(d.tenantId ?? "").trim() !== id;
}
//# sourceMappingURL=churchTenantFields.js.map