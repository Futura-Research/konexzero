# syntax=docker/dockerfile:1
# Development + CI Dockerfile for KonexZero
# Production deployments use Kamal with a multi-stage variant

ARG RUBY_VERSION=3.3.8
FROM docker.io/library/ruby:$RUBY_VERSION-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -qq && apt-get install --no-install-recommends -y \
    build-essential \
    curl \
    git \
    libpq-dev

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN --mount=type=cache,target=/usr/local/bundle/cache \
    bundle install --jobs 4 --retry 3

COPY . .

RUN groupadd -g 1000 rails \
    && useradd -u 1000 -g rails -m rails \
    && chown -R rails:rails /app

USER rails

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3000/healthz || exit 1

CMD ["bundle", "exec", "rails", "server", "-p", "3000", "-b", "0.0.0.0"]
