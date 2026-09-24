import {newMeetingRoom, isMeetingRoom} from "../../../src/shared/meeting/room";

/// The room name is the only thing standing between a stranger and a
/// live class of children, so it is tested as a secret rather than as an
/// identifier.
describe("the name of the room a class meets in", () => {
  it("is different every time", () => {
    // A room reused across lessons is a door last term's leaver still
    // has a key to.
    const seen = new Set<string>();
    for (let i = 0; i < 500; i++) seen.add(newMeetingRoom());
    expect(seen.size).toBe(500);
  });

  it("says nothing about the class it belongs to", () => {
    // The name is in the address bar of every participant and in
    // whatever they paste into a chat. One naming the school, the
    // section or the subject discloses all three to anyone who ever
    // sees the link.
    const room = newMeetingRoom();
    for (const leak of ["school", "grade", "rizal", "math", "2026", "-09-"]) {
      expect(room.toLowerCase()).not.toContain(leak);
    }
    // Nothing date-shaped either.
    expect(room).not.toMatch(/\d{4}-\d{2}-\d{2}/);
  });

  it("is long enough not to be guessed", () => {
    // ~120 bits. The threat is not brute force over a network, it is
    // somebody typing a name they worked out from a timetable on a
    // noticeboard -- but a short name makes the first one possible too.
    const room = newMeetingRoom();
    expect(room.length).toBeGreaterThanOrEqual(23);
    expect(room.length).toBeLessThanOrEqual(27);
  });

  it("uses only characters every Jitsi deployment accepts", () => {
    for (let i = 0; i < 200; i++) {
      expect(newMeetingRoom()).toMatch(/^lc-[a-z0-9]+$/);
    }
  });

  describe("recognising one of ours", () => {
    it("accepts what it generates", () => {
      for (let i = 0; i < 200; i++) {
        expect(isMeetingRoom(newMeetingRoom())).toBe(true);
      }
    });

    it("refuses anything that arrived another way", () => {
      // Checked on the way out as well as in: a room name that reached
      // the document by some other route is one this app did not
      // generate, and sending a class to it is sending them somewhere
      // unknown.
      for (const bad of [
        "",
        "lc-",
        "lc-short",
        "logicclass-grade10-rizal",
        "lc-UPPERCASE1234567890",
        "lc-has spaces in it here",
        "../../etc/passwd",
        "lc-" + "a".repeat(200),
        null,
        undefined,
        42,
        {room: "lc-abcdefghijklmnopqrst"},
      ]) {
        expect(isMeetingRoom(bad)).toBe(false);
      }
    });
  });
});
