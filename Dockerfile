



# -------- Build Stage --------
FROM node:22-slim AS builder

WORKDIR /app

# Copy dependency files (for caching)
COPY package*.json ./

# Install all dependencies (including dev)
RUN npm ci

# Copy source code
COPY . .

# Build application
RUN npm run build


# -------- Runtime Stage --------
FROM nginx:alpine

# Copy only required artifacts
COPY --from=builder /app/build /usr/share/nginx/html/

EXPOSE 80

CMD [ "nginx", "-g", "daemon off;" ]