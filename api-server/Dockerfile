# syntax=docker/dockerfile:1

# ============================================================
# Stage 1: Dependencies
# ============================================================
FROM node:20-alpine AS dependencies

# Set working directory
WORKDIR /app

# Install security updates
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
    dumb-init \
    && rm -rf /var/cache/apk/*

# Copy package files
COPY package*.json ./

# Install production dependencies only
# Use npm ci for faster, reproducible builds
RUN npm ci --only=production --ignore-scripts && \
    npm cache clean --force

# ============================================================
# Stage 2: Build (if needed for TypeScript/transpilation)
# ============================================================
FROM dependencies AS build

# Copy source code
COPY src ./src

# Run any build steps if needed
# RUN npm run build

# ============================================================
# Stage 3: Production
# ============================================================
FROM node:20-alpine AS production

# Add metadata labels
LABEL maintainer="UnityExpress Team"
LABEL description="UnityExpress API Server - Production-ready Node.js microservice"
LABEL version="1.0.0"

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init && \
    rm -rf /var/cache/apk/*

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Set working directory
WORKDIR /app

# Copy dependencies from dependencies stage
COPY --from=dependencies --chown=nodejs:nodejs /app/node_modules ./node_modules

# Copy package files
COPY --chown=nodejs:nodejs package*.json ./

# Copy application code
COPY --chown=nodejs:nodejs src ./src

# Set NODE_ENV to production
ENV NODE_ENV=production \
    PORT=3000 \
    # Optimize Node.js memory usage
    NODE_OPTIONS="--max-old-space-size=512" \
    # Enable heap snapshots on OOM
    NODE_HEAPSNAPSHOT_OPTIONS="--heapsnapshot-signal=SIGUSR2"

# Expose application port
EXPOSE 3000

# Switch to non-root user
USER nodejs

# Add healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})" || exit 1

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]

# Start the application
CMD ["node", "src/index.js"]