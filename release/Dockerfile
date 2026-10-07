FROM archlinux:base-devel@sha256:996c3a1d6b0d87b01242f6fcd8cfa3ad3eece1a67ab5c8f108e20af1d7b97bdd
RUN pacman -Syu --noconfirm --needed just jq libx11 systemd-libs dbus i3status shellcheck namcap git curl \
    && pacman -Scc --noconfirm
COPY scripts/setup-tools.sh /tmp/setup-tools.sh
RUN sh /tmp/setup-tools.sh /opt/my-bar-tools && rm /tmp/setup-tools.sh
ARG BUILDER_UID=1000
ARG BUILDER_GID=1000
RUN groupadd --gid "$BUILDER_GID" builder \
    && useradd --create-home --uid "$BUILDER_UID" --gid "$BUILDER_GID" builder
USER builder
ENV MY_BAR_TOOLS=/opt/my-bar-tools
WORKDIR /work
