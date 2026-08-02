/**
 * Agregados mensais do Financeiro pessoal (paridade Controle Total).
 * users/{uid}/finance_month_buckets/{yyyy-MM} → { netPaid, updatedAt }
 * users/{uid}/finance_account_month_buckets/{yyyy-MM} → { netByAccount, updatedAt }
 * Timezone: America/Sao_Paulo.
 */
import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";

type TxData = FirebaseFirestore.DocumentData;

function monthKeyBr(ts: FirebaseFirestore.Timestamp | null | undefined): string {
  if (!ts || typeof ts.toDate !== "function") return "1970-01";
  const d = ts.toDate();
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Sao_Paulo",
    year: "numeric",
    month: "2-digit",
  });
  const parts = fmt.formatToParts(d);
  const y = parts.find((p) => p.type === "year")?.value || "1970";
  const m = parts.find((p) => p.type === "month")?.value || "01";
  return `${y}-${m}`;
}

function openingContribution(data: TxData | null | undefined): number {
  if (!data) return 0;
  const isPaid = (data.status || "paid").toString() === "paid";
  if (!isPaid) return 0;
  const type = (data.type || "expense").toString();
  const amount = Number(data.amount) || 0;
  if (type === "income") return amount;
  return -Math.abs(amount);
}

function effectiveTs(data: TxData | null | undefined): FirebaseFirestore.Timestamp | null {
  if (!data) return null;
  if (data.effectiveDate && typeof data.effectiveDate.toDate === "function") {
    return data.effectiveDate as FirebaseFirestore.Timestamp;
  }
  if (data.paidAt && typeof data.paidAt.toDate === "function") {
    return data.paidAt as FirebaseFirestore.Timestamp;
  }
  if (data.date && typeof data.date.toDate === "function") {
    return data.date as FirebaseFirestore.Timestamp;
  }
  return null;
}

function safeAccountFieldId(accountId: string): string {
  return accountId.replace(/\./g, "\uFF0E");
}

async function applyMonthBucketDelta(
  userId: string,
  before: TxData | null,
  after: TxData | null,
): Promise<void> {
  const bEff = before ? effectiveTs(before) : null;
  const aEff = after ? effectiveTs(after) : null;
  const bC = before ? openingContribution(before) : 0;
  const aC = after ? openingContribution(after) : 0;
  const bKey = bEff ? monthKeyBr(bEff) : null;
  const aKey = aEff ? monthKeyBr(aEff) : null;

  const db = admin.firestore();
  const inc = admin.firestore.FieldValue.increment;
  const ts = admin.firestore.FieldValue.serverTimestamp();

  if (bKey && aKey && bKey === aKey) {
    const net = aC - bC;
    if (net !== 0) {
      await db.doc(`users/${userId}/finance_month_buckets/${bKey}`).set(
        { netPaid: inc(net), updatedAt: ts },
        { merge: true },
      );
    }
    return;
  }
  if (bKey && bC !== 0) {
    await db.doc(`users/${userId}/finance_month_buckets/${bKey}`).set(
      { netPaid: inc(-bC), updatedAt: ts },
      { merge: true },
    );
  }
  if (aKey && aC !== 0) {
    await db.doc(`users/${userId}/finance_month_buckets/${aKey}`).set(
      { netPaid: inc(aC), updatedAt: ts },
      { merge: true },
    );
  }
}

