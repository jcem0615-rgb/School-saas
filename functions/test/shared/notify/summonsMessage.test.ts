import {
  formatSummonsWhen,
  summonsCancelledBody,
  summonsIssuedBody,
} from "../../../src/shared/notify/summonsMessage";

describe("formatSummonsWhen", () => {
  it("renders in Manila time, not the server's", () => {
    // 01:30 UTC is 09:30 the same morning in Manila. A function running
    // in UTC would tell a family to come in at half past one at night.
    const when = formatSummonsWhen(new Date("2026-03-03T01:30:00Z"));
    expect(when).toContain("9:30");
    expect(when).toContain("Mar");
    expect(when).toContain("3");
  });

  it("gives nothing back for a missing or unusable date", () => {
    expect(formatSummonsWhen(null)).toBe("");
    expect(formatSummonsWhen(new Date("not a date"))).toBe("");
  });
});

describe("summonsIssuedBody", () => {
  it("names the student, the time and the reason", () => {
    const body = summonsIssuedBody("Ana Cruz", "Tue 3 Mar, 9:30 am", "Repeated lateness");
    expect(body).toBe(
      "Ana Cruz is asked to come to the guidance office on Tue 3 Mar, 9:30 am. " +
        "Reason: Repeated lateness."
    );
  });

  it("does not double the full stop when the reason already ends in one", () => {
    const body = summonsIssuedBody("Ana Cruz", "Tue 3 Mar", "Repeated lateness.");
    expect(body).not.toContain("..");
  });

  it("still says something useful with no reason given", () => {
    const body = summonsIssuedBody("Ana Cruz", "Tue 3 Mar", "   ");
    expect(body).toBe("Ana Cruz is asked to come to the guidance office on Tue 3 Mar.");
    expect(body).not.toContain("..");
    expect(body).not.toContain("Reason");
  });

  it("still says something useful with no date given", () => {
    const body = summonsIssuedBody("Ana Cruz", "", "Repeated lateness");
    expect(body).toBe(
      "Ana Cruz is asked to come to the guidance office. Reason: Repeated lateness."
    );
  });

  it("falls back to a name rather than addressing nobody", () => {
    expect(summonsIssuedBody("", "Tue 3 Mar", "")).toBe(
      "Your child is asked to come to the guidance office on Tue 3 Mar."
    );
  });
});

describe("summonsCancelledBody", () => {
  it("says plainly that there is nothing to attend", () => {
    expect(summonsCancelledBody("Ana Cruz", "Tue 3 Mar, 9:30 am")).toBe(
      "The guidance office has cancelled the appointment for Ana Cruz on " +
        "Tue 3 Mar, 9:30 am. There is nothing to attend."
    );
  });

  it("reads correctly with no date on the record", () => {
    expect(summonsCancelledBody("Ana Cruz", "")).toBe(
      "The guidance office has cancelled the appointment for Ana Cruz. " +
        "There is nothing to attend."
    );
  });
});
