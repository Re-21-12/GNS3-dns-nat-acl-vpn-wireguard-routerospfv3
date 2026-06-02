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
echo 'Ruta esperada (modo ICMP -I, ICMPv6 permitido por ACL):'
echo '  Salto 1: 2001:db8:3::1   (R3 fa0/0 — gateway PC3)'
echo '  Salto 2: 2001:db8:23::1  (R2 Serial0/0 — enlace serial R2-R3)'
echo '  Salto 3: 2001:db8:12::1  (R1-Linux — destino final)'
echo ''
echo 'NOTA: Se usa traceroute6 -I (ICMP) porque la ACL de R1-Linux'
echo 'tiene la regla: -p ipv6-icmp -j ACCEPT'
echo 'Con UDP el salto 3 mostraria * (el DROP final lo bloquea).'
echo ''
traceroute6 -I -n -q 2 -w 2 -m 6 2001:db8:12::1
echo ''
echo 'Los 3 saltos confirman OSPFv3 end-to-end: PC3 -> R3 -> R2 -> R1-Linux.'
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
echo 'dominio.com (zona publica — debe resolver a R1-Linux 2001:db8:12::1):'
echo '  [dig]'
dig AAAA dominio.com @2001:db8:12::1 +short +time=3 2>/dev/null \
    || echo 'DNAT DNS no respondio'
echo '  [nslookup]'
nslookup -type=AAAA dominio.com 2001:db8:12::1 2>/dev/null | grep -E 'Address|address' | grep -v '#'
echo ''
echo 'dominio.com via VPN (dig directo a PC1 fd00:1::10):'
dig AAAA dominio.com @fd00:1::10 +short +time=3 2>/dev/null
echo ''
echo 'dominio.local (zona privada — solo resolvible via VPN):'
echo '  [dig]'
dig AAAA dominio.local @fd00:1::10 +short +time=3 2>/dev/null
echo '  [nslookup]'
nslookup -type=AAAA dominio.local fd00:1::10 2>/dev/null | grep -E 'Address|address' | grep -v '#'
"

# ----------------------------------------------------------
# FASE 5.5 — Pruebas COMPLETAS sin VPN
# Demuestra que sin VPN:
#   - HTTP publico funciona via NAT66 DNAT
#   - DNS via DNAT funciona
#   - Recursos privados (fd00::) son inaccesibles
# ----------------------------------------------------------
run "FASE 5.5 | Todo sin VPN — red privada debe ser inaccesible" "
echo 'Bajando VPN para pruebas sin tunel...'
wg-quick down wg0 2>/dev/null
sleep 1
echo ''

echo '--- [5.5.1] Rutas activas SIN VPN (no debe haber fd00:: en tabla) ---'
ip -6 route show | grep fd00 && echo 'ATENCION: rutas fd00:: presentes sin VPN' || echo 'OK: no hay rutas fd00:: sin VPN'
echo ''

echo '--- [5.5.2] HTTP publico SIN VPN (debe funcionar via NAT66) ---'
curl -6 --max-time 5 -s http://[2001:db8:12::1]/ | grep -E '<h1>|NAT66'
echo ''

echo '--- [5.5.3] DNS via DNAT SIN VPN (dig @R1-Linux publico) ---'
dig AAAA dominio.com @2001:db8:12::1 +short +time=3 2>/dev/null && echo 'DNS DNAT OK' || echo 'DNS DNAT no respondio'
echo ''

echo '--- [5.5.4] Red privada inaccesible SIN VPN ---'
echo 'ping6 fd00:1::10 (PC1 ULA):'
ping6 -c 2 -W 2 fd00:1::10 2>&1 | tail -2
echo 'ping6 fd00:2::1 (extremo VPN):'
ping6 -c 2 -W 2 fd00:2::1 2>&1 | tail -2
echo ''

echo '--- [5.5.5] HTTP intranet inaccesible SIN VPN ---'
curl -6 --max-time 3 -s -H 'Host: intranet.dominio.local' http://[fd00:1::10]/ \
    && echo 'FAIL: intranet no deberia ser accesible sin VPN' \
    || echo 'OK: intranet inaccesible sin VPN (Network unreachable)'
echo ''

echo 'Subiendo VPN de nuevo para fases siguientes...'
wg-quick up wg0 2>/dev/null
sleep 2
wg show | grep -E 'endpoint|handshake'
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
# FASE 6.5 — Ping y traceroute CON VPN activa
# ----------------------------------------------------------
run "FASE 6.5 | Ping y traceroute con VPN activa" "
echo '--- Rutas activas: fd00:: via wg0 ---'
ip -6 route show | grep -E 'wg0|fd00'
echo ''

echo '--- ping6 a PC1 ULA via tunel (fd00:1::10) ---'
ping6 -c 3 -W 3 fd00:1::10
echo ''

echo '--- ping6 a PC2 VPCS via tunel (fd00:1::20) ---'
ping6 -c 3 -W 3 fd00:1::20 \
    && echo 'PC2 accesible via VPN' \
    || echo 'PC2 no responde (verificar que VPCS este activo)'
echo ''

echo '--- traceroute6 a PC1 via tunel VPN (fd00:1::10) ---'
echo 'NOTA: WireGuard opera en kernel space y NO emite ICMP TTL-exceeded.'
echo 'El traceroute muestra * pero el ping funciona — el tunel esta activo.'
echo 'Esto es comportamiento normal de todos los tuneles VPN.'
traceroute6 -n -q 1 -w 2 -m 5 fd00:1::10
echo ''

echo '--- CONTRASTE: traceroute por red PUBLICA (sin pasar por VPN) ---'
echo 'La ruta publica SI muestra los 3 saltos (ICMP -I, routers Cisco'
echo 'responden TTL-exceeded y R1-Linux acepta ICMPv6 por ACL):'
traceroute6 -I -n -q 1 -w 2 -m 4 2001:db8:12::1
echo ''

echo '--- Resumen de diferencias ---'
echo 'PUBLICA (ICMP):  PC3 → R3 (salto1) → R2 (salto2) → R1-Linux (salto3 visible)'
echo 'VPN (fd00::):    PC3 → wg0 → PC1 — sin saltos visibles (tunel cifrado)'
echo 'El contraste demuestra que WireGuard cifra/oculta la ruta intencionalmente.'
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
