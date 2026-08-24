/**
 * Classifies a Firestore document write by comparing before/after data.
 * Extracted as a pure function (no Firebase types) so it's unit-testable
 * without spinning up the emulator -- see classifyAction.test.ts.
 */
export function classifyAction(
  before: Record<string, unknown> | null,
  after: Record<string, unknown> | null
): "create" | "delete" | "soft_delete" | "restore" | "update" {
  if (!before && after) return "create";
  if (before && !after) return "delete";
  if (before && after && after.isDeleted === true && before.isDeleted !== true) return "soft_delete";
  if (before && after && before.isDeleted === true && after.isDeleted === false) return "restore";
  return "update";
}
