// api-server/src/metrics.js
const client = require("prom-client");

// Create a Registry
const register = new client.Registry();

// Add default metrics (CPU, memory, event loop, etc.)
client.collectDefaultMetrics({ 
  register,
  prefix: 'unityexpress_',
  gcDurationBuckets: [0.001, 0.01, 0.1, 1, 2, 5]
});

// ============================================================
// HTTP Metrics
// ============================================================

const httpRequestDurationSeconds = new client.Histogram({
  name: "unityexpress_http_request_duration_seconds",
  help: "HTTP request duration in seconds",
  labelNames: ["method", "route", "status_code"],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5, 10]
});

const httpRequestTotal = new client.Counter({
  name: "unityexpress_http_requests_total",
  help: "Total number of HTTP requests",
  labelNames: ["method", "route", "status_code"]
});

const httpRequestSizeBytes = new client.Histogram({
  name: "unityexpress_http_request_size_bytes",
  help: "HTTP request size in bytes",
  labelNames: ["method", "route"],
  buckets: [100, 1000, 10000, 100000, 1000000]
});

const httpResponseSizeBytes = new client.Histogram({
  name: "unityexpress_http_response_size_bytes",
  help: "HTTP response size in bytes",
  labelNames: ["method", "route", "status_code"],
  buckets: [100, 1000, 10000, 100000, 1000000]
});

const activeConnections = new client.Gauge({
  name: "unityexpress_active_connections",
  help: "Number of active HTTP connections"
});

// ============================================================
// Business Metrics - Purchases
// ============================================================

const purchasesCreated = new client.Counter({
  name: "unityexpress_purchases_created_total",
  help: "Total number of purchases created",
  labelNames: ["status"]
});

const purchaseValue = new client.Histogram({
  name: "unityexpress_purchase_value",
  help: "Distribution of purchase values",
  labelNames: ["status"],
  buckets: [10, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 50000]
});

const purchasesByUser = new client.Counter({
  name: "unityexpress_purchases_by_user_total",
  help: "Total purchases per user",
  labelNames: ["userid"]
});

const totalRevenue = new client.Gauge({
  name: "unityexpress_total_revenue",
  help: "Total revenue from all purchases"
});

const averagePurchaseValue = new client.Gauge({
  name: "unityexpress_average_purchase_value",
  help: "Average value of purchases"
});

// ============================================================
// Kafka Metrics
// ============================================================

const kafkaMessagesPublished = new client.Counter({
  name: "unityexpress_kafka_messages_published_total",
  help: "Total Kafka messages published",
  labelNames: ["topic", "status"]
});

const kafkaPublishDuration = new client.Histogram({
  name: "unityexpress_kafka_publish_duration_seconds",
  help: "Duration of Kafka publish operations",
  labelNames: ["topic", "status"],
  buckets: [0.01, 0.05, 0.1, 0.5, 1, 2, 5]
});

const kafkaConnectionStatus = new client.Gauge({
  name: "unityexpress_kafka_connection_status",
  help: "Kafka connection status (1 = connected, 0 = disconnected)"
});

const kafkaPublishErrors = new client.Counter({
  name: "unityexpress_kafka_publish_errors_total",
  help: "Total Kafka publish errors",
  labelNames: ["topic", "error_type"]
});

// ============================================================
// MongoDB Metrics
// ============================================================

const mongoQueriesTotal = new client.Counter({
  name: "unityexpress_mongo_queries_total",
  help: "Total MongoDB queries",
  labelNames: ["operation", "collection", "status"]
});

const mongoQueryDuration = new client.Histogram({
  name: "unityexpress_mongo_query_duration_seconds",
  help: "Duration of MongoDB queries",
  labelNames: ["operation", "collection"],
  buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 2]
});

const mongoConnectionStatus = new client.Gauge({
  name: "unityexpress_mongo_connection_status",
  help: "MongoDB connection status (1 = connected, 0 = disconnected)"
});

const mongoDocumentsTotal = new client.Gauge({
  name: "unityexpress_mongo_documents_total",
  help: "Total number of documents in collection",
  labelNames: ["collection"]
});

// ============================================================
// Application Metrics
// ============================================================

const apiErrors = new client.Counter({
  name: "unityexpress_api_errors_total",
  help: "Total API errors",
  labelNames: ["route", "error_type"]
});

const validationErrors = new client.Counter({
  name: "unityexpress_validation_errors_total",
  help: "Total validation errors",
  labelNames: ["field"]
});

const apiUptime = new client.Gauge({
  name: "unityexpress_api_uptime_seconds",
  help: "API uptime in seconds"
});

