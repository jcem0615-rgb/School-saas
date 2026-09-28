import {
  onlineClassBody,
  onlineClassTitle,
} from "../../../src/shared/notify/onlineClassMessage";

/**
 * What a class is told when their lesson starts.
 *
 * Read on a lock screen by a twelve-year-old, which is the whole reason
 * these are strings in a file rather than template literals buried in a
 * trigger nobody can run without an emulator.
 */
describe("telling a class their lesson has started", () => {
  it("names the lesson, not just the app", () => {
    // "LogicClass" on a lock screen says which app. It does not say
    // which lesson, and a pupil with four classes a day needs the
    // second one.
    expect(onlineClassTitle("Mathematics")).toBe("Mathematics is online now");
  });

  it("names the section, because a school runs two of the same class", () => {
    const body = onlineClassBody("Mathematics", "Grade 10 - Rizal");

    expect(body).toContain("Grade 10 - Rizal");
    // And a family sharing one device may have a child in each.
    expect(onlineClassBody("Mathematics", "Grade 10 - Bonifacio"))
      .not.toBe(body);
  });

  it("says what to do next, and what will be needed", () => {
    const body = onlineClassBody("Physics", "Grade 9 - Mabini");

    expect(body).toContain("Tap to join");
    expect(body).toContain("class code");
  });

  it("still says something when the record is blank", () => {
    // A session written without a subject is a broken record, not a
    // reason to send somebody a notification with a hole in it.
    expect(onlineClassTitle("")).toBe("Your class is online now");
    expect(onlineClassTitle("   ")).toBe("Your class is online now");
    expect(onlineClassBody("", "")).toContain("Your class has started");
    expect(onlineClassBody("  ", "  ")).not.toContain("  for");
  });

  it("fits on a lock screen", () => {
    // The push preview is cut at 180 characters. A message that only
    // reads correctly in the inbox is a message most people never read.
    expect(onlineClassBody("Mathematics", "Grade 10 - Rizal").length)
      .toBeLessThan(180);
  });

  it("says nothing about the room or the code", () => {
    // The room name is the whole of what keeps a stranger out of a class
    // of children, and the code is the second lock. Neither belongs in
    // something that lands on a lock screen a stranger can read.
    const body = onlineClassBody("Mathematics", "Grade 10 - Rizal");

    expect(body).not.toMatch(/lc-[a-z0-9]/);
    expect(body).not.toMatch(/[A-Z0-9]{4}-[A-Z0-9]{4}/);
  });
});
