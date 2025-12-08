# syntax=docker/dockerfile:1

# ============================================================
# Stage 1: Build (if using build tools like npm, webpack)
# ============================================================
FROM node:20-alpine AS builder

WORKDIR /build

# If you have package.json for building web assets:
# COPY package*.json ./
# RUN npm ci && npm cache clean --force
# COPY . .
# RUN npm run build

# For static files only, skip this stage

# ============================================================
# Stage 2: Production with optimized NGINX
# ============================================================
FROM nginx:1.25-alpine AS production

# Add metadata labels
LABEL maintainer="UnityExpress Team"
LABEL description="UnityExpress Web UI - Optimized NGINX static server"
LABEL version="1.0.0"

# Install security updates
RUN apk update && \
    apk upgrade && \
    apk add --no-cache \
    # For signal handling
    tini \
    # For healthchecks
    curl \
    && rm -rf /var/cache/apk/*

# Create non-root user for NGINX
RUN addgroup -g 101 -S nginx || true && \
    adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx || true

# Remove default NGINX config and content
RUN rm -rf /etc/nginx/conf.d/* && \
    rm -rf /usr/share/nginx/html/*

# Copy optimized NGINX configuration
COPY --chown=nginx:nginx nginx.conf /etc/nginx/nginx.conf

# Copy static web content
COPY --chown=nginx:nginx html/ /usr/share/nginx/html/

# Create required directories with proper permissions
RUN mkdir -p /var/cache/nginx/client_temp \
             /var/cache/nginx/proxy_temp \
             /var/cache/nginx/fastcgi_temp \
             /var/cache/nginx/uwsgi_temp \
             /var/cache/nginx/scgi_temp && \
    chown -R nginx:nginx /var/cache/nginx && \
    chmod -R 755 /var/cache/nginx

# Create pid file directory
RUN mkdir -p /var/run/nginx && \
    chown -R nginx:nginx /var/run/nginx && \
    chmod -R 755 /var/run/nginx

# Set permissions for log directories
RUN touch /var/log/nginx/access.log /var/log/nginx/error.log && \
    chown -R nginx:nginx /var/log/nginx && \
    chmod -R 755 /var/log/nginx

# Environment variables
ENV NGINX_WORKER_PROCESSES=auto \
    NGINX_WORKER_CONNECTIONS=1024

# Expose HTTP port
EXPOSE 80

# Switch to non-root user
USER nginx

# Add healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost/health || exit 1

# Use tini for proper signal handling
ENTRYPOINT ["/sbin/tini", "--"]

# Start NGINX in foreground
CMD ["nginx", "-g", "daemon off;"]