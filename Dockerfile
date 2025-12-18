# Prep base stage
ARG TF_VERSION=1.5.5
FROM hashicorp/terraform:${TF_VERSION} AS tf-source
# Build ui
FROM node:20-alpine AS ui
WORKDIR /src
# Copy specific package files
COPY ./ui/package-lock.json ./
COPY ./ui/package.json ./
COPY ./ui/babel.config.js ./
# Set Progress, Config and install
RUN npm set progress=false && npm config set depth 0 && npm install
# Copy source
# Copy Specific Directories
COPY ./ui/public ./public
COPY ./ui/src ./src
# build (to dist folder)
RUN NODE_OPTIONS='--openssl-legacy-provider' npm run build

# Build rover
FROM golang:1.24-bookworm AS rover

WORKDIR /src
# Copy go.mod and go.sum first for caching
COPY go.mod go.sum ./
RUN go mod download
# Copy full source
COPY . .
# Copy ui/dist from ui stage as it needs to embedded
COPY --from=ui /src/dist ./ui/dist
# Build rover
RUN CGO_ENABLED=0 GOOS=linux go build -o rover .

# Release stage
# ---------------------------------------------------------
# Final Release Stage (Debian Bookworm Slim)
# ---------------------------------------------------------
FROM debian:bookworm-slim AS release

ENV DEBIAN_FRONTEND=noninteractive

COPY --from=tf-source /bin/terraform /bin/terraform

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    chromium \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r rover && useradd -r -g rover -m -d /home/rover rover

COPY --from=rover /src/rover /bin/rover

RUN chmod +x /bin/rover && \
    chown rover:rover /bin/rover

USER rover
WORKDIR /home/rover

ENTRYPOINT ["/bin/rover"]