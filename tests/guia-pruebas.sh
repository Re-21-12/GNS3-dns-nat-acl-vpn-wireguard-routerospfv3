#!/bin/bash
# ============================================================
# GUIA DE PRUEBAS — v5 (R1-Linux Docker + NAT66)
#
# Arquitectura:
#   R1-Linux (Docker) : gateway + NAT66 DNAT + OSPFv3 (FRR)
#   R2 (Cisco 3745)   : OSPFv3, fa0/0→R1, s0/1→R3
#   R3 (Cisco 3745)   : OSPFv3, s0/0→R2, fa0/0→Switch2
#   PC1 (Docker)      : servidor HTTP+DNS+WG, SOLO ULA fd00:1::10
#   PC3 (Docker)      : cliente externo, 2001:db8:3::10
# ============================================================

cat << 'MAPA'
================================================================
  TOPOLOGIA Y CONEXIONES FISICAS — GNS3
================================================================

  R1-Linux eth1 ──── Switch1 Ethernet0   (cable ya tendido)
  R1-Linux eth0 ──── R2 FastEthernet0/0  (Ethernet — no serial)
  R2 Serial0/1  ──── R3 Serial0/0        (serial)
  R3 FastEth0/0 ──── Switch2 Ethernet0   (cable ya tendido)

  PC1 eth0 ──── Switch1 Ethernet2
  PC2 eth0 ──── Switch1 Ethernet1
  PC3 eth0 ──── Switch2 Ethernet1

  IMPORTANTE: R1 es Docker Linux (NO Cisco).
              R1-R2 debe ser Ethernet (fa0/0 en R2).
================================================================
MAPA

cat << 'PRELAB'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PASO PREVIO: Build de imagenes Docker
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

En el host GNS3 (no dentro de contenedores):

  chmod +x generar-claves-y-rebuild.sh
  ./generar-claves-y-rebuild.sh

Esto genera claves WireGuard reales y hace:
  docker build -t r1-linux     docker/r1-linux/
  docker build -t pc1-servidor docker/pc1-servidor/
  docker build -t pc3-cliente  docker/pc3-cliente/

Templates Docker en GNS3:
  r1-linux     → 2 adaptadores de red (eth0 + eth1)
  pc1-servidor → 1 adaptador
  pc3-cliente  → 1 adaptador

Persistent Directories:
  r1-linux     : /etc/frr
  pc1-servidor : /etc/wireguard, /etc/bind/zones, /var/www, /var/log/nginx, /etc/network/interfaces.d
  pc3-cliente  : /etc/wireguard, /etc/network/interfaces.d
PRELAB

cat << 'F1'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  FASE 1: R1-Linux (Docker)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PASO 1.1 — Verificar IPs en R1-Linux
  ip -6 addr show eth0
  ESPERADO: 2001:db8:12::1/64  (RED PUBLICA — hacia R2)

  ip -6 addr show eth1
  ESPERADO: fd00:1::1/64       (LAN interna — hacia Switch1)

PASO 1.2 — Verificar ip6tables NAT66
  ip6tables -t nat -L PREROUTING -n -v
  ESPERADO (4 reglas DNAT en eth0):
    DNAT  tcp  dpt:80    to: [fd00:1::10]:80
    DNAT  tcp  dpt:53    to: [fd00:1::10]:53
    DNAT  udp  dpt:53    to: [fd00:1::10]:53
    DNAT  udp  dpt:51820 to: [fd00:1::10]:51820

  ip6tables -t nat -L POSTROUTING -n -v
  ESPERADO: MASQUERADE en eth1

PASO 1.3 — Verificar FRR/OSPFv3
  vtysh -c "show ipv6 ospf6 interface"
  vtysh -c "show ipv6 ospf6 neighbor"
  ESPERADO (tras 30-60s): vecino 2.2.2.2 en eth0

PASO 1.4 — Ping hacia R2
  ping6 -c 3 2001:db8:12::2   (R2 fa0/0)
  ESPERADO: respuesta OK
F1

cat << 'F2'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  FASE 2: Routers Cisco (R2 y R3)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PASO 2.1 — Aplicar configs (copiar/pegar en consola GNS3)
  R2 ← routers/R2/r2-config.txt
  R3 ← routers/R3/r3-config.txt

