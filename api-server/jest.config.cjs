module.exports = {
  testEnvironment: "node",
  roots: ["<rootDir>/tests"],
  coverageDirectory: "<rootDir>/coverage",
  collectCoverageFrom: [
    "src/**/*.js",
    "!src/index.js"
  ]
};
