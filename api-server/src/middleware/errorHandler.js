// api-server/src/middleware/errorHandler.js
const { createLogger } = require("../logger");
const logger = createLogger("ErrorHandler");

/**
 * Global error handling middleware
 * Must be registered after all other middleware and routes
 */
function errorHandler(err, req, res, next) {
  const statusCode = err.statusCode || err.status || 500;
  const errorId = `err-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

  logger.error("Request failed", {
    errorId,
    statusCode,
    method: req.method,
    path: req.path,
    message: err.message,
    stack: err.stack,
    ...(err.details && { details: err.details })
  });

  // Don't leak internal error details to client in production
  const clientMessage = process.env.NODE_ENV === "production" 
    ? "Internal server error" 
    : err.message;

  res.status(statusCode).json({
    error: clientMessage,
    errorId,
    ...(process.env.NODE_ENV !== "production" && { details: err.details })
  });
}

module.exports = { errorHandler };
