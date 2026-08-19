/**
 * Requires the Firestore emulator (uses admin.firestore() directly).
 * Run via: firebase emulators:exec --only firestore "jest test/shared/counters"
 */
import * as admin from "firebase-admin";
import {getNextSequence} from "../../../src/shared/counters/getNextSequence";

describe("getNextSequence", () => {
  beforeAll(() => {
    if (admin.apps.length === 0) {
      admin.initializeApp({projectId: "school-saas-test"});
    }
  });

  it("starts at 1 for a new counter", async () => {
    const value = await getNextSequence("school_x", "test_counter_new");
    expect(value).toBe(1);
  });

  it("increments on each call", async () => {
    const counterName = "test_counter_increment";
    const first = await getNextSequence("school_x", counterName);
    const second = await getNextSequence("school_x", counterName);
    const third = await getNextSequence("school_x", counterName);
    expect([first, second, third]).toEqual([1, 2, 3]);
  });

  it("never issues duplicate values under concurrent calls", async () => {
    const counterName = "test_counter_concurrent";
    const results = await Promise.all(
      Array.from({length: 20}, () => getNextSequence("school_x", counterName))
    );
    const unique = new Set(results);
    expect(unique.size).toBe(20);
  });

  it("keeps separate schools' counters independent", async () => {
    const a = await getNextSequence("school_a", "shared_counter_name");
    const b = await getNextSequence("school_b", "shared_counter_name");
    expect(a).toBe(1);
    expect(b).toBe(1);
  });
});