PASO 2.2 — Verificar R2
  R2# show ipv6 interface brief
  ESPERADO:
    FastEthernet0/0  [up/up]  2001:db8:12::2
    Serial0/1        [up/up]  2001:db8:23::1

  R2# show ipv6 ospf neighbor
  ESPERADO: 1.1.1.1 FULL (R1-Linux), 3.3.3.3 FULL (R3)

PASO 2.3 — Verificar R3
  R3# show ipv6 interface brief
  ESPERADO:
    Serial0/0        [up/up]  2001:db8:23::2
    FastEthernet0/0  [up/up]  2001:db8:3::1

  R3# show ipv6 ospf neighbor
  ESPERADO: 2.2.2.2 FULL (R2)

PASO 2.4 — Pings entre routers via OSPFv3
  R2# ping ipv6 2001:db8:12::1   (R1-Linux eth0)
  R2# ping ipv6 2001:db8:23::2   (R3)
  R3# ping ipv6 2001:db8:12::1   (R1-Linux — via R2)
  TODOS deben responder.

PASO 2.5 — Verificar rutas en R3 (debe ver red de PC1 via OSPFv3)
  R3# show ipv6 route ospf
  ESPERADO: O   fd00:1::/64 via 2001:db8:23::1 (R2→R1)
F2

cat << 'F3'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  FASE 3: PC1 servidor (Docker)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PASO 3.1 — Verificar IP (SOLO ULA, sin GUA publica)
  ip -6 addr show eth0
  ESPERADO:
    inet6 fd00:1::10/64   scope global   ← ULA interna
    inet6 fe80::...       scope link
  NO debe aparecer ninguna 2001:db8:: — R1-Linux hace el DNAT.

PASO 3.2 — Verificar gateway
  ip -6 route show default
  ESPERADO: default via fd00:1::1 dev eth0   (R1-Linux eth1)

PASO 3.3 — Ping desde R1-Linux hacia PC1
  (en R1-Linux): ping6 -c 3 fd00:1::10
  ESPERADO: respuesta OK (misma LAN via Switch1)

PASO 3.4 — Verificar servicios en PC1
  # BIND9
  dig AAAA dominio.com   @::1
  ESPERADO: 2001:db8:12::1 (R1-Linux IP publica)

  dig AAAA dominio.local @::1
  ESPERADO: fd00:1::10

  # Nginx
  curl -6 http://[::1]/
  ESPERADO: HTML "dominio.com"

  # WireGuard
  wg show
  ESPERADO: interface wg0 activa, fd00:2::1

PASO 3.5 — Verificar DNAT desde R1-Linux (simular peticion externa)
  (en R1-Linux): curl -6 http://[fd00:1::10]/
  ESPERADO: HTML "dominio.com"
  (conectividad directa antes de DNAT — valida que PC1 responde)
F3

cat << 'F4'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  FASE 4: PC2 VPCS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

PASO 4.1 — Configurar VPCS
  ip fd00:1::20/64 fd00:1::1
  save

PASO 4.2 — Pruebas desde PC2
  ping fd00:1::1    (R1-Linux eth1)  ← mismo Switch1
  ping fd00:1::10   (PC1)            ← mismo Switch1
  AMBOS deben responder.
F4

cat << 'F5'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  FASE 5: PC3 cliente externo (sin VPN)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Ruta fisica:
  PC3→SW2→R3-fa0/0→R3-s0/0→R2-s0/1→R2-fa0/0
    →R1-Linux eth0 [ACL+DNAT] →eth1→Switch1→PC1

PASO 5.1 — Verificar IP de PC3
  ip -6 addr show eth0
  ESPERADO: inet6 2001:db8:3::10/64

  ip -6 route show default
  ESPERADO: default via 2001:db8:3::1 (R3 fa0/0)

PASO 5.2 — Traceroute al servidor
  traceroute6 2001:db8:12::1
  ESPERADO:
    1  2001:db8:3::1    (R3 fa0/0)
    2  2001:db8:23::1   (R2 s0/1)
    3  2001:db8:12::1   (R1-Linux eth0)

PASO 5.3 — HTTP publico (sin VPN)
  curl -6 http://[2001:db8:12::1]/
  ESPERADO: HTML "dominio.com" con "NAT66 DNAT en R1"

  Que paso: PC3→R1 eth0:80 → DNAT → eth1→PC1:80 → respuesta

