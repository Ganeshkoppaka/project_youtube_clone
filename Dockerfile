# ============================================================
# STAGE 1 — BUILDER
# Node.js is ONLY in this stage. It never appears in the
# final image. This is the core of multi-stage security.
# ============================================================
FROM node:20-alpine AS builder
# Why alpine? Minimal OS — fewer packages = smaller attack surface
# node:20 = LTS version, actively patched

# Set working directory inside container
WORKDIR /app

# Copy package files FIRST (before source code)
# Why? Docker layer caching — if package.json doesn't change,
# npm ci is skipped on rebuild. Faster builds.
COPY package.json package-lock.json ./

# Install exact versions from lock file
# --frozen-lockfile = fail if lock file is out of sync (same as npm ci)
RUN npm ci --frozen-lockfile

# Now copy the rest of the source code
COPY . .

# Remove any .env files that might have been copied
# This is a safety net — .dockerignore handles it too,
# but defense in depth means we check here as well
RUN rm -f .env .env.local .env.*.local

# Build the React app
# REACT_APP_RAPIDAPI_KEY is passed as a build argument
# It gets baked into the JS bundle at build time
ARG REACT_APP_RAPIDAPI_KEY
ENV REACT_APP_RAPIDAPI_KEY=$REACT_APP_RAPIDAPI_KEY

RUN npm run build
# Result: /app/build/ contains index.html + JS bundles

# ============================================================
# STAGE 2 — RUNTIME (final image)
# This is what actually runs in production.
# It contains ONLY nginx + the static build output.
# No Node, no npm, no package.json, no source code.
# ============================================================
FROM nginx:1.27-alpine AS runtime
# nginx:alpine = ~40MB vs node:alpine ~180MB

# Copy our custom security-hardened nginx config
COPY nginx.conf /etc/nginx/nginx.conf

# Copy ONLY the built static files from the builder stage
# Everything else from stage 1 is discarded automatically
COPY --from=builder /app/build /usr/share/nginx/html

# Fix permissions so nginx can read files
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html

# Create nginx cache dirs with correct permissions
RUN mkdir -p /var/cache/nginx /var/run && \
    chown -R nginx:nginx /var/cache/nginx /var/run

# Switch to non-root user
# nginx process runs as uid 101 (nginx user), NOT root
USER nginx

# Document which port the app listens on
EXPOSE 8080

# Health check — Kubernetes uses this to know if the pod is healthy
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/ || exit 1

# Start nginx in foreground (required for containers — no daemon mode)
CMD ["nginx", "-g", "daemon off;"]