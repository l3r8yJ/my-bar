FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git gcc libc6-dev \
       pkg-config clang clang-tidy clang-format libclang-rt-dev just jq libx11-dev \
       libsystemd-dev libjson-c-dev dbus binutils shellcheck \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /work
