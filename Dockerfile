# syntax=docker/dockerfile:1.6
ARG RUBY_VERSION=3.3.6

# ---------- builder ----------
FROM --platform=$BUILDPLATFORM ruby:${RUBY_VERSION}-slim AS builder
ARG TARGETARCH
ARG TARGETOS
ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_FROZEN=1 \
    RACK_ENV=production
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    libsqlite3-dev \
    libyaml-dev \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Cache gems
COPY Gemfile Gemfile.lock* /app/
RUN bundle config set --local without 'development test' \
    && bundle install --jobs 4 --retry 3

# Copy source for asset build
COPY . /app

# Download Tailwind standalone CLI per target arch
RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) TW_ARCH=linux-x64 ;; \
      arm64) TW_ARCH=linux-arm64 ;; \
      *) echo "Unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -sSL "https://github.com/tailwindlabs/tailwindcss/releases/download/v4.1.13/tailwindcss-${TW_ARCH}" -o /usr/local/bin/tailwindcss; \
    chmod +x /usr/local/bin/tailwindcss

# Download fonts (Inter, Newsreader) self-hosted
RUN mkdir -p /app/public/fonts \
    && curl -sSL -o /app/public/fonts/Inter-Regular.woff2 "https://rsms.me/inter/font-files/Inter-Regular.woff2?v=4.0" \
    && curl -sSL -o /app/public/fonts/Inter-Medium.woff2 "https://rsms.me/inter/font-files/Inter-Medium.woff2?v=4.0" \
    && curl -sSL -o /app/public/fonts/Inter-SemiBold.woff2 "https://rsms.me/inter/font-files/Inter-SemiBold.woff2?v=4.0" \
    && curl -sSL -o /app/public/fonts/Newsreader-Regular.woff2 "https://cdn.jsdelivr.net/fontsource/fonts/newsreader@latest/latin-400-normal.woff2" \
    && curl -sSL -o /app/public/fonts/Newsreader-SemiBold.woff2 "https://cdn.jsdelivr.net/fontsource/fonts/newsreader@latest/latin-600-normal.woff2"

# Build CSS (Tailwind v4 — config is in the input CSS itself)
RUN cd /app && /usr/local/bin/tailwindcss \
    -i /app/config/tailwind.input.css \
    -o /app/public/app.css \
    --minify

# Clean cache
RUN rm -rf /usr/local/bundle/cache /usr/local/bundle/ruby/*/cache \
    /app/.git /app/test /app/coverage /app/tmp /app/log

# ---------- runtime ----------
FROM ruby:${RUBY_VERSION}-slim AS runtime
ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT="development:test" \
    RACK_ENV=production \
    PORT=9292 \
    NEUZ_DATA_DIR=/app/data
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libsqlite3-0 \
    curl \
    tini \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash --uid 1000 neuz

WORKDIR /app
COPY --from=builder --chown=neuz:neuz /usr/local/bundle /usr/local/bundle
COPY --from=builder --chown=neuz:neuz /app /app
RUN mkdir -p /app/data && chown -R neuz:neuz /app

USER neuz
EXPOSE 9292
VOLUME ["/app/data"]
ENTRYPOINT ["/usr/bin/tini","--","/app/bin/entrypoint.sh"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT:-9292}/healthz" || exit 1
