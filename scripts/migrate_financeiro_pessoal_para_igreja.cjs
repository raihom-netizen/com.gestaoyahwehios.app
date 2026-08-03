/**
 * Migração one-shot (Admin SDK): Financeiro "pessoal" (users/{uid}/transactions
 * e users/{uid}/finance_accounts) → Financeiro "por igreja"
 * (igrejas/{churchId}/finance e igrejas/{churchId}/contas).
 *
 * Motivo: a tela Financeiro do painel grava hoje em users/{uid do login atual}/...,
 * então dois gestores da mesma igreja veem lançamentos diferentes um do outro.
 * O sistema por-igreja (igrejas/{churchId}/finance + contas) já existe, já tem
 * regras/índices publicados e já é usado por Fornecedores, conciliação OFX,
 * geração de despesas fixas e o motor de relatórios — este script traz para lá
 * o histórico que ainda está preso no login pessoal de cada usuário.
 *
 * Uso:
 *   node scripts/migrate_financeiro_pessoal_para_igreja.js                 (dry-run, todo mundo)
 *   node scripts/migrate_financeiro_pessoal_para_igreja.js --uid=<uid>     (dry-run, só um uid)
 *   node scripts/migrate_financeiro_pessoal_para_igreja.js --commit        (grava de verdade)
 *   node scripts/migrate_financeiro_pessoal_para_igreja.js --uid=<uid> --commit
 *
 * - Modo padrão é DRY-RUN: só imprime o que faria, não grava nada.
 * - churchId de cada uid é resolvido via users/{uid}.tenantId / .igrejaId
 *   (mesmo campo que firestore.rules já usa) — uid sem igreja resolvível é
 *   pulado e reportado, nunca "inventa" uma igreja.
 * - Não apaga users/{uid}/transactions (fonte) — a limpeza é manual, depois
 *   de conferir no Console que a migração ficou certa.
 * - Saldo das contas de destino é recalculado a partir dos lançamentos
 *   efetivados migrados (mesma regra de flutter_app/lib/core/finance_saldo_policy.dart).
 */

const admin = require("firebase-admin");
const path = require("path");

const args = process.argv.slice(2);
const commit = args.includes("--commit");
const uidArg = args.find((a) => a.startsWith("--uid="));
const onlyUid = uidArg ? uidArg.split("=")[1] : null;

function initAdmin() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
    return;
  }
  const sa = path.join(__dirname, "..", "secrets", "gestaoyahweh-21e23-7951f1817911.json");
  try {
    // eslint-disable-next-line import/no-dynamic-require, global-require
    admin.initializeApp({ credential: admin.credential.cert(require(sa)) });
  } catch {
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
  }
}
initAdmin();

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

// ---- Réplica fiel de flutter_app/lib/core/finance_infer_tipo.dart -------
// A origem (Financeiro pessoal) sempre grava `type` explícito ('income'/
// 'expense'), então o fallback rico do Dart (categoria/contaOrigemId etc.)
// não é necessário aqui — mantido simples de propósito.
function financeInferTipo(d) {
  const explicit = String(d.type ?? d.tipo ?? "").trim().toLowerCase();
  if (!explicit) return "entrada";
  if (explicit === "transferencia" || explicit === "transferência") return "transferencia";
  if (explicit.includes("entrada") || explicit.includes("receita") || explicit === "income") {
    return "entrada";
  }
  if (
    explicit.includes("saida") ||
    explicit.includes("saída") ||
    explicit.includes("despesa") ||
    explicit === "expense"
  ) {
    return "saida";
  }
  return explicit;
}

function parseValor(raw) {
  if (raw == null) return 0;
  if (typeof raw === "number") return raw;
  return parseFloat(String(raw).replace(",", ".")) || 0;
}

// finance_accounts.productType (pessoal) -> contas.tipoConta (igreja)
const PRODUCT_TYPE_TO_TIPO_CONTA = {
  checking: "corrente",
  savings: "poupanca",
  card: "cartao",
  bank_and_card: "corrente",
  vault: "caixa",
};

async function resolveChurchId(uid) {
  const userDoc = await db.collection("users").doc(uid).get();
  if (!userDoc.exists) return null;
  const d = userDoc.data() || {};
  const churchId = (d.tenantId || d.igrejaId || "").toString().trim();
  return churchId || null;
}

