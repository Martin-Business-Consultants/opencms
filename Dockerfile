# syntax=docker/dockerfile:1
# check=error=true

# The CMS's production image, for Kamal (config/deploy.yml) or by hand:
#   docker build -t cms .
#   docker build --secret id=CMS_PLUGINS,env=CMS_PLUGINS -t cms .   # with the install's plugins
#   docker run -d -p 80:80 -e SECRET_KEY_BASE=… -v cms_storage:/rails/storage --name cms cms

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.6
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems (no Node: the admin's JavaScript is
# served through importmap with no build step)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./
# Plugins are gems the Gemfile globs, so they're needed before bundling.
COPY engines ./engines
COPY plugins ./plugins

# The install's own plugins, from the CMS_PLUGINS builder secret (bin/fetch-plugins).
COPY bin/fetch-plugins ./bin/
RUN --mount=type=secret,id=CMS_PLUGINS,required=false bin/fetch-plugins

# A plugin's gems aren't in the repository's Gemfile.lock, so with any
# installed the lock is resolved here (the core's gems stay at their locked
# versions) and kept aside for `COPY . .`, which would put the original back.
RUN if ls plugins/*/*.gemspec > /dev/null 2>&1; then BUNDLE_DEPLOYMENT=0 BUNDLE_FROZEN=0 bundle lock; fi && \
    cp Gemfile.lock /tmp/Gemfile.lock && \
    bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .
RUN cp /tmp/Gemfile.lock Gemfile.lock

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets (Propshaft digests; nothing is compiled) without
# requiring the install's secrets
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile


# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
