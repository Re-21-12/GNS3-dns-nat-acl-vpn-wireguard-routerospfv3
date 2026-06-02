#!/bin/bash
# ============================================================
# generar-claves-y-rebuild.sh
# Ejecutar UNA VEZ en el host de GNS3 (no dentro del contenedor)
#
# Qué hace:
#   1. Genera claves WireGuard reales en el host
#   2. Escribe los archivos de config con claves reales
#   3. Reconstruye la imagen Docker con todo incluido
#   4. La imagen resultante ya tiene claves fijas — no las pierde
#
# Ejecutar:
#   chmod +x generar-claves-y-rebuild.sh
#   ./generar-claves-y-rebuild.sh
# ============================================================

set -e
G='\033[0;32m' Y='\033[1;33m' N='\033[0m'
log()  { echo -e "${G}[OK]${N} $1"; }
warn() { echo -e "${Y}[!!]${N} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WG_DIR="$SCRIPT_DIR/docker/pc1-servidor/configs/wireguard"
PC3_DIR="$SCRIPT_DIR/docker/pc3-cliente/configs/wireguard"

echo "=============================================="
echo "  Generador de claves WireGuard para lab IPv6"
echo "=============================================="

# Verificar que wireguard-tools este instalado en el host
if ! command -v wg &>/dev/null; then
    warn "wg no encontrado. Instalar:"
    warn "  Ubuntu/Debian: sudo apt install wireguard-tools"
    warn "  Mac:           brew install wireguard-tools"
    exit 1
fi

# -------------------------------------------------------
# 1. Generar claves
# -------------------------------------------------------
log "Generando claves servidor (PC1)..."
SRV_PRIV=$(wg genkey)
SRV_PUB=$(echo "$SRV_PRIV" | wg pubkey)

log "Generando claves cliente (PC3)..."
PC3_PRIV=$(wg genkey)
PC3_PUB=$(echo "$PC3_PRIV" | wg pubkey)

echo ""
echo "  Servidor pubkey : $SRV_PUB"
echo "  PC3     pubkey  : $PC3_PUB"
echo ""

# -------------------------------------------------------
# 2. Escribir wg0.conf para PC1 (servidor) con claves reales
# -------------------------------------------------------
log "Escribiendo configs/wireguard/wg0.conf (PC1 servidor)..."
mkdir -p "$WG_DIR"
cat > "$WG_DIR/wg0.conf" <<EOF
[Interface]
Address    = fd00:2::1/64
ListenPort = 51820
PrivateKey = ${SRV_PRIV}
PostUp   = ip6tables -A FORWARD -i wg0 -j ACCEPT
PostUp   = ip6tables -A FORWARD -o wg0 -j ACCEPT
PostUp   = ip6tables -A INPUT   -i wg0 -j ACCEPT
PostDown = ip6tables -D FORWARD -i wg0 -j ACCEPT
PostDown = ip6tables -D FORWARD -o wg0 -j ACCEPT
PostDown = ip6tables -D INPUT   -i wg0 -j ACCEPT

[Peer]
# PC3 cliente
PublicKey           = ${PC3_PUB}
AllowedIPs          = fd00:2::2/128
PersistentKeepalive = 25
EOF
chmod 600 "$WG_DIR/wg0.conf"

# -------------------------------------------------------
# 3. Escribir wg0.conf para PC3 (cliente) con claves reales
# -------------------------------------------------------
log "Escribiendo configs/wireguard/wg0-client.conf (PC3 cliente)..."
mkdir -p "$PC3_DIR"
cat > "$PC3_DIR/wg0-client.conf" <<EOF
[Interface]
Address    = fd00:2::2/64
PrivateKey = ${PC3_PRIV}
# DNS via tunel VPN (fd00:1::10 enrutado por AllowedIPs)
DNS        = fd00:1::10

[Peer]
# PC1 servidor — Endpoint es R1-Linux que hace DNAT :51820 → fd00:1::10:51820
PublicKey           = ${SRV_PUB}
Endpoint            = [2001:db8:12::1]:51820
AllowedIPs          = fd00:1::/64, fd00:2::/64
PersistentKeepalive = 25
EOF
chmod 600 "$PC3_DIR/wg0-client.conf"

# -------------------------------------------------------
# 4. Reconstruir imagenes Docker con claves incluidas
# -------------------------------------------------------
log "Reconstruyendo imagen r1-linux..."
docker build -t r1-linux     "$SCRIPT_DIR/docker/r1-linux"

log "Reconstruyendo imagen pc1-servidor..."
docker build -t pc1-servidor "$SCRIPT_DIR/docker/pc1-servidor"

log "Reconstruyendo imagen pc3-cliente..."
docker build -t pc3-cliente  "$SCRIPT_DIR/docker/pc3-cliente"

echo ""
echo "=============================================="
echo "  Imagenes reconstruidas con claves fijas"
echo "  Ya no se generan claves al arrancar"
echo ""
echo "  r1-linux      → gateway NAT66 + OSPFv3"
echo "  pc1-servidor  → contiene wg0.conf del servidor"
echo "  pc3-cliente   → contiene wg0-client.conf del cliente"
echo ""
echo "  Templates Docker para GNS3:"
echo "    r1-linux     : 2 adaptadores (eth0 + eth1)"
echo "    pc1-servidor : 1 adaptador"
echo "    pc3-cliente  : 1 adaptador"
echo ""
echo "  Persistent directories:"
echo "    r1-linux     : /etc/frr"
echo "    pc1-servidor : /etc/wireguard /etc/bind/zones /var/www /var/log/nginx /etc/network/interfaces.d"
echo "    pc3-cliente  : /etc/wireguard /etc/network/interfaces.d"
echo ""
echo "  Si necesitas nuevas claves: volver a ejecutar"
echo "  este script y hacer docker build de nuevo."
echo "=============================================="
                                                                                                                                                                                                                                            