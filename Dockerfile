FROM teslamate/grafana:1.29.1 as grafana

#---

FROM teslamate/teslamate:1.29.1

ARG BUILD_ARCH
ARG BASHIO_VERSION=0.16.2
ARG S6_OVERLAY_VERSION=3.1.6.2

ENV \
    DEBIAN_FRONTEND="noninteractive" \
    LANG="C.UTF-8" \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES=1 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
    S6_SERVICES_GRACETIME=0

USER root

RUN \
    set -x \
    && apt-get update && apt-get install -y --no-install-recommends \
        bash \
        bind9utils \
        ca-certificates \
        curl \
        jq \
        nginx \
        postgresql-client \
        tzdata \
        xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && S6_ARCH="${BUILD_ARCH}" \
    && if [ "${BUILD_ARCH}" = "amd64" ]; then S6_ARCH="x86_64"; \
    elif [ "${BUILD_ARCH}" = "armv7" ]; then S6_ARCH="arm"; fi \
    && curl -Ls "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" | tar xpJ -C / \
    && curl -Ls "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" | tar xpJ -C / \
    && curl -Ls "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-noarch.tar.xz" | tar Jxp -C /  \
    && curl -Ls "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-arch.tar.xz" | tar Jxp -C / \
    && mkdir -p /etc/fix-attrs.d \
    && mkdir -p /etc/services.d \
    && mkdir -p /tmp/bashio \
    && curl -Ls "https://github.com/hassio-addons/bashio/archive/v${BASHIO_VERSION}.tar.gz" | tar xz --strip 1 -C /tmp/bashio \
    && mv /tmp/bashio/lib /usr/lib/bashio \
    && ln -s /usr/lib/bashio/bashio /usr/bin/bashio \
    && rm -rf /tmp/bashio

COPY --chown=root scripts/*.sh /
RUN chmod a+x /*.sh

COPY --chown=root services/teslamate/run services/teslamate/finish /etc/services.d/teslamate/
RUN chmod a+x /etc/services.d/teslamate/*

COPY --chown=root services/nginx/run services/nginx/finish /etc/services.d/nginx/
RUN chmod a+x /etc/services.d/nginx/*

COPY --chown=root services/nginx/teslamate.conf /etc/nginx/conf.d/

COPY --from=grafana --chown=root /dashboards /dashboards
COPY --from=grafana --chown=root /dashboards_internal /dashboards

# S6-Overlay
ENTRYPOINT ["/init"]

LABEL \
    org.opencontainers.image.title="Home Assistant Add-on: TeslaMate" \
    org.opencontainers.image.description="A self-hosted data logger for your Tesla." \
    org.opencontainers.image.source="https://github.com/lildude/ha-addon-ghostfolio/" \
    org.opencontainers.image.licenses="MIT"
