#!/bin/bash
# ============================================================
# start.sh — R1-Linux
#
# Rol: gateway + firewall + NAT66 DNAT + OSPFv3
#
# Interfaces (segun cableado GNS3):
#   eth0  2001:db8:12::1/64  Red publica  (R2 fa0/0)
#   eth1  fd00:1::1/64       LAN interna  (Switch1)
#
# NAT66 DNAT (eth0 publica → eth1 LAN):
#   :80    TCP  → fd00:1::10:80
#   :53    TCP  → fd00:1::10:53
#   :53    UDP  → fd00:1::10:53
#   :51820 UDP  → fd00:1::10:51820
#
# Persistent directories GNS3:
#   /etc/frr
# ============================================================
set -e
G='\033[0;32m' Y='\033[1;33m' R='\033[0;31m' N='\033[0m'
log()  { echo -e "${G}[OK]${N} $1"; }
warn() { echo -e "${Y}[!!]${N} $1"; }
err()  { echo -e "${R}[ERR]${N} $1"; exit 1; }

echo "=============================================="
echo "  R1-Linux — inicio"
echo "=============================================="

# -------------------------------------------------------
# 0. Esperar a que GNS3 conecte las interfaces virtuales
#    GNS3 arranca el contenedor primero y añade eth0/eth1
#    unos segundos después via ubridge/veth pairs.
# -------------------------------------------------------
log "[0/4] Esperando interfaces eth0 y eth1..."
for i in $(seq 1 30); do
    if ip link show eth0 &>/dev/null && ip link show eth1 &>/dev/null; then
        log "Interfaces disponibles (${i}s)"
        break
    fi
    sleep 1
done
if ! ip link show eth0 &>/dev/null; then
    warn "eth0 no aparecio en 30s — continuando igual"
fi

# -------------------------------------------------------
# 1. IPv6 forwarding — obligatorio antes de todo
# -------------------------------------------------------
log "[1/4] Habilitando IPv6 forwarding..."
sysctl -w net.ipv6.conf.all.forwarding=1     > /dev/null
sysctl -w net.ipv6.conf.default.forwarding=1 > /dev/null
sysctl -w net.ipv6.conf.all.accept_ra=0      > /dev/null

# -------------------------------------------------------
# 2. Configurar IPs
#    eth0 = publico (hacia R2)
#    eth1 = LAN interna (hacia Switch1 / PC1)
# -------------------------------------------------------
log "[2/4] Configurando IPs..."
ip link set eth0 up 2>/dev/null || true
ip link set eth1 up 2>/dev/null || true

ip -6 addr flush dev eth0 scope global 2>/dev/null || true
ip -6 addr flush dev eth1 scope global 2>/dev/null || true

ip -6 addr add 2001:db8:12::1/64 dev eth0 2>/dev/null || warn "2001:db8:12::1 ya existe"
ip -6 addr add fd00:1::1/64      dev eth1 2>/dev/null || warn "fd00:1::1 ya existe"

log "IPs asignadas:"
ip -6 addr show dev eth0 | grep inet6
ip -6 addr show dev eth1 | grep inet6

# -------------------------------------------------------
# 3. ip6tables — NAT66 DNAT + ACL
#
# Requiere modulos del kernel:
#   ip6table_nat, ip6table_filter, nf_conntrack_ipv6
# En GNS3 (contenedor privilegiado) estan disponibles.
# -------------------------------------------------------
log "[3/4] Configurando ip6tables (NAT66 DNAT + ACL)..."

# Cargar modulos necesarios (silenciar error si ya estan cargados)
modprobe ip6table_nat    2>/dev/null || true
modprobe ip6table_filter 2>/dev/null || true
modprobe nf_conntrack    2>/dev/null || true

# Limpiar todas las cadenas
ip6tables -F           2>/dev/null || true
ip6tables -t nat -F    2>/dev/null || true
ip6tables -X           2>/dev/null || true
ip6tables -t nat -X    2>/dev/null || true

