# Comandos de Referencia — Lab IPv6

## Acceso a los nodos

| Nodo | Acceso | IP(s) |
|------|--------|-------|
| **PC3** | `docker exec -it $(docker ps --filter name=GNS3.pc3 -q) bash` | `2001:db8:3::10` · wg0 `fd00:2::2` |
| **R1-Linux** | `docker exec -it $(docker ps --filter name=GNS3.r1 -q) bash` | eth0 `2001:db8:12::1` · eth1 `fd00:1::1` |
| **PC1** | `docker exec -it $(docker ps --filter name=GNS3.pc1 -q) bash` | `fd00:1::10` · wg0 `fd00:2::1` |
| **R2** | Consola GNS3 | fa0/0 `2001:db8:12::2` · s0/0 `2001:db8:23::1` |
| **R3** | Consola GNS3 | fa0/0 `2001:db8:3::1` · s0/0 `2001:db8:23::2` |

---

## 1. Direccionamiento IP — verificar IPs asignadas

| Nodo | IP(s) | Comando |
|------|-------|---------|
| **PC3** `2001:db8:3::10` | eth0 + wg0 | `ip -6 addr show` |
| **R1-Linux** `2001:db8:12::1` | eth0 + eth1 | `ip -6 addr show` |
| **PC1** `fd00:1::10` | eth0 + wg0 | `ip -6 addr show` |
| **R2** `2001:db8:12::2` | fa0/0 + s0/0 | `show ipv6 interface brief` |
| **R3** `2001:db8:3::1` | fa0/0 + s0/0 | `show ipv6 interface brief` |

```bash
# PC3 — eth0 publica + wg0 VPN
ip -6 addr show eth0
ip -6 addr show wg0

# R1-Linux — eth0 publica + eth1 LAN interna
ip -6 addr show eth0
ip -6 addr show eth1

# PC1 — ULA interna + wg0 VPN
ip -6 addr show eth0
ip -6 addr show wg0

# R2 (Cisco GNS3)
show ipv6 interface brief

# R3 (Cisco GNS3)
show ipv6 interface brief
```

---

## 2. Traceroute — verificar ruteo OSPFv3

Ruta esperada completa: `PC3 → R3 → R2 → R1-Linux`

| Origen | IP Origen | Destino | IP Destino | Comando |
|--------|-----------|---------|------------|---------|
| **PC3** | `2001:db8:3::10` | dominio.com (R1-Linux) | `2001:db8:12::1` | `traceroute6 -I -n 2001:db8:12::1` |
| **R3** | `2001:db8:3::1` | R1-Linux | `2001:db8:12::1` | `traceroute ipv6 2001:db8:12::1` |
| **R2** | `2001:db8:12::2` | PC3 | `2001:db8:3::10` | `traceroute ipv6 2001:db8:3::10` |

```bash
# Desde PC3 (usa -I para ICMP — la ACL de R1-Linux permite ipv6-icmp)
traceroute6 -I -n -q 2 -w 2 2001:db8:12::1
# Resultado esperado:
#  1  2001:db8:3::1    (R3 fa0/0)
#  2  2001:db8:23::1   (R2 s0/0)
#  3  2001:db8:12::1   (R1-Linux eth0)

# Desde R3 (Cisco GNS3)
traceroute ipv6 2001:db8:12::1

# Desde R2 (Cisco GNS3)
traceroute ipv6 2001:db8:3::10
```

> **Nota VPN:** `traceroute6 fd00:1::10` desde PC3 mostrará siempre `*`
> porque WireGuard es un tunel kernel-space que no emite ICMP TTL-exceeded.
> El ping con 0% perdida confirma que el tunel funciona.

---

## 3. Ping — conectividad por capas

| Origen | IP Origen | Destino | IP Destino | Comando |
|--------|-----------|---------|------------|---------|
| **PC3** | `2001:db8:3::10` | Gateway R3 | `2001:db8:3::1` | `ping6 -c 3 2001:db8:3::1` |
| **PC3** | `2001:db8:3::10` | R2 Serial | `2001:db8:23::1` | `ping6 -c 3 2001:db8:23::1` |
| **PC3** | `2001:db8:3::10` | R1-Linux | `2001:db8:12::1` | `ping6 -c 3 2001:db8:12::1` |
| **PC3** wg0 | `fd00:2::2` | PC1 wg0 | `fd00:2::1` | `ping6 -c 3 fd00:2::1` |
| **PC3** wg0 | `fd00:2::2` | PC1 ULA | `fd00:1::10` | `ping6 -c 3 fd00:1::10` |
| **R3** | `2001:db8:3::1` | PC1 ULA (via OSPFv3) | `fd00:1::10` | `ping ipv6 fd00:1::10` |

