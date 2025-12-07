module.exports = {
  testEnvironment: "jsdom",
  roots: ["<rootDir>/__tests__"],
  moduleNameMapper: {
    "^@/(.*)$": "<rootDir>/$1"
  },
  setupFilesAfterEnv: ["<rootDir>/jest.setup.js"],
  coverageDirectory: "<rootDir>/coverage",
  collectCoverageFrom: [
    "**/*.js",
    "!jest.config.js",
    "!coverage/**"
  ]
};
