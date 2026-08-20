FROM ruby:2.7.8-bullseye

ENV LANG=C.UTF-8 \
    RAILS_ENV=development \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3

# Native dependencies required by the legacy Rails bundle.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential \
      libsqlite3-dev \
      nodejs \
      ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Ruby 2.6 ships with an old Bundler; pin the version used by this revived app.
RUN gem update --system 3.2.3 \
 && gem install bundler -v 2.4.22 --no-document

# Resolve/install dependencies before copying the rest of the source so Docker can cache this layer.
COPY Gemfile Gemfile.lock ./

# The lockfile was originally produced on Windows. Add Linux as a supported platform
# inside the image without changing the host checkout.
RUN bundle _2.4.22_ config --local without production \
 && bundle _2.4.22_ config --local build.sqlite3 "--with-cflags=-Wno-error=incompatible-pointer-types" \
 && bundle _2.4.22_ config --local build.bcrypt "--with-cflags=-Wno-error=incompatible-pointer-types" \
 && bundle _2.4.22_ install

COPY . .

RUN mkdir -p /app/tmp/pids /app/user_data/songs /app/storage \
 && chmod +x /app/docker/entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["/app/docker/entrypoint.sh"]
CMD ["bundle", "_2.4.22_", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
