// api-server/src/logger.js
const winston = require("winston");

// Create a structured logger with JSON format
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || "info",
  format: winston.format.combine(
    winston.format.timestamp({ format: "YYYY-MM-DD HH:mm:ss" }),
    winston.format.errors({ stack: true }),
    winston.format.splat(),
    winston.format.json()
  ),
  defaultMeta: { service: "unityexpress-api" },
  transports: [
    // Console transport for visibility
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.printf(({ timestamp, level, message, service, ...meta }) => {
          const metaStr = Object.keys(meta).length > 0 ? JSON.stringify(meta, null, 2) : "";
          return `${timestamp} [${service}] ${level}: ${message} ${metaStr}`;
        })
      )
    })
  ]
});

// Export a child logger factory
function createLogger(component) {
  return logger.child({ component });
}

module.exports = { logger, createLogger };
