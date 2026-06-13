import * as admin from "firebase-admin";

/** Garante app default quando o analisador Firebase carrega módulos isolados (antes de index.ts). */
if (!admin.apps.length) {
  admin.initializeApp();
}

/** Firestore lazy — evita `const db = admin.firestore()` no top-level dos módulos importados cedo. */
export function fs() {
  return admin.firestore();
}

export function storageBucket(name?: string) {
  return name ? admin.storage().bucket(name) : admin.storage().bucket();
}

export { admin };