# --- NAT66 DNAT: trafico entrante por eth0 (publico) → PC1 en eth1 (LAN) ---
ip6tables -t nat -A PREROUTING -i eth0 -p tcp --dport 80    \
    -j DNAT --to-destination [fd00:1::10]:80
ip6tables -t nat -A PREROUTING -i eth0 -p tcp --dport 53    \
    -j DNAT --to-destination [fd00:1::10]:53
ip6tables -t nat -A PREROUTING -i eth0 -p udp --dport 53    \
    -j DNAT --to-destination [fd00:1::10]:53
ip6tables -t nat -A PREROUTING -i eth0 -p udp --dport 51820 \
    -j DNAT --to-destination [fd00:1::10]:51820

# MASQUERADE en eth1: PC1 ve el trafico como proveniente de fd00:1::1 (R1)
ip6tables -t nat -A POSTROUTING -o eth1 -j MASQUERADE

# --- ACL: filtro en eth0 (interfaz publica) ---
# OSPFv3 (protocolo 89) necesario para adjacencia con R2
ip6tables -A INPUT -i eth0 -p ospf -j ACCEPT
ip6tables -A INPUT -i eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT
ip6tables -A INPUT -i eth0 -p ipv6-icmp -j ACCEPT
ip6tables -A INPUT -i eth1 -j ACCEPT
ip6tables -A INPUT -i lo   -j ACCEPT
ip6tables -A INPUT -i eth0 -j DROP

# Reenvio: eth0→eth1 permite nuevas conexiones (DNAT las redirige a PC1)
ip6tables -A FORWARD -i eth0 -o eth1 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
# Reenvio: eth1→eth0 solo trafico de respuesta
ip6tables -A FORWARD -i eth1 -o eth0 -m state --state ESTABLISHED,RELATED     -j ACCEPT

log "ip6tables OK"
echo "--- nat PREROUTING ---"
ip6tables -t nat -L PREROUTING  -n -v
echo "--- nat POSTROUTING ---"
ip6tables -t nat -L POSTROUTING -n -v
echo "--- filter INPUT ---"
ip6tables -L INPUT   -n -v
echo "--- filter FORWARD ---"
ip6tables -L FORWARD -n -v

# -------------------------------------------------------
# 4. FRRouting (OSPFv3)
# -------------------------------------------------------
log "[4/4] Iniciando FRRouting (OSPFv3)..."

chown frr:frr /etc/frr/frr.conf /etc/frr/daemons 2>/dev/null || true
chmod 640     /etc/frr/frr.conf /etc/frr/daemons 2>/dev/null || true

mkdir -p /var/log/frr /var/run/frr
chown frr:frr /var/log/frr /var/run/frr

/usr/lib/frr/zebra -d \
    -f /etc/frr/frr.conf \
    -u frr -g frr \
    --log file:/var/log/frr/zebra.log \
    -i /var/run/frr/zebra.pid
sleep 2

/usr/lib/frr/ospf6d -d \
    -f /etc/frr/frr.conf \
    -u frr -g frr \
    --log file:/var/log/frr/ospf6d.log \
    -i /var/run/frr/ospf6d.pid
sleep 1

log "FRRouting iniciado"

echo ""
echo "=============================================="
echo "  eth0 : 2001:db8:12::1/64  (RED PUBLICA → R2)"
echo "  eth1 : fd00:1::1/64       (LAN interna → Switch1)"
echo ""
echo "  NAT66 DNAT activo (entrada por eth0):"
echo "    :80    → fd00:1::10:80"
echo "    :53    → fd00:1::10:53"
echo "    :51820 → fd00:1::10:51820"
echo ""
echo "  OSPFv3 router-id 1.1.1.1"
echo "  Logs: vtysh -c 'show ipv6 ospf6 neighbor'"
echo "=============================================="

exec tail -f /var/log/frr/zebra.log /var/log/frr/ospf6d.log
