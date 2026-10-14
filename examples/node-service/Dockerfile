# syntax=docker/dockerfile:1

# Reference-only Node sample (not deployed). Mirrors the typical alpine
# pattern: npm ci + prune + non-root UID 1001 + dumb-init.
FROM node:26.7.0-alpine

WORKDIR /app

# Cache the dependency install as a separate layer.
COPY package*.json ./
RUN npm ci
RUN npm prune --omit=dev

# Copy the application source.
COPY . .

# Non-root user (alpine allocates UID 1001 for the first app user).
RUN addgroup -S app && adduser -S app -G app
USER app

# NOTE: dumb-init is NOT bundled in the official node:alpine image. To make
# this reference sample runnable as-is, add it to the layer above, e.g.:
#   RUN apk add --no-cache dumb-init
# It reaps zombies and forwards signals to the app.
ENTRYPOINT ["dumb-init", "--", "node", "index.js"]
