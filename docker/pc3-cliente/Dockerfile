FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    wireguard \
    wireguard-tools \
    openresolv \
    iproute2 \
    iputils-ping \
    traceroute \
    tcpdump \
    curl \
    wget \
    net-tools \
    dnsutils \
    nano \
    procps \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/wireguard /opt/wg-baked /scripts

COPY configs/wireguard/wg0-client.conf /etc/wireguard/wg0.conf
# Copia de respaldo fuera del directorio persistente
COPY configs/wireguard/wg0-client.conf /opt/wg-baked/wg0.conf
COPY scripts/start.sh /scripts/start.sh

RUN chmod +x /scripts/start.sh \
 && chmod 600 /etc/wireguard/wg0.conf /opt/wg-baked/wg0.conf

CMD ["/scripts/start.sh"]
