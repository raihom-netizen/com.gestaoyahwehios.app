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
exports.onIgrejaVisitanteDeleteCleanupFirestore = exports.onIgrejaFinanceiroDeleteCleanupFirestore = exports.onIgrejaPatrimonioDeleteCleanupFirestore = exports.onIgrejaOracaoDeleteCleanupFirestore = exports.onIgrejaFornecedorDeleteCleanupFirestore = exports.onIgrejaAgendaDeleteCleanupFirestore = exports.onIgrejaMuralAvisoDeleteCleanupFirestore = exports.onIgrejaNoticiaDeleteCleanupFirestore = exports.onIgrejaEventoDeleteCleanupFirestore = exports.onIgrejaAvisoDeleteCleanupFirestore = exports.onIgrejaMembroDeleteCleanupFirestore = void 0;
/**
 * Limpa subcoleções abaixo de documentos operacionais excluídos.
 * A exclusão do documento pai no Firestore não remove subcoleções automaticamente.
 */
const functions = __importStar(require("firebase-functions/v1"));
const admin = __importStar(require("firebase-admin"));
async function deleteChildren(snap, context) {
    try {
        await admin.firestore().recursiveDelete(snap.ref);
        functions.logger.info("Subcoleções removidas após exclusão", {
            path: snap.ref.path,
            tenantId: context.params.tenantId,
            docId: context.params.docId,
        });
    }
    catch (error) {
        functions.logger.error("Falha ao limpar subcoleções após exclusão", {
            path: snap.ref.path,
            error,
        });
        throw error;
    }
}
exports.onIgrejaMembroDeleteCleanupFirestore = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/membros/{docId}")
    .onDelete(deleteChildren);
exports.onIgrejaAvisoDeleteCleanupFirestore = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/avisos/{docId}")
    .onDelete(deleteChildren);
exports.onIgrejaEventoDeleteCleanupFirestore = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/eventos/{docId}")
    .onDelete(deleteChildren);
exports.onIgrejaNoticiaDeleteCleanupFirestore = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/noticias/{docId}")
    .onDelete(deleteChildren);
exports.onIgrejaMuralAvisoDeleteCleanupFirestore = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/mural_avisos/{docId}")
    .onDelete(deleteChildren);
exports.onIgrejaAgendaDeleteCleanupFirestore = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/agenda/{docId}")
    .onDelete(deleteChildren);
exports.onIgrejaFornecedorDeleteCleanupFirestore = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/fornecedores/{docId}")
    .onDelete(deleteChildren);
exports.onIgrejaOracaoDeleteCleanupFirestore = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/pedidosOracao/{docId}")
    .onDelete(deleteChildren);
exports.onIgrejaPatrimonioDeleteCleanupFirestore = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/patrimonio/{docId}")
    .onDelete(deleteChildren);
exports.onIgrejaFinanceiroDeleteCleanupFirestore = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/financeiro/{docId}")
    .onDelete(deleteChildren);
exports.onIgrejaVisitanteDeleteCleanupFirestore = functions
    .region("us-central1")
    .firestore.document("igrejas/{tenantId}/visitantes/{docId}")
    .onDelete(deleteChildren);
//# sourceMappingURL=recursiveDeleteOnFirestoreDelete.js.map