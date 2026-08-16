/**
 * Limpa subcoleções abaixo de documentos operacionais excluídos.
 * A exclusão do documento pai no Firestore não remove subcoleções automaticamente.
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

async function deleteChildren(
  snap: FirebaseFirestore.DocumentSnapshot,
  context: functions.EventContext,
): Promise<void> {
  try {
    await admin.firestore().recursiveDelete(snap.ref);
    functions.logger.info("Subcoleções removidas após exclusão", {
      path: snap.ref.path,
      tenantId: context.params.tenantId,
      docId: context.params.docId,
    });
  } catch (error) {
    functions.logger.error("Falha ao limpar subcoleções após exclusão", {
      path: snap.ref.path,
      error,
    });
    throw error;
  }
}

export const onIgrejaMembroDeleteCleanupFirestore = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/membros/{docId}")
  .onDelete(deleteChildren);

export const onIgrejaAvisoDeleteCleanupFirestore = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/avisos/{docId}")
  .onDelete(deleteChildren);

export const onIgrejaEventoDeleteCleanupFirestore = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/eventos/{docId}")
  .onDelete(deleteChildren);

export const onIgrejaNoticiaDeleteCleanupFirestore = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/noticias/{docId}")
  .onDelete(deleteChildren);

export const onIgrejaMuralAvisoDeleteCleanupFirestore = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/mural_avisos/{docId}")
  .onDelete(deleteChildren);

export const onIgrejaAgendaDeleteCleanupFirestore = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/agenda/{docId}")
  .onDelete(deleteChildren);

export const onIgrejaFornecedorDeleteCleanupFirestore = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/fornecedores/{docId}")
  .onDelete(deleteChildren);

export const onIgrejaOracaoDeleteCleanupFirestore = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/pedidosOracao/{docId}")
  .onDelete(deleteChildren);

export const onIgrejaPatrimonioDeleteCleanupFirestore = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/patrimonio/{docId}")
  .onDelete(deleteChildren);

export const onIgrejaFinanceiroDeleteCleanupFirestore = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/financeiro/{docId}")
  .onDelete(deleteChildren);

export const onIgrejaVisitanteDeleteCleanupFirestore = functions
  .region("us-central1")
  .firestore.document("igrejas/{tenantId}/visitantes/{docId}")
  .onDelete(deleteChildren);
