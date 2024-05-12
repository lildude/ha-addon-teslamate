FROM teslamate/grafana:1.28.5 as grafana

#---

FROM teslamate/teslamate:1.28.5

ARG ARCH
ARG BASHIO_VERSION=0.11.0
ARG S6_OVERLAY_VERSION=2.1.0.2

ENV \
    DEBIAN_FRONTEND="noninteractive" \
    LANG="C.UTF-8" \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES=1

USER root

# Commands taken from HA Ubuntu base Dockerfile but switched to wget as curl didn't work using buildx
# https://github.com/home-assistant/docker-base/blob/master/ubuntu/amd64/Dockerfile
RUN \
    set -x \
    && apt-get update && apt-get install -y --no-install-recommends \
        bash \
        bind9utils \
        ca-certificates \
        curl \
        jq \
        nginx \
        tzdata \
        wget \
    && rm -rf /var/lib/apt/lists/* \
    \
    && wget https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${ARCH}.tar.gz \
    && tar zxvf s6-overlay-${ARCH}.tar.gz -C / \
    && rm -f s6-overlay-${ARCH}.tar.gz \
    && mkdir -p /etc/fix-attrs.d \
    && mkdir -p /etc/services.d \
    \
    && mkdir -p /tmp/bashio \
    && wget https://github.com/hassio-addons/bashio/archive/v${BASHIO_VERSION}.tar.gz \
    && tar xvzf v${BASHIO_VERSION}.tar.gz --strip 1 -C /tmp/bashio \
    && rm -f v${BASHIO_VERSION}.tar.gz \
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