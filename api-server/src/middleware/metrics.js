// api-server/src/middleware/metrics.js
const { 
  httpRequestDuration, 
  httpRequestTotal,
  activeConnections 
} = require('../metrics');

function metricsMiddleware(req, res, next) {
  const start = Date.now();
  
  // Increment active connections
  activeConnections.inc();
  
  // Track when response finishes
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const route = req.route?.path || req.path;
    const statusCode = res.statusCode.toString();
    
    // Record request duration
    httpRequestDuration
      .labels(req.method, route, statusCode)
      .observe(duration);
    
    // Count total requests
    httpRequestTotal
      .labels(req.method, route, statusCode)
      .inc();
    
    // Decrement active connections
    activeConnections.dec();
  });
  
  next();
}

module.exports = { metricsMiddleware };