async function migrateAccountsForUid(uid, churchId, dryRun) {
  const accountsSnap = await db
    .collection("users")
    .doc(uid)
    .collection("finance_accounts")
    .get();
  let n = 0;
  for (const doc of accountsSnap.docs) {
    const d = doc.data() || {};
    const nome = (d.nickname || "").toString().trim() || `Conta ${doc.id.slice(0, 6)}`;
    const tipoConta = PRODUCT_TYPE_TO_TIPO_CONTA[d.productType] || "corrente";
    const destRef = db.collection("igrejas").doc(churchId).collection("contas").doc(doc.id);
    const destSnap = await destRef.get();
    n++;
    if (destSnap.exists) {
      console.log(`  [conta] igrejas/${churchId}/contas/${doc.id} já existe — mantido, id reaproveitado.`);
      continue;
    }
    console.log(`  [conta] users/${uid}/finance_accounts/${doc.id} ("${nome}") -> igrejas/${churchId}/contas/${doc.id}`);
    if (!dryRun) {
      await destRef.set(
        {
          nome,
          bancoCodigo: "",
          bancoNome: "",
          agencia: "",
          numeroConta: "",
          tipoConta,
          observacao: "Migrado do Financeiro pessoal.",
          ativo: true,
          saldo: 0,
          migratedFromUid: uid,
          createdAt: d.createdAt || FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
  }
  return n;
}

async function migrateTransactionsForUid(uid, churchId, dryRun) {
  const txSnap = await db.collection("users").doc(uid).collection("transactions").get();
  const saldoDelta = {};
  let n = 0;
  for (const doc of txSnap.docs) {
    const d = doc.data() || {};
    const tipo = financeInferTipo(d);
    const valor = parseValor(d.amount ?? d.valor);
    const status = (d.status || "").toString();

    const next = { ...d };
    delete next.scaleClosureDedupKey; // campo do agendamento pessoal, não existe no doc da igreja

    if (tipo === "entrada") {
      next.recebimentoConfirmado = status !== "pending";
      if (d.financeAccountId) next.contaDestinoId = d.financeAccountId;
    } else if (tipo === "saida") {
      next.pagamentoConfirmado = status !== "pending";
      if (d.financeAccountId) next.contaOrigemId = d.financeAccountId;
    }
    next.migratedFromUid = uid;
    next.migratedAt = FieldValue.serverTimestamp();

    n++;
    console.log(
      `  [lancamento] users/${uid}/transactions/${doc.id} (${tipo}, R$ ${valor.toFixed(2)}) -> igrejas/${churchId}/finance/${doc.id}`,
    );
    if (!dryRun) {
      await db
        .collection("igrejas")
        .doc(churchId)
        .collection("finance")
        .doc(doc.id)
        .set(next, { merge: true });
    }

    // Mesma regra de finance_saldo_policy.dart: transferência sempre efetiva;
    // entrada/saida só efetiva se não marcada explicitamente como pendente.
    const efetivado =
      tipo === "transferencia"
        ? true
        : tipo === "entrada"
          ? next.recebimentoConfirmado !== false
          : tipo === "saida"
            ? next.pagamentoConfirmado !== false
            : true;
    if (efetivado && valor > 0) {
      if (tipo === "entrada" && next.contaDestinoId) {
        saldoDelta[next.contaDestinoId] = (saldoDelta[next.contaDestinoId] || 0) + valor;
      } else if (tipo === "saida" && next.contaOrigemId) {
        saldoDelta[next.contaOrigemId] = (saldoDelta[next.contaOrigemId] || 0) - valor;
      }
    }
  }
  return { n, saldoDelta };
}

async function applySaldoDeltas(churchId, saldoDelta, dryRun) {
  for (const [contaId, delta] of Object.entries(saldoDelta)) {
    console.log(
      `  [saldo] igrejas/${churchId}/contas/${contaId}: ${delta >= 0 ? "+" : ""}${delta.toFixed(2)}`,
    );
    if (!dryRun) {
      const ref = db.collection("igrejas").doc(churchId).collection("contas").doc(contaId);
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) return;
        const atual = parseValor((snap.data() || {}).saldo);
        tx.update(ref, { saldo: atual + delta, updatedAt: FieldValue.serverTimestamp() });
      });
    }
  }
}

async function findUidsWithTransactions() {
  const uids = new Set();
  const cgSnap = await db.collectionGroup("transactions").get();
  for (const doc of cgSnap.docs) {
    const usersDoc = doc.ref.parent.parent; // users/{uid}
    if (usersDoc && usersDoc.parent.id === "users") {
      uids.add(usersDoc.id);
    }
  }
  return Array.from(uids);
}

async function main() {
  console.log(`Modo: ${commit ? "COMMIT (vai gravar)" : "DRY-RUN (não grava nada)"}`);

  const uids = onlyUid ? [onlyUid] : await findUidsWithTransactions();
  console.log(`Encontrados ${uids.length} login(s) com lançamentos pessoais.`);

  for (const uid of uids) {
    const churchId = await resolveChurchId(uid);
    if (!churchId) {
      console.log(`- uid ${uid}: sem churchId resolvível (users/${uid}.tenantId/igrejaId ausente) — PULADO.`);
      continue;
    }
    console.log(`\n=== uid ${uid} -> igreja ${churchId} ===`);
    const nContas = await migrateAccountsForUid(uid, churchId, !commit);
    const { n: nTx, saldoDelta } = await migrateTransactionsForUid(uid, churchId, !commit);
    await applySaldoDeltas(churchId, saldoDelta, !commit);
    console.log(`  Total: ${nContas} conta(s) tocada(s), ${nTx} lançamento(s).`);
  }

  console.log(
    `\n${commit ? "Migração aplicada." : "Dry-run concluído — nada foi gravado. Revise acima e rode de novo com --commit para aplicar."}`,
  );
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
