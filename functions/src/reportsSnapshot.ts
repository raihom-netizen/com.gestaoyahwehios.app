/**
 * Bundle de dados para o módulo Relatórios — Admin SDK, 1 round-trip na Web.
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import type { DocumentData, QueryDocumentSnapshot } from "firebase-admin/firestore";
import { resolveTenantIdForCallable } from "./tenantCallableResolve";

const DEFAULT_LIMITS = {
  membros: 800,
  eventos: 250,
  finance: 500,
  patrimonio: 200,
} as const;

type ModuleKey = "membros" | "eventos" | "finance" | "patrimonio";

function pickString(data: DocumentData, keys: string[]): string {
  for (const k of keys) {
    const v = data[k];
    if (v != null && String(v).trim()) return String(v).trim();
  }
  return "";
}

function memberRow(doc: QueryDocumentSnapshot): Record<string, unknown> {
  const d = doc.data();
  return {
    id: doc.id,
    NOME_COMPLETO: pickString(d, ["NOME_COMPLETO", "nome", "name"]),
    nome: pickString(d, ["nome", "NOME_COMPLETO", "name"]),
    EMAIL: pickString(d, ["EMAIL", "email"]),
    email: pickString(d, ["email", "EMAIL"]),
    TELEFONES: pickString(d, ["TELEFONES", "TELEFONE", "telefone"]),
    telefone: pickString(d, ["telefone", "TELEFONES"]),
    CPF: pickString(d, ["CPF", "cpf"]),
    cpf: pickString(d, ["cpf", "CPF"]),
    STATUS: pickString(d, ["STATUS", "status"]),
    status: pickString(d, ["status", "STATUS"]),
    SEXO: pickString(d, ["SEXO", "sexo", "genero"]),
    FUNCAO: pickString(d, ["FUNCAO", "funcao", "CARGO", "cargo"]),
    CARGO: pickString(d, ["CARGO", "cargo", "FUNCAO"]),
    FUNCOES: d.FUNCOES ?? d.funcoes ?? [],
    DEPARTAMENTOS: d.DEPARTAMENTOS ?? d.departamentos ?? [],
    DATA_NASCIMENTO: d.DATA_NASCIMENTO ?? d.dataNascimento ?? null,
    dataNascimento: d.dataNascimento ?? d.DATA_NASCIMENTO ?? null,
    fotoUrl: pickString(d, ["fotoUrl", "photoUrl", "FOTO_URL_OU_ID"]),
    assinaturaUrl: pickString(d, ["assinaturaUrl", "assinatura_url"]),
  };
}

function eventoRow(doc: QueryDocumentSnapshot): Record<string, unknown> {
  const d = doc.data();
  const startAt = d.startAt ?? d.dataEvento ?? d.createdAt ?? null;
  return {
    id: doc.id,
    title: pickString(d, ["title", "titulo"]) || "Evento",
    titulo: pickString(d, ["titulo", "title"]),
    type: pickString(d, ["type", "tipo"]) || "evento",
    startAt,
    dataEvento: d.dataEvento ?? startAt,
    location: pickString(d, ["location", "local"]),
    local: pickString(d, ["local", "location"]),
    rsvp: Array.isArray(d.rsvp) ? d.rsvp : [],
    likes: Array.isArray(d.likes) ? d.likes : [],
  };
}

function financeRow(doc: QueryDocumentSnapshot): Record<string, unknown> {
  const d = doc.data();
  return {
    id: doc.id,
    ...d,
    createdAt: d.createdAt ?? d.data ?? null,
    valor: d.valor ?? d.amount ?? 0,
    amount: d.amount ?? d.valor ?? 0,
    tipo: d.tipo ?? d.type ?? "",
    type: d.type ?? d.tipo ?? "",
    categoria: d.categoria ?? "",
    descricao: d.descricao ?? d.anotacoes ?? "",
  };
}

function patrimonioRow(doc: QueryDocumentSnapshot): Record<string, unknown> {
  const d = doc.data();
  return { id: doc.id, ...d };
}

export const getRelatoriosBundle = functions
  .region("us-central1")
  .runWith({ timeoutSeconds: 60, memory: "512MB" })
  .https.onCall(async (request, context) => {
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Login necessario");
    }
    const body = (request || {}) as Record<string, unknown>;
    const tenantId = await resolveTenantIdForCallable(
      {
        uid: context.auth.uid,
        token: context.auth.token as Record<string, unknown>,
      },
      String(body.tenantId || ""),
    );
    if (!tenantId) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "igrejaId ausente",
      );
    }

    const modulesRaw = body.modules;
    const modules: ModuleKey[] = Array.isArray(modulesRaw)
      ? (modulesRaw as string[]).filter((m): m is ModuleKey =>
          ["membros", "eventos", "finance", "patrimonio"].includes(m),
        )
      : (["membros", "eventos", "finance", "patrimonio"] as ModuleKey[]);

    const membrosLimit = Math.min(
      Number(body.membrosLimit) || DEFAULT_LIMITS.membros,
      DEFAULT_LIMITS.membros,
    );
    const eventosLimit = Math.min(
      Number(body.eventosLimit) || DEFAULT_LIMITS.eventos,
      DEFAULT_LIMITS.eventos,
    );
    const financeLimit = Math.min(
      Number(body.financeLimit) || DEFAULT_LIMITS.finance,
      DEFAULT_LIMITS.finance,
    );
    const patrimonioLimit = Math.min(
      Number(body.patrimonioLimit) || DEFAULT_LIMITS.patrimonio,
      DEFAULT_LIMITS.patrimonio,
    );

    const db = admin.firestore();
    const churchRef = db.collection("igrejas").doc(tenantId);

    const out: Record<string, unknown> = {
      ok: true,
      tenantId,
      membros: [] as Record<string, unknown>[],
      eventos: [] as Record<string, unknown>[],
      finance: [] as Record<string, unknown>[],
      patrimonio: [] as Record<string, unknown>[],
    };

    const tasks: Promise<void>[] = [];

    if (modules.includes("membros")) {
      tasks.push(
        churchRef
          .collection("membros")
          .limit(membrosLimit)
          .get()
          .then((snap) => {
            out.membros = snap.docs.map(memberRow);
          }),
      );
    }

    if (modules.includes("eventos")) {
      tasks.push(
        churchRef
          .collection("eventos")
          .limit(eventosLimit)
          .get()
          .then((snap) => {
            out.eventos = snap.docs.map(eventoRow);
          }),
      );
    }

    if (modules.includes("finance")) {
      tasks.push(
        churchRef
          .collection("finance")
          .limit(financeLimit)
          .get()
          .then(async (snap) => {
            if (snap.docs.length > 0) {
              out.finance = snap.docs.map(financeRow);
              return;
            }
            const legacy = await churchRef
              .collection("financeiro")
              .limit(financeLimit)
              .get();
            out.finance = legacy.docs.map(financeRow);
          }),
      );
    }

    if (modules.includes("patrimonio")) {
      tasks.push(
        churchRef
          .collection("patrimonio")
          .limit(patrimonioLimit)
          .get()
          .then((snap) => {
            out.patrimonio = snap.docs.map(patrimonioRow);
          }),
      );
    }

    await Promise.all(tasks);

    functions.logger.info("getRelatoriosBundle", {
      tenantId,
      modules,
      membros: (out.membros as unknown[]).length,
      eventos: (out.eventos as unknown[]).length,
      finance: (out.finance as unknown[]).length,
      patrimonio: (out.patrimonio as unknown[]).length,
    });

    return out;
  });
