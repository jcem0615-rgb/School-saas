/**
 * Who an announcement is addressed to.
 *
 * This is the same rule as `AnnouncementAudience.includes` in
 * app/lib/features/director_portal/domain/entities/announcement.dart, and
 * the two have to stay identical -- if they drift, people get pushed
 * notifications about announcements that are not in their list, or worse,
 * a class-suspension notice reaches everyone's list and nobody's phone.
 *
 * The duplication is deliberate rather than shared: the client filter
 * decides what a list shows, this decides whose phone rings, and a phone
 * is the one that wakes somebody at 5am. Both are covered by tests that
 * assert the same table of cases.
 */
export interface AnnouncementAudience {
  all: boolean;
  roles: string[];
}

/** Parses the audience off a Firestore document, defensively. */
export function readAudience(data: FirebaseFirestore.DocumentData | undefined): AnnouncementAudience {
  const raw = data?.audience;
  // An announcement written before the field existed, or by something
  // that omitted it, reaches nobody rather than everybody. A push is not
  // recoverable once sent, so the failure mode has to be silence.
  if (!raw || typeof raw !== "object") return {all: false, roles: []};
  return {
    all: raw.all === true,
    roles: Array.isArray(raw.roles) ? raw.roles.filter((r: unknown) => typeof r === "string") : [],
  };
}

export function audienceIncludes(audience: AnnouncementAudience, role: string): boolean {
  return audience.all || audience.roles.includes(role);
}