```bash
# Desde PC3 — red publica (sin VPN necesaria)
ping6 -c 3 2001:db8:3::1    # gateway R3
ping6 -c 3 2001:db8:23::1   # R2 Serial0/0
ping6 -c 3 2001:db8:12::2   # R2 FastEthernet0/0
ping6 -c 3 2001:db8:12::1   # R1-Linux (dominio.com)

# Desde PC3 — a traves de VPN WireGuard (wg0 debe estar activo)
ping6 -c 3 fd00:2::1        # extremo VPN servidor (PC1 wg0)
ping6 -c 3 fd00:1::10       # PC1 ULA — LAN interna via tunel

# Desde R3 (Cisco GNS3) — comprueba que OSPFv3 propago fd00:1::/64
ping ipv6 fd00:1::10
ping ipv6 fd00:1::1
```

---

## 4. DNS — resolución de nombres

| Origen | IP Origen | Servidor DNS | IP Servidor | Zona | Comando |
|--------|-----------|--------------|-------------|------|---------|
| **PC3** | `2001:db8:3::10` | R1-Linux DNAT | `2001:db8:12::1` | publica | `dig AAAA dominio.com @2001:db8:12::1` |
| **PC3** wg0 | `fd00:2::2` | PC1 directo | `fd00:1::10` | publica | `dig AAAA dominio.com @fd00:1::10` |
| **PC3** wg0 | `fd00:2::2` | PC1 directo | `fd00:1::10` | privada | `dig AAAA dominio.local @fd00:1::10` |

```bash
# Desde PC3 — zona publica via DNAT (R1-Linux redirige :53 a PC1)
dig  AAAA dominio.com @2001:db8:12::1 +short
# Esperado: 2001:db8:12::1

nslookup -type=AAAA dominio.com 2001:db8:12::1
# Esperado: Address: 2001:db8:12::1

# Desde PC3 — zona publica consultando PC1 directamente (via VPN)
dig AAAA dominio.com @fd00:1::10 +short
# Esperado: 2001:db8:12::1

# Desde PC3 — zona privada (solo accesible con VPN activa)
dig  AAAA dominio.local @fd00:1::10 +short
# Esperado: fd00:1::10

nslookup -type=AAAA dominio.local fd00:1::10
# Esperado: Address: fd00:1::10
```

---

## 5. HTTP — acceso web via NAT66

| Origen | IP Origen | Servidor | IP Destino | VPN | Comando |
|--------|-----------|----------|------------|-----|---------|
| **PC3** | `2001:db8:3::10` | dominio.com (NAT66 DNAT) | `2001:db8:12::1:80` | No | `curl -6 http://[2001:db8:12::1]/` |
| **PC3** | `2001:db8:3::10` | puerto bloqueado (ACL) | `2001:db8:12::1:8080` | No | `curl -6 http://[2001:db8:12::1]:8080/` |
| **PC3** wg0 | `fd00:2::2` | intranet.dominio.local | `fd00:1::10:80` | Si | `curl -6 -H 'Host: intranet.dominio.local' http://[fd00:1::10]/` |

```bash
# Desde PC3 — HTTP publico (R1-Linux hace DNAT :80 -> fd00:1::10:80)
curl -6 http://[2001:db8:12::1]/
# Esperado: HTML de dominio.com con "NAT66 DNAT en R1 → PC1 fd00:1::10"

# Desde PC3 — verificar que ACL bloquea puertos no permitidos
curl -6 --max-time 3 http://[2001:db8:12::1]:8080/
# Esperado: timeout (conexion rechazada por ip6tables DROP)

# Desde PC3 con VPN — intranet privada (solo accesible via tunel)
curl -6 -H 'Host: intranet.dominio.local' http://[fd00:1::10]/
# Esperado: HTML de intranet con "Recurso privado — solo accesible por VPN"
```

---

