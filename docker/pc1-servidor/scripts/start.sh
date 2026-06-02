#!/bin/bash
# ============================================================
# start.sh — PC1 Servidor
#
# Persistencia de IPs:
#   Se escribe /etc/network/interfaces.d/eth0.conf
#   Este directorio se agrega a persistent directories en GNS3
#   Así la config de red sobrevive reinicios del contenedor.
#
# Persistent directories a configurar en GNS3:
#   /etc/wireguard
#   /etc/bind/zones
#   /var/www
#   /var/log/nginx
#   /etc/network/interfaces.d
# ============================================================
set -e
G='\033[0;32m' Y='\033[1;33m' R='\033[0;31m' N='\033[0m'
log()  { echo -e "${G}[OK]${N} $1"; }
warn() { echo -e "${Y}[!!]${N} $1"; }
err()  { echo -e "${R}[ERR]${N} $1"; exit 1; }

echo "=============================================="
echo "  PC1 Servidor — inicio"
echo "=============================================="

IFACE="eth0"
NET_CONF="/etc/network/interfaces.d/eth0.conf"

# -------------------------------------------------------
# 1. Configuración de red persistente
#    PC1 en v5 usa SOLO ULA (fd00:1::10/64).
#    R1-Linux hace DNAT: la IP publica es 2001:db8:12::1 (R1 eth1).
#    Gateway: fd00:1::1 (R1-Linux eth0).
# -------------------------------------------------------
log "[1/5] Configurando red IPv6 persistente (solo ULA)..."

if [ ! -f "$NET_CONF" ]; then
    log "Primera vez — creando $NET_CONF"
    mkdir -p /etc/network/interfaces.d
    cat > "$NET_CONF" <<EOF
iface eth0 inet6 static
    address fd00:1::10
    netmask 64
    gateway fd00:1::1
    autoconf 0
    accept_ra 0
EOF
else
    log "$NET_CONF ya existe (directorio persistente) — reutilizando"
fi

# Aplicar la configuración
ip -6 addr flush dev "$IFACE" scope global 2>/dev/null || true
ip -6 addr add fd00:1::10/64 dev "$IFACE" 2>/dev/null || warn "fd00:1::10 ya existe"
ip -6 route add default via fd00:1::1 dev "$IFACE" 2>/dev/null || warn "ruta default ya existe"

log "IPs aplicadas:"
ip -6 addr show dev "$IFACE" | grep "inet6"

# -------------------------------------------------------
# 2. Forwarding IPv6
# -------------------------------------------------------
log "[2/5] Habilitando forwarding..."
sysctl -w net.ipv6.conf.all.forwarding=1     > /dev/null
sysctl -w net.ipv6.conf.default.forwarding=1 > /dev/null

# -------------------------------------------------------
# 3. ip6tables
# -------------------------------------------------------
log "[3/5] ip6tables..."
ip6tables -F INPUT   2>/dev/null || true
ip6tables -F FORWARD 2>/dev/null || true
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
ip6tables -A INPUT -p icmpv6 -j ACCEPT
ip6tables -A INPUT -p tcp --dport 80    -j ACCEPT
ip6tables -A INPUT -p tcp --dport 53    -j ACCEPT
ip6tables -A INPUT -p udp --dport 53    -j ACCEPT
ip6tables -A INPUT -p udp --dport 51820 -j ACCEPT
ip6tables -A INPUT -j DROP
ip6tables -A FORWARD -i wg0  -o eth0 -j ACCEPT
ip6tables -A FORWARD -i eth0 -o wg0  -j ACCEPT
log "ip6tables OK"

# -------------------------------------------------------
# 4. WireGuard
# -------------------------------------------------------
log "[4/5] Verificando WireGuard..."
# GNS3 monta /etc/wireguard como dir persistente vacio en primer arranque.
# Si el archivo no esta, restaurar desde la copia baked en /opt/wg-baked/
if [ ! -f /etc/wireguard/wg0.conf ]; then
    if [ -f /opt/wg-baked/wg0.conf ]; then
        cp /opt/wg-baked/wg0.conf /etc/wireguard/wg0.conf
        chmod 600 /etc/wireguard/wg0.conf
        log "wg0.conf restaurado desde imagen"
    else
        err "No existe wg0.conf — ejecuta ./generar-claves-y-rebuild.sh"
    fi
fi
grep -q "PLACEHOLDER" /etc/wireguard/wg0.conf 2>/dev/null && \
    err "wg0.conf tiene placeholders — ejecuta ./generar-claves-y-rebuild.sh"
log "wg0.conf OK"

# -------------------------------------------------------
# 5. Servicios
# -------------------------------------------------------
log "[5/5] Iniciando servicios..."
named-checkconf && service bind9 start && log "BIND9 OK"
nginx -t && nginx && log "Nginx OK"
wg-quick up wg0 && log "WireGuard OK"

echo ""
echo "=============================================="
echo "  ULA : fd00:1::10/64  (SOLO ULA — R1-Linux hace DNAT)"
echo "  GW  : fd00:1::1   (R1-Linux eth0)"
echo "  VPN : fd00:2::1/64"
echo "  HTTP :80  DNS :53  WG :51820"
echo "  Config de red en: $NET_CONF (persistente)"
echo "=============================================="

exec tail -f /var/log/nginx/dominio.com.access.log /var/log/syslog
