/** A bounded server-issued grant for a store review account only. */
export function reviewGrantIsActive(
  value: unknown,
  authenticatedUserId: string,
  now: Date,
): boolean {
  if (typeof value !== "object" || value === null) return false;
  const grant = value as Record<string, unknown>;
  if (
    grant.user_id !== authenticatedUserId ||
    grant.purpose !== "store_review" ||
    typeof grant.expires_at !== "string"
  ) return false;
  const expiry = Date.parse(grant.expires_at);
  return Number.isFinite(expiry) && expiry > now.getTime();
}
