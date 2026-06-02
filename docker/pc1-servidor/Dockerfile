FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=America/Guatemala

RUN apt-get update && apt-get install -y \
    nginx \
    bind9 \
    bind9utils \
    bind9-doc \
    wireguard \
    wireguard-tools \
    iproute2 \
    iputils-ping \
    traceroute \
    tcpdump \
    curl \
    wget \
    net-tools \
    dnsutils \
    iptables \
    isc-dhcp-client \
    nano \
    procps \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/wireguard \
             /opt/wg-baked \
             /var/www/dominio.com \
             /var/www/intranet \
             /etc/bind/zones \
             /scripts

COPY configs/nginx/dominio.com.conf   /etc/nginx/sites-available/dominio.com
COPY configs/nginx/intranet.conf      /etc/nginx/sites-available/intranet
COPY configs/bind/named.conf.local    /etc/bind/named.conf.local
COPY configs/bind/named.conf.options  /etc/bind/named.conf.options
COPY configs/bind/zones/db.dominio.com    /etc/bind/zones/db.dominio.com
COPY configs/bind/zones/db.dominio.local  /etc/bind/zones/db.dominio.local
COPY web/dominio.com/index.html       /var/www/dominio.com/index.html
COPY web/intranet/index.html          /var/www/intranet/index.html
COPY scripts/start.sh                 /scripts/start.sh
# Copia de respaldo fuera del directorio persistente
# GNS3 monta /etc/wireguard vacio en primer arranque — restauramos desde aqui
COPY configs/wireguard/wg0.conf       /opt/wg-baked/wg0.conf

RUN ln -sf /etc/nginx/sites-available/dominio.com /etc/nginx/sites-enabled/ \
 && ln -sf /etc/nginx/sites-available/intranet    /etc/nginx/sites-enabled/ \
 && rm -f /etc/nginx/sites-enabled/default

RUN chmod +x /scripts/start.sh \
 && chown -R www-data:www-data /var/www/dominio.com /var/www/intranet

EXPOSE 80 53/tcp 53/udp 51820/udp

CMD ["/scripts/start.sh"]