## 6. Reglas NAT y ACL — mostrar configuracion activa

### R1-Linux — ip6tables

| Nodo | IP | Tabla | Comando |
|------|----|-------|---------|
| **R1-Linux** | `2001:db8:12::1` | NAT PREROUTING (DNAT) | `ip6tables -t nat -L PREROUTING -n -v` |
| **R1-Linux** | `2001:db8:12::1` | NAT POSTROUTING (MASQUERADE) | `ip6tables -t nat -L POSTROUTING -n -v` |
| **R1-Linux** | `2001:db8:12::1` | Filter INPUT (ACL) | `ip6tables -L INPUT -n -v` |
| **R1-Linux** | `2001:db8:12::1` | Filter FORWARD | `ip6tables -L FORWARD -n -v` |

```bash
# Desde R1-Linux — ver todas las reglas NAT
ip6tables -t nat -L -n -v --line-numbers

# Desde R1-Linux — ver reglas DNAT especificas
ip6tables -t nat -L PREROUTING -n -v
# Esperado:
#   DNAT  tcp  eth0  :80    -> [fd00:1::10]:80
#   DNAT  tcp  eth0  :53    -> [fd00:1::10]:53
#   DNAT  udp  eth0  :53    -> [fd00:1::10]:53
#   DNAT  udp  eth0  :51820 -> [fd00:1::10]:51820

# Desde R1-Linux — ver reglas ACL (filtro en eth0 publica)
ip6tables -L INPUT -n -v
# Esperado:
#   ACCEPT  ospf   eth0  (OSPFv3 para adjacencia con R2)
#   ACCEPT  all    eth0  state ESTABLISHED,RELATED
#   ACCEPT  icmp6  eth0  (permite ping y traceroute -I)
#   ACCEPT  all    eth1  (LAN interna sin restriccion)
#   ACCEPT  all    lo
#   DROP    all    eth0  (bloquea todo lo demas)

# Desde R1-Linux — ver reglas FORWARD
ip6tables -L FORWARD -n -v
```

### R2 y R3 — Cisco IOS (GNS3)

```
# Verificar OSPFv3 activo y vecinos
show ipv6 ospf neighbor
show ipv6 ospf database

# Ver tabla de rutas IPv6 (rutas O = aprendidas por OSPFv3)
show ipv6 route
show ipv6 route ospf

# R2 — ver interfaces
show ipv6 interface fa0/0
show ipv6 interface s0/0

# R3 — ver interfaces
show ipv6 interface fa0/0
show ipv6 interface s0/0
```

---

## 7. WireGuard — estado VPN

| Nodo | IP | Comando |
|------|----|---------|
| **PC3** cliente | `fd00:2::2` | `wg show` |
| **PC1** servidor | `fd00:2::1` | `wg show` |

```bash
# Desde PC3 — estado del tunel cliente
wg show
# Campos clave:
#   endpoint: [2001:db8:12::1]:51820  <- R1-Linux que hace DNAT a PC1
#   allowed ips: fd00:1::/64, fd00:2::/64
#   latest handshake: X seconds ago   <- tunel activo

# Desde PC1 — estado del tunel servidor
wg show
# Campos clave:
#   listening port: 51820
#   peer: <clave publica PC3>
#   latest handshake: X seconds ago

# Subir/bajar VPN desde PC3
wg-quick up   wg0
wg-quick down wg0
```

---

## Resumen de IPs del laboratorio

```
PC3  eth0   2001:db8:3::10/64        Red publica cliente externo
     wg0    fd00:2::2/64             Extremo VPN cliente

R3   fa0/0  2001:db8:3::1/64        Gateway de PC3
     s0/0   2001:db8:23::2/64       Enlace serial hacia R2

R2   s0/0   2001:db8:23::1/64       Enlace serial hacia R3
     fa0/0  2001:db8:12::2/64       Enlace Ethernet hacia R1

R1   eth0   2001:db8:12::1/64       Interfaz publica (NAT66 + ACL)
     eth1   fd00:1::1/64            LAN interna (Switch1)

PC1  eth0   fd00:1::10/64           Servidor (nginx + BIND9)
     wg0    fd00:2::1/64            Extremo VPN servidor

PC2  eth0   fd00:1::20/64           VPCS (nodo de prueba interna)
```
