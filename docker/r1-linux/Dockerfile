FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Guatemala

RUN apt-get update && apt-get install -y \
    frr \
    iproute2 \
    iptables \
    iputils-ping \
    traceroute \
    tcpdump \
    curl \
    wget \
    net-tools \
    nano \
    procps \
    kmod \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/frr /var/log/frr /var/run/frr /scripts \
 && chown -R frr:frr /etc/frr /var/log/frr /var/run/frr

COPY configs/frr/frr.conf  /etc/frr/frr.conf
COPY configs/frr/daemons   /etc/frr/daemons
COPY scripts/start.sh      /scripts/start.sh

RUN chown frr:frr /etc/frr/frr.conf /etc/frr/daemons \
 && chmod 640     /etc/frr/frr.conf /etc/frr/daemons \
 && chmod +x      /scripts/start.sh

CMD ["/scripts/start.sh"]
