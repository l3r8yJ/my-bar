FROM archlinux:base-devel@sha256:996c3a1d6b0d87b01242f6fcd8cfa3ad3eece1a67ab5c8f108e20af1d7b97bdd
RUN pacman -Syu --noconfirm --needed clang llvm just jq libx11 systemd-libs json-c dbus i3status shellcheck namcap git \
    && pacman -Scc --noconfirm
ARG BUILDER_UID=1000
ARG BUILDER_GID=1000
RUN groupadd --gid "$BUILDER_GID" builder \
    && useradd --create-home --uid "$BUILDER_UID" --gid "$BUILDER_GID" builder
USER builder
ENV CFLAGS="-march=x86-64 -mtune=generic -fstack-protector-strong -fstack-clash-protection -fcf-protection" \
    LDFLAGS="-Wl,-z,relro,-z,now"
WORKDIR /work
