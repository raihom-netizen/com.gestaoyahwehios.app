/**
 * Remove utilizadores Firebase Auth **somente anónimos** (686+ no projeto).
 * Mantém Gmail, Apple, e-mail/senha e telefone.
 *
 * Simular (não apaga):
 *   node scripts/purge-anonymous-auth-users.js --dry-run
 *
 * Apagar de verdade:
 *   node scripts/purge-anonymous-auth-users.js --execute
 *
 * Credenciais: gcloud auth application-default login
 * ou GOOGLE_APPLICATION_CREDENTIALS apontando para service account.
 */

const admin = require("firebase-admin");

const projectId =
  process.env.GCLOUD_PROJECT ||
  process.env.GOOGLE_CLOUD_PROJECT ||
  "gestaoyahweh-21e23";

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run") || !args.includes("--execute");

if (!args.includes("--dry-run") && !args.includes("--execute")) {
  console.log(
    "Modo simulação (--dry-run). Para apagar: node scripts/purge-anonymous-auth-users.js --execute",
  );
}

const VALID_PROVIDER_IDS = new Set([
  "password",
  "google.com",
  "apple.com",
  "phone",
]);

function isAnonymousOnlyAuthUser(user) {
  const email = String(user.email ?? "").trim();
  if (email.length > 0) return false;
  const phone = String(user.phoneNumber ?? "").trim();
  if (phone.length > 0) return false;
  const providers = user.providerData ?? [];
  if (providers.length === 0) return true;
  return !providers.some((p) =>
    VALID_PROVIDER_IDS.has(String(p.providerId ?? "").trim()),
  );
}

if (!admin.apps.length) {
  admin.initializeApp({ projectId });
}

async function main() {
  console.log(`Projeto: ${projectId}`);
  console.log(dryRun ? "MODO: simulação (dry-run)" : "MODO: APAGAR (execute)");

  let scanned = 0;
  let deleted = 0;
  let skipped = 0;
  const errors = [];
  let pageToken;
  const pending = [];

  const flush = async () => {
    while (pending.length > 0) {
      const chunk = pending.splice(0, 1000);
      if (dryRun) {
        deleted += chunk.length;
        continue;
      }
      const res = await admin.auth().deleteUsers(chunk);
      deleted += res.successCount;
      for (const e of res.errors) {
        errors.push(`${e.index}: ${e.error.message}`);
      }
    }
  };

  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    for (const user of page.users) {
      scanned += 1;
      if (!isAnonymousOnlyAuthUser(user)) {
        skipped += 1;
        continue;
      }
      pending.push(user.uid);
      if (pending.length >= 1000) await flush();
    }
    pageToken = page.pageToken;
    process.stdout.write(
      `\rAnalisados: ${scanned} | a apagar: ${deleted + pending.length} | válidos: ${skipped}`,
    );
  } while (pageToken);

  await flush();

  console.log("\n--- Resultado ---");
  console.log(JSON.stringify({ scanned, deleted, skipped, errors: errors.slice(0, 20) }, null, 2));
  if (errors.length > 20) {
    console.log(`… +${errors.length - 20} erros`);
  }
  if (dryRun) {
    console.log("\nNenhum utilizador foi apagado. Rode com --execute para apagar.");
  } else {
    console.log("\nLimpeza concluída.");
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
