#!/bin/bash
# ============================================================
# start.sh — PC3 Cliente
#
# Persistent directories en GNS3:
#   /etc/wireguard
#   /etc/network/interfaces.d
# ============================================================
set -e
G='\033[0;32m' Y='\033[1;33m' N='\033[0m'
log()  { echo -e "${G}[OK]${N} $1"; }
warn() { echo -e "${Y}[!!]${N} $1"; }

echo "=============================================="
echo "  PC3 Cliente — inicio"
echo "=============================================="

IFACE="eth0"
NET_CONF="/etc/network/interfaces.d/eth0.conf"

# -------------------------------------------------------
# 1. Config de red persistente
# -------------------------------------------------------
log "[1/2] Configurando red IPv6 persistente..."

if [ ! -f "$NET_CONF" ]; then
    log "Primera vez — creando $NET_CONF"
    mkdir -p /etc/network/interfaces.d
    cat > "$NET_CONF" <<EOF
iface eth0 inet6 static
    address 2001:db8:3::10
    netmask 64
    gateway 2001:db8:3::1
    autoconf 0
    accept_ra 0
EOF
else
    log "$NET_CONF ya existe (persistente) — reutilizando"
fi

ip -6 addr flush dev "$IFACE" scope global 2>/dev/null || true

while IFS= read -r line; do
    if echo "$line" | grep -q "address"; then
        ADDR=$(echo "$line" | awk '{print $2}')
        MASK=$(grep -A1 "address $ADDR" "$NET_CONF" | grep "netmask" | awk '{print $2}')
        [ -z "$MASK" ] && MASK="64"
        ip -6 addr add "${ADDR}/${MASK}" dev "$IFACE" 2>/dev/null || warn "$ADDR ya existe"
    fi
    if echo "$line" | grep -q "gateway"; then
        GW=$(echo "$line" | awk '{print $2}')
        ip -6 route add default via "$GW" dev "$IFACE" 2>/dev/null || warn "ruta ya existe"
    fi
done < "$NET_CONF"

log "IPv6: 2001:db8:3::10/64   gw: 2001:db8:3::1"
ip -6 addr show dev "$IFACE" | grep "inet6"

# -------------------------------------------------------
# 2. WireGuard
# -------------------------------------------------------
log "[2/2] Verificando WireGuard..."
# Restaurar desde imagen si el dir persistente esta vacio
if [ ! -f /etc/wireguard/wg0.conf ]; then
    if [ -f /opt/wg-baked/wg0.conf ]; then
        cp /opt/wg-baked/wg0.conf /etc/wireguard/wg0.conf
        chmod 600 /etc/wireguard/wg0.conf
        log "wg0.conf restaurado desde imagen"
    else
        warn "No hay wg0.conf — arrancando sin VPN"
    fi
fi

if grep -q "PLACEHOLDER" /etc/wireguard/wg0.conf 2>/dev/null; then
    warn "wg0.conf tiene placeholders — ejecuta ./generar-claves-y-rebuild.sh"
elif [ -f /etc/wireguard/wg0.conf ]; then
    wg-quick up wg0
    log "WireGuard activo"
    wg show
fi

echo ""
echo "=============================================="
echo "  IP  : 2001:db8:3::10/64"
echo "  GW  : 2001:db8:3::1 (R3)"
echo "  Config de red en: $NET_CONF (persistente)"
echo "=============================================="

exec /bin/bash
