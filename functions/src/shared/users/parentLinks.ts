/**
 * Which children a parent account can see.
 *
 * `users/{uid}.linkedStudentIds` is the whole of a parent's access. Every
 * parent read in firestore.rules -- grades, attendance, the statement of
 * account, guidance summons, emergency alerts, the messaging thread --
 * resolves to "is this studentId in that array?". Nothing else gates it.
 *
 * So this array is a permission list wearing the clothes of a profile
 * field, and the two failure directions are not symmetrical:
 *
 *   * a missing link is an inconvenience -- a parent rings the office and
 *     somebody adds it;
 *   * a wrong link hands one family another family's child: their marks,
 *     their attendance, their balance, and a private line to their
 *     teacher. Nobody is notified, and nothing on either screen looks
 *     unusual.
 *
 * Which is why linking runs through a callable and is audited, rather
 * than being a client write to a profile field.
 *
 * Pure and separately tested: the array arithmetic here decides who reads
 * a child's record, and "it looked right" is not a standard that can be
 * held to.
 */

export class ParentLinkError extends Error {}

/** The array as it should be stored: unique, non-empty, order preserved. */
export function normaliseLinks(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  for (const entry of raw) {
    if (typeof entry !== "string") continue;
    const id = entry.trim();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push(id);
  }
  return out;
}

/**
 * The array after linking [studentId], and whether anything changed.
 *
 * Linking a child who is already linked is a no-op rather than an error.
 * A registrar who clicks twice, or two registrars working the same
 * enrolment queue, should not see a failure for a state that is already
 * correct -- but the caller still needs to know nothing happened, so the
 * audit log does not fill with links that were never made.
 */
export function withLink(
  existing: unknown,
  studentId: string
): {links: string[]; changed: boolean} {
  const id = studentId.trim();
  if (!id) throw new ParentLinkError("A student must be named.");

  const links = normaliseLinks(existing);
  if (links.includes(id)) return {links, changed: false};
  return {links: [...links, id], changed: true};
}

/**
 * The array after unlinking [studentId], and whether anything changed.
 *
 * Unlinking the last child leaves an empty array, not a deleted field. A
 * parent account with no children is a real state -- the family has left
 * the school, or the link was wrong and the right one has not been made
 * yet -- and it reads correctly everywhere: `in []` is false, so the
 * account simply sees nothing. Deleting the field would make every
 * `resource.data.linkedStudentIds` lookup in the rules error instead.
 */
export function withoutLink(
  existing: unknown,
  studentId: string
): {links: string[]; changed: boolean} {
  const id = studentId.trim();
  if (!id) throw new ParentLinkError("A student must be named.");

  const links = normaliseLinks(existing);
  const remaining = links.filter((s) => s !== id);
  return {links: remaining, changed: remaining.length !== links.length};
}
