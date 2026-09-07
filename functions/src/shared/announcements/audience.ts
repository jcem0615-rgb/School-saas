/**
 * Who an announcement is addressed to.
 *
 * This is the same rule as `AnnouncementAudience.includes` in
 * app/lib/features/director_portal/domain/entities/announcement.dart, and
 * the two have to stay identical -- if they drift, people get pushed
 * notifications about announcements that are not in their list, or worse,
 * a class-suspension notice reaches everyone's list and nobody's phone.
 *
 * They did drift, and in exactly that direction. Teachers were given a
 * way to address one class rather than a whole role, the client learned
 * about `sections`, and this file did not -- so every notice a teacher
 * posted to their own class was read here as "addressed to nobody" and
 * silently notified no one. It sat in the app's list, where a parent
 * would find it only by going to look.
 *
 * The duplication is deliberate rather than shared: the client filter
 * decides what a list shows, this decides whose phone rings, and a phone
 * is the one that wakes somebody at 5am. Both are covered by tests that
 * assert the same table of cases -- which is the part that has to
 * include sections now, since a table missing a case is how the drift
 * lasted this long.
 */
import {normalizeSection, normalizeSections} from "../sections";

export interface AnnouncementAudience {
  all: boolean;
  roles: string[];

  /**
   * Section names, e.g. "Grade 10 - Rizal". What a teacher posts to.
   *
   * Role and section are an OR, not an AND: a notice for one class has
   * to reach that section's students, their parents and the other
   * teachers who take them, and none of those is a role.
   */
  sections: string[];
}

/** Parses the audience off a Firestore document, defensively. */
export function readAudience(data: FirebaseFirestore.DocumentData | undefined): AnnouncementAudience {
  const raw = data?.audience;
  // An announcement written before the field existed, or by something
  // that omitted it, reaches nobody rather than everybody. A push is not
  // recoverable once sent, so the failure mode has to be silence.
  if (!raw || typeof raw !== "object") return {all: false, roles: [], sections: []};
  return {
    all: raw.all === true,
    roles: Array.isArray(raw.roles) ? raw.roles.filter((r: unknown) => typeof r === "string") : [],
    // Absent on every announcement posted before teachers could target a
    // class, which is why this defaults to empty rather than throwing.
    sections: Array.isArray(raw.sections) ?
      raw.sections.filter((s: unknown) => typeof s === "string") :
      [],
  };
}

/**
 * Whether this announcement is addressed to somebody with [role] who
 * belongs to [viewerSections].
 *
 * [viewerSections] are the classes that person is in, however they come
 * to be in one -- a student's own section, the sections of a parent's
 * children, the sections a teacher is assigned to. Resolving that is the
 * caller's job, because it takes queries; deciding what to do with it is
 * this function's.
 */
export function audienceIncludes(
  audience: AnnouncementAudience,
  role: string,
  viewerSections: Iterable<string> = []
): boolean {
  if (audience.all || audience.roles.includes(role)) return true;
  if (audience.sections.length === 0) return false;
  const addressed = normalizeSections(audience.sections);
  if (addressed.size === 0) return false;
  for (const section of viewerSections) {
    if (addressed.has(normalizeSection(section))) return true;
  }
  return false;
}

/**
 * Addressed to no one at all.
 *
 * The editor will not let anybody post from this state; this is the
 * second line, for anything written straight to Firestore. It is not the
 * same question as "does this reach *this* person", which is why it is
 * its own function rather than a check inlined at the one call site --
 * inlined, it went stale the moment sections existed and read every
 * class notice as addressed to nobody.
 */
export function reachesNobody(audience: AnnouncementAudience): boolean {
  return !audience.all && audience.roles.length === 0 && audience.sections.length === 0;
}