const lastDeploymentTimestamp = new client.Gauge({
  name: "unityexpress_last_deployment_timestamp",
  help: "Timestamp of last deployment"
});

// ============================================================
// Performance Metrics
// ============================================================

const slowQueries = new client.Counter({
  name: "unityexpress_slow_queries_total",
  help: "Number of slow database queries (>1s)",
  labelNames: ["operation", "collection"]
});

const cacheHits = new client.Counter({
  name: "unityexpress_cache_hits_total",
  help: "Total cache hits",
  labelNames: ["cache_type"]
});

const cacheMisses = new client.Counter({
  name: "unityexpress_cache_misses_total",
  help: "Total cache misses",
  labelNames: ["cache_type"]
});

// ============================================================
// Register all metrics
// ============================================================

register.registerMetric(httpRequestDurationSeconds);
register.registerMetric(httpRequestTotal);
register.registerMetric(httpRequestSizeBytes);
register.registerMetric(httpResponseSizeBytes);
register.registerMetric(activeConnections);

register.registerMetric(purchasesCreated);
register.registerMetric(purchaseValue);
register.registerMetric(purchasesByUser);
register.registerMetric(totalRevenue);
register.registerMetric(averagePurchaseValue);

register.registerMetric(kafkaMessagesPublished);
register.registerMetric(kafkaPublishDuration);
register.registerMetric(kafkaConnectionStatus);
register.registerMetric(kafkaPublishErrors);

register.registerMetric(mongoQueriesTotal);
register.registerMetric(mongoQueryDuration);
register.registerMetric(mongoConnectionStatus);
register.registerMetric(mongoDocumentsTotal);

register.registerMetric(apiErrors);
register.registerMetric(validationErrors);
register.registerMetric(apiUptime);
register.registerMetric(lastDeploymentTimestamp);

register.registerMetric(slowQueries);
register.registerMetric(cacheHits);
register.registerMetric(cacheMisses);

// ============================================================
// Middleware
// ============================================================

function metricsMiddleware(req, res, next) {
  const route = req.route ? req.route.path : req.path;
  const startTime = Date.now();
  
  // Increment active connections
  activeConnections.inc();
  
  // Track request size
  const requestSize = parseInt(req.headers['content-length']) || 0;
  if (requestSize > 0) {
    httpRequestSizeBytes
      .labels(req.method, route)
      .observe(requestSize);
  }
  
  // Start timer for duration
  const end = httpRequestDurationSeconds.startTimer({
    method: req.method,
    route
  });
  
  res.on("finish", () => {
    const statusCode = res.statusCode.toString();
    const duration = (Date.now() - startTime) / 1000;
    
    // Record duration
    end({ status_code: statusCode });
    
    // Count total requests
    httpRequestTotal
      .labels(req.method, route, statusCode)
      .inc();
    
    // Track response size
    const responseSize = parseInt(res.get('content-length')) || 0;
    if (responseSize > 0) {
      httpResponseSizeBytes
        .labels(req.method, route, statusCode)
        .observe(responseSize);
    }
    
    // Decrement active connections
    activeConnections.dec();
    
    // Track errors
    if (statusCode.startsWith('5')) {
      apiErrors.labels(route, 'server_error').inc();
    } else if (statusCode.startsWith('4')) {
      apiErrors.labels(route, 'client_error').inc();
    }
  });
  
  next();
}

// ============================================================
// Handler
// ============================================================

async function metricsHandler(req, res) {
  // Update uptime
  apiUptime.set(process.uptime());
  
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
}

// ============================================================
// Exports
// ============================================================

module.exports = {
  // Middleware & Handler
  metricsMiddleware,
  metricsHandler,
  register,
  
  // HTTP Metrics
  httpRequestDurationSeconds,
  httpRequestTotal,
  httpRequestSizeBytes,
  httpResponseSizeBytes,
  activeConnections,
  
  // Business Metrics
  purchasesCreated,
  purchaseValue,
  purchasesByUser,
  totalRevenue,
  averagePurchaseValue,
  
  // Kafka Metrics
  kafkaMessagesPublished,
  kafkaPublishDuration,
  kafkaConnectionStatus,
  kafkaPublishErrors,
  
  // MongoDB Metrics
  mongoQueriesTotal,
  mongoQueryDuration,
  mongoConnectionStatus,
  mongoDocumentsTotal,
  
  // Application Metrics
  apiErrors,
  validationErrors,
  apiUptime,
  lastDeploymentTimestamp,
  
  // Performance Metrics
  slowQueries,
  cacheHits,
  cacheMisses
};