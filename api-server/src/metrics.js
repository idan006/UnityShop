const client = require("prom-client");

const register = new client.Registry();

client.collectDefaultMetrics({ register });

const httpRequestDurationSeconds = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "HTTP request duration in seconds",
  labelNames: ["method", "route", "status_code"],
  buckets: [0.05, 0.1, 0.3, 0.5, 1, 2, 5]
});

register.registerMetric(httpRequestDurationSeconds);

function metricsMiddleware(req, res, next) {
  const route = req.route ? req.route.path : req.path;
  const end = httpRequestDurationSeconds.startTimer({
    method: req.method,
    route
  });

  res.on("finish", () => {
    end({ status_code: res.statusCode });
  });

  next();
}

async function metricsHandler(req, res) {
  res.set("Content-Type", register.contentType);
  res.end(await register.metrics());
}

module.exports = {
  metricsMiddleware,
  metricsHandler,
  register
};