PASO 5.4 — Verificar ACL bloquea otros puertos
  curl -6 --connect-timeout 3 http://[2001:db8:12::1]:8080
  ESPERADO: timeout (bloqueado por ACL ip6tables INPUT DROP)

PASO 5.5 — Confirmar que PC1 ULA NO es accesible directamente
  ping6 -c 2 fd00:1::10
  ESPERADO: Network unreachable (PC3 no tiene ruta a fd00::/48)
F5

cat << 'F6'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  FASE 6: VPN WireGuard (PC3 → R1 → PC1)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Flujo:
  PC3 → UDP[2001:db8:12::1]:51820
      → R1-Linux DNAT → [fd00:1::10]:51820
      → PC1 WireGuard
      → PC3 obtiene fd00:2::2/64

PASO 6.1 — Activar VPN en PC3
  wg-quick up wg0

PASO 6.2 — Verificar handshake
  wg show
  BUSCAR: latest handshake: X seconds ago
          transfer: X B received, X B sent

  Si NO hay handshake:
    1. Verificar PC1 activo: (en PC1) wg show
    2. Endpoint en wg0.conf debe ser [2001:db8:12::1]:51820
    3. Ping a R1 sin VPN: ping6 2001:db8:12::1 (debe responder)
    4. R1 ACL permite :51820: (en R1) ip6tables -L INPUT -n -v
    5. R1 DNAT activo: (en R1) ip6tables -t nat -L PREROUTING -n

PASO 6.3 — Verificar rutas con VPN activa
  ip -6 route show
  ESPERADO: fd00::/48 via fd00:2::1 dev wg0 (ruta por VPN)

PASO 6.4 — Acceso a red interna (solo con VPN)
  ping6 fd00:2::1     (PC1 extremo WG)
  ping6 fd00:1::10      (PC1 ULA — accesible via VPN)
  ping6 fd00:1::20      (PC2 VPCS — accesible via VPN)
  TODOS deben responder.

PASO 6.5 — Intranet privada
  curl -6 http://[fd00:1::10]/
  ESPERADO: HTML "Intranet — dominio.local"

  curl -6 -H "Host: intranet.dominio.local" http://[fd00:1::10]/
  ESPERADO: misma pagina intranet

PASO 6.6 — DNS con VPN activa
  dig AAAA dominio.local @fd00:1::10
  ESPERADO: fd00:1::10

  dig AAAA dominio.com   @fd00:1::10
  ESPERADO: 2001:db8:12::1

PASO 6.7 — Confirmar que sin VPN NO hay acceso interno
  wg-quick down wg0
  ping6 fd00:1::10
  ESPERADO: Network unreachable
  wg-quick up wg0
F6

cat << 'RESUMEN'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  RESUMEN DE VERIFICACION FINAL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  [ ] R1-Linux: 2001:db8:12::1/eth0, fd00:1::1/eth1
  [ ] R1-Linux: ip6tables DNAT activo (:80 :53 :51820)
  [ ] R1-Linux: OSPFv3 vecino R2 (2.2.2.2) FULL
  [ ] R2: OSPF vecinos R1 + R3 FULL
  [ ] R3: OSPF vecino R2 FULL, ruta fd00:1::/64 visible
  [ ] PC1: fd00:1::10/64 (SOLO ULA), GW fd00:1::1
  [ ] PC1: nginx, bind9, wg0 activos
  [ ] PC2: fd00:1::20/64, ping a PC1 y R1 OK
  [ ] PC3: 2001:db8:3::10/64, curl http://[2001:db8:12::1]/ OK
  [ ] PC3: wg-quick up wg0, handshake con PC1 OK
  [ ] PC3+VPN: acceso a fd00:1::10 (intranet) OK
  [ ] PC3 sin VPN: fd00:1::10 NO accesible

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  CABLES GNS3 (orden de conexion)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. R1-Linux eth1  <-> Switch1 Ethernet0  (ya tendido)
  2. R3 fa0/0       <-> Switch2 Ethernet0  (ya tendido)
  3. R1-Linux eth0  <-> R2 FastEthernet0/0 (ETHERNET)
  4. R2 Serial0/1   <-> R3 Serial0/0       (serial)
  5. PC1 eth0       <-> Switch1 Ethernet2
  6. PC2 eth0       <-> Switch1 Ethernet1
  7. PC3 eth0       <-> Switch2 Ethernet1
RESUMEN
