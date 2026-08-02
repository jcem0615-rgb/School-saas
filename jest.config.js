/** @type {import('jest').Config} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/test-rules"],
  testMatch: ["**/*.test.ts"],
  transform: {
    "^.+\\.ts$": ["ts-jest", {isolatedModules: true, tsconfig: "<rootDir>/tsconfig.json"}],
  },
  // Rules tests spin up/tear down emulator state per file; give them more
  // room than the 5s Jest default, especially the first test in a run.
  testTimeout: 20000,
  // Serial, and not negotiable. Every suite here talks to the one
  // emulator under the same projectId and calls clearFirestore() in
  // afterEach -- run in parallel, suites wipe each other's seed data
  // mid-test and fail with bare PERMISSION_DENIED on documents that were
  // there a moment ago. That looks exactly like a rules regression and
  // sent one investigation down the wrong path already.
  maxWorkers: 1,
};
