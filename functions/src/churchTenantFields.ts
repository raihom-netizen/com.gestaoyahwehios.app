import * as admin from "firebase-admin";

/** Campos canónicos — espelho de `flutter_app/lib/core/data/church_tenant_fields.dart`. */
export function tenantFieldsPatch(
  churchId: string,
  includeTimestamp = true,
): Record<string, unknown> {
  const id = String(churchId || "").trim();
  const patch: Record<string, unknown> = {
    churchId: id,
    tenantId: id,
  };
  if (includeTimestamp) {
    patch.tenantFieldsStampedAt = admin.firestore.FieldValue.serverTimestamp();
  }
  return patch;
}

export function withTenantFieldsStamp(
  churchId: string,
  data: Record<string, unknown>,
): Record<string, unknown> {
  const id = String(churchId || "").trim();
  if (!id) return data;
  return { ...data, churchId: id, tenantId: id };
}

export function needsTenantFieldsStamp(
  data: Record<string, unknown> | undefined,
  churchId: string,
): boolean {
  const id = String(churchId || "").trim();
  if (!id) return false;
  const d = data ?? {};
  return String(d.churchId ?? "").trim() !== id || String(d.tenantId ?? "").trim() !== id;
}
