FROM archlinux:base-devel@sha256:624bdc7fc6615155d67bc34cf7146c0c9fd0e3c92943977da63a630e4ca49c30
RUN pacman -Syu --noconfirm --needed just jq libx11 systemd-libs json-c dbus i3status shellcheck namcap git curl make xz \
    && pacman -Scc --noconfirm
COPY scripts/ci-install-tools.sh /tmp/ci-install-tools.sh
RUN sh /tmp/ci-install-tools.sh /opt/my-bar-tools && rm /tmp/ci-install-tools.sh
ARG BUILDER_UID=1000
ARG BUILDER_GID=1000
RUN groupadd --gid "$BUILDER_GID" builder \
    && useradd --create-home --uid "$BUILDER_UID" --gid "$BUILDER_GID" builder
USER builder
ENV MY_BAR_TOOLS=/opt/my-bar-tools
WORKDIR /work
