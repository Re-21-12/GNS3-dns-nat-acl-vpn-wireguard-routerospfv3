#!/bin/bash
# ============================================================
# PRUEBAS PC3 — Lab IPv6 v5
# Ejecutar en la maquina host de GNS3, no dentro del contenedor
#
# Uso:
#   chmod +x ejecutar-pruebas-pc3.sh
#   ./ejecutar-pruebas-pc3.sh
# ============================================================

# chmod +x /home/re/Downloads/lab-ipv6-v2-ios124/lab-ipv6-v2/tests/ejecutar-pruebas-pc3.sh

PC3=$(docker ps --filter name=GNS3.pc3 -q)
[ -z "$PC3" ] && echo "ERROR: pc3-cliente no esta corriendo en Docker" && exit 1

run() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    shift
    docker exec "$PC3" bash -c "$*" 2>&1
}

echo ""
echo "============================================================"
echo "  PRUEBAS DE CONECTIVIDAD IPv6 — PC3 Cliente Externo"
echo "============================================================"

# ----------------------------------------------------------
# FASE 1 — Identidad de PC3
# ----------------------------------------------------------
run "FASE 1 | Identidad de PC3" "
echo 'IP asignada:'
ip -6 addr show eth0 | grep 'inet6.*global'
echo ''
echo 'Gateway default (debe ser R3 = 2001:db8:3::1):'
ip -6 route show default
echo ''
echo 'Estado WireGuard:'
wg show 2>/dev/null | grep -E 'interface|endpoint|handshake|transfer|allowed'
"

# ----------------------------------------------------------
# FASE 2 — ping6 a R2 desde PC3 (requisito enunciado)
# ----------------------------------------------------------
run "FASE 2 | ping6 a la direccion publica de R2 desde PC3" "
echo 'Ping a R2 Serial0/0 (2001:db8:23::1) — enlace directo R2-R3:'
ping6 -c 3 -W 2 2001:db8:23::1
echo ''
echo 'Ping a R2 FastEthernet0/0 (2001:db8:12::2) — enlace R2-R1:'
ping6 -c 3 -W 2 2001:db8:12::2
"

# ----------------------------------------------------------
# FASE 3 — traceroute6 a dominio.com para verificar OSPFv3
# ----------------------------------------------------------
run "FASE 3 | traceroute6 a dominio.com (OSPFv3 en accion)" "
echo 'dominio.com resuelve a 2001:db8:12::1 (R1-Linux, punto publico)'
echo ''
echo 'Ruta esperada:'
echo '  Salto 1: 2001:db8:3::1   (R3 fa0/0 — gateway PC3)'
echo '  Salto 2: 2001:db8:23::1  (R2 Serial0/0 — enlace serial R2-R3)'
echo '  Salto 3: 2001:db8:12::1  (R1-Linux eth0 — NAT66 entrada)'
echo ''
traceroute6 -n -q 2 -w 2 -m 6 2001:db8:12::1
"

# ----------------------------------------------------------
# FASE 4 — HTTP publico sin VPN (NAT66 DNAT)
# ----------------------------------------------------------
run "FASE 4 | Acceso web publico — dominio.com (sin VPN)" "
echo 'curl a 2001:db8:12::1:80 — R1-Linux hace DNAT a PC1:80'
echo ''
curl -6 --max-time 5 -s http://[2001:db8:12::1]/ | grep -E 'h1|<p>'
echo ''
echo 'Verificar ACL bloquea puertos no permitidos (:8080):'
curl -6 --max-time 3 -s http://[2001:db8:12::1]:8080/ \
    && echo 'FAIL: deberia estar bloqueado' \
    || echo 'OK: ACL bloquea :8080 correctamente'
"

# ----------------------------------------------------------
# FASE 5 — DNS via R1-Linux (DNAT :53 -> PC1)
# ----------------------------------------------------------
run "FASE 5 | DNS via NAT66 DNAT :53 hacia PC1" "
echo 'Consulta DNS a traves de R1-Linux (DNAT :53 -> fd00:1::10:53)'
echo ''
echo 'dominio.com (zona publica — debe resolver a R1-Linux):'
dig AAAA dominio.com @2001:db8:12::1 +short +time=3 2>/dev/null \
    || echo 'DNAT DNS no respondio — bind9 puede estar solo en ULA'
echo ''
echo 'Consulta DNS directa a PC1 via VPN (fd00:1::10):'
dig AAAA dominio.com @fd00:1::10 +short +time=3 2>/dev/null
echo ''
echo 'dominio.local (zona privada — solo via VPN):'
dig AAAA dominio.local @fd00:1::10 +short +time=3 2>/dev/null
"

# ----------------------------------------------------------
# FASE 6 — VPN WireGuard (PC3 -> R1-Linux DNAT -> PC1)
# ----------------------------------------------------------
run "FASE 6 | VPN WireGuard — estado y acceso interno" "
echo 'Estado del tunel:'
wg show 2>/dev/null
echo ''
echo 'Ping al extremo VPN servidor (fd00:2::1 = PC1 wg0):'
ping6 -c 3 -W 3 fd00:2::1 \
    && echo 'Tunel WireGuard activo' \
    || echo 'Sin tunel — ejecutar: wg-quick up wg0'
echo ''
echo 'Ping a PC1 ULA interna via tunel (fd00:1::10):'
ping6 -c 3 -W 3 fd00:1::10
echo ''
echo 'HTTP intranet privada (solo accesible con VPN):'
curl -6 --max-time 5 -s \
    -H 'Host: intranet.dominio.local' \
    http://[fd00:1::10]/ | grep -E 'h1|<p>|<div class'
"

# ----------------------------------------------------------
# FASE 7 — Aislamiento: recursos privados sin VPN
# ----------------------------------------------------------
run "FASE 7 | Aislamiento — VPN abajo -> red interna inaccesible" "
echo 'Bajando VPN...'
wg-quick down wg0 2>/dev/null
sleep 1
echo ''
echo 'fd00:2::1 (extremo WG) sin VPN — debe fallar:'
ping6 -c 2 -W 2 fd00:2::1 2>&1 | tail -2
echo ''
echo 'HTTP publico sigue funcionando sin VPN:'
curl -6 --max-time 4 -s http://[2001:db8:12::1]/ | grep h1
echo ''
echo 'Subiendo VPN de nuevo...'
wg-quick up wg0 2>/dev/null
sleep 3
echo 'Reconexion VPN:'
wg show 2>/dev/null | grep -E 'handshake|transfer'
"

echo ""
echo "============================================================"
echo "  PRUEBAS COMPLETADAS"
echo "============================================================"