async function bumpAccountMonthNet(
  userId: string,
  monthKey: string,
  accountId: string,
  delta: number,
): Promise<void> {
  if (!monthKey || !accountId || delta === 0) return;
  const db = admin.firestore();
  const field = safeAccountFieldId(accountId);
  await db.doc(`users/${userId}/finance_account_month_buckets/${monthKey}`).set(
    {
      [`netByAccount.${field}`]: admin.firestore.FieldValue.increment(delta),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

function accountBucketDelta(data: TxData | null | undefined): {
  accountId: string | null;
  delta: number;
} {
  if (!data) return { accountId: null, delta: 0 };
  const isPaid = (data.status || "paid").toString() === "paid";
  if (!isPaid) return { accountId: null, delta: 0 };
  const type = (data.type || "expense").toString();
  const amount = Math.abs(Number(data.amount) || 0);
  if (amount <= 0) return { accountId: null, delta: 0 };
  const paidFrom = ((data.paidFromFinanceAccountId || "") + "").trim();
  const accountId = ((data.financeAccountId || "") + "").trim();
  if (paidFrom && type === "expense") {
    return { accountId: paidFrom, delta: -amount };
  }
  if (!accountId) return { accountId: null, delta: 0 };
  return { accountId, delta: openingContribution(data) };
}

async function applyAccountMonthBucketDelta(
  userId: string,
  before: TxData | null,
  after: TxData | null,
): Promise<void> {
  const bEff = before ? effectiveTs(before) : null;
  const aEff = after ? effectiveTs(after) : null;
  const bKey = bEff ? monthKeyBr(bEff) : null;
  const aKey = aEff ? monthKeyBr(aEff) : null;
  const bSlot = accountBucketDelta(before);
  const aSlot = accountBucketDelta(after);

  if (
    bKey &&
    aKey &&
    bKey === aKey &&
    bSlot.accountId &&
    aSlot.accountId &&
    bSlot.accountId === aSlot.accountId
  ) {
    const net = aSlot.delta - bSlot.delta;
    if (net !== 0) await bumpAccountMonthNet(userId, bKey, bSlot.accountId, net);
    return;
  }
  if (bKey && bSlot.accountId && bSlot.delta !== 0) {
    await bumpAccountMonthNet(userId, bKey, bSlot.accountId, -bSlot.delta);
  }
  if (aKey && aSlot.accountId && aSlot.delta !== 0) {
    await bumpAccountMonthNet(userId, aKey, aSlot.accountId, aSlot.delta);
  }
}

async function applyAllBucketDeltas(
  userId: string,
  before: TxData | null,
  after: TxData | null,
): Promise<void> {
  await applyMonthBucketDelta(userId, before, after);
  await applyAccountMonthBucketDelta(userId, before, after);
}

/** Mantém buckets sincronizados a cada create/update/delete de lançamento. */
export const financeMonthBucketsOnTransactionWrite = functions
  .region("us-central1")
  .runWith({ memory: "256MB" })
  .firestore.document("users/{userId}/transactions/{txId}")
  .onWrite(async (change, context) => {
    const userId = context.params.userId as string;
    const before = change.before.exists ? (change.before.data() as TxData) : null;
    const after = change.after.exists ? (change.after.data() as TxData) : null;
    try {
      await applyAllBucketDeltas(userId, before, after);
    } catch (e: any) {
      console.error(
        "financeMonthBucketsOnTransactionWrite",
        userId,
        e?.message || e,
      );
    }
  });

/**
 * Reconstrói buckets a partir de todos os lançamentos do usuário autenticado.
 * Chamável após deploy/migração (idempotente).
 */
export const gyFinanceRebuildOpeningBuckets = functions
  .region("us-central1")
  .runWith({ memory: "512MB", timeoutSeconds: 300 })
  .https.onCall(async (_data, context) => {
    if (!context.auth?.uid) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Login obrigatório.",
      );
    }
    const uid = context.auth.uid;
    const db = admin.firestore();
    const monthSums = new Map<string, number>();
    const accountMonthSums = new Map<string, Map<string, number>>();

    const txCol = db.collection(`users/${uid}/transactions`);
    let last: FirebaseFirestore.QueryDocumentSnapshot | null = null;
    for (;;) {
      let q: FirebaseFirestore.Query = txCol.orderBy("date", "asc").limit(400);
      if (last) q = q.startAfter(last);
      const snap = await q.get();
      if (snap.empty) break;
      for (const doc of snap.docs) {
        const d = doc.data() as TxData;
        const eff = effectiveTs(d);
        if (!eff) continue;
        const k = monthKeyBr(eff);
        const c = openingContribution(d);
        monthSums.set(k, (monthSums.get(k) || 0) + c);
        const slot = accountBucketDelta(d);
        if (slot.accountId && slot.delta !== 0) {
          if (!accountMonthSums.has(k)) accountMonthSums.set(k, new Map());
          const m = accountMonthSums.get(k)!;
          m.set(slot.accountId, (m.get(slot.accountId) || 0) + slot.delta);
        }
      }
      last = snap.docs[snap.docs.length - 1];
      if (snap.size < 400) break;
    }

    const monthEntries = [...monthSums.entries()];
    for (let i = 0; i < monthEntries.length; i += 400) {
      const batch = db.batch();
      const chunk = monthEntries.slice(i, i + 400);
      for (const [k, v] of chunk) {
        batch.set(
          db.doc(`users/${uid}/finance_month_buckets/${k}`),
          {
            netPaid: v,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
      await batch.commit();
    }

    const accountMonthEntries = [...accountMonthSums.entries()];
    for (let i = 0; i < accountMonthEntries.length; i += 200) {
      const batch = db.batch();
      const chunk = accountMonthEntries.slice(i, i + 200);
      for (const [monthKey, accMap] of chunk) {
        const netByAccount: Record<string, number> = {};
        for (const [acc, val] of accMap.entries()) {
          netByAccount[safeAccountFieldId(acc)] = val;
        }
        batch.set(
          db.doc(`users/${uid}/finance_account_month_buckets/${monthKey}`),
          {
            netByAccount,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
      await batch.commit();
    }

    await db.doc(`users/${uid}/finance_stats/meta`).set(
      {
        openingBucketsVersion: 3,
        openingBucketsRebuiltAt: admin.firestore.FieldValue.serverTimestamp(),
        monthCount: monthSums.size,
      },
      { merge: true },
    );

    return { ok: true, months: monthSums.size };
  });
