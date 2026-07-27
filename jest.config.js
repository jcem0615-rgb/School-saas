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
};
