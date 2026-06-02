# CONTEXTO DE PROYECTO — Lab IPv6 GNS3

# Pegar este archivo completo al inicio de una nueva sesión de Claude

# para continuar exactamente donde se dejó.

## OBJETIVO DEL LABORATORIO

Diseñar e implementar una red IPv6 completa en GNS3 que:

- Conecta dominio.com (público) y dominio.local (privado)
- Usa ruteo dinámico OSPFv3 en la red pública
- R1 aplica ACL + NAT66 DNAT para HTTP(:80), DNS(:53), WireGuard(:51820)
- PC1 (Docker) es servidor HTTP + DNS + VPN WireGuard
- PC3 (Docker) es cliente externo que accede a dominio.com sin VPN
  y a dominio.local solo a través de VPN WireGuard hacia R1

---

## TOPOLOGÍA REAL (según imagen GNS3)

```
                        R2 (Cisco 3745)
                       /               \
              R1-Linux                  R3 (Cisco 3745)
              (Docker)                  |
                 |                   Switch2
              Switch1              (Built-in GNS3)
           (Built-in GNS3)            |
          /           \            pc3-cliente
       PC2            pc1-servidor  (Docker)
      (VPCS)           (Docker)
```

### Conexiones físicas exactas en GNS3:

| Cable | Desde             | Hacia                                       |
| ----- | ----------------- | ------------------------------------------- |
| 1     | R1-Linux eth0     | Switch1 Puerto 0                            |
| 2     | R1-Linux eth1     | R2 fa0/0 (Ethernet, no serial)              |
| 3     | R2 fa0/1          | R3 Serial0/0 (o fa0/1 según disponibilidad) |
| 4     | R3 fa0/0          | Switch2 Puerto 0                            |
| 5     | PC2 VPCS eth0     | Switch1 Puerto 1                            |
| 6     | pc1-servidor eth0 | Switch1 Puerto 2                            |
| 7     | pc3-cliente eth0  | Switch2 Puerto 1                            |

### Puertos de Switch GNS3 — CONFIRMADOS

- Switch1 Ethernet0 → R1-Linux eth1  (LAN interna, cable ya tendido)
- Switch1 Ethernet1 → PC2 VPCS eth0
- Switch1 Ethernet2 → pc1-servidor eth0   ← CONFIRMADO
- Switch2 Ethernet0 → R3 fa0/0       (cable ya tendido)
- Switch2 Ethernet1 → pc3-cliente eth0    ← CONFIRMADO

### Interfaces R1-Linux — CONFIRMADAS

- eth0 → R2 fa0/0  (Red pública 2001:db8:12::1/64)
- eth1 → Switch1 Ethernet0  (LAN interna fd00:1::1/64)

---

## DIRECCIONAMIENTO IPv6

| Dispositivo  | Interfaz  | Dirección         | Rol                           |
| ------------ | --------- | ----------------- | ----------------------------- |
| R1-Linux     | eth0      | fd00:1::1/64      | Gateway LAN interna           |
| R1-Linux     | eth1      | 2001:db8:12::1/64 | IP pública — punto de entrada |
| R2           | fa0/0     | 2001:db8:12::2/64 | hacia R1-Linux                |
| R2           | fa0/1     | 2001:db8:23::1/64 | hacia R3                      |
| R3           | Serial0/0 | 2001:db8:23::2/64 | hacia R2                      |
| R3           | fa0/0     | 2001:db8:3::1/64  | Gateway LAN PC3               |
| pc1-servidor | eth0      | fd00:1::10/64     | SOLO ULA — sin GUA pública    |
| PC2 VPCS     | eth0      | fd00:1::20/64     | Cliente interno               |
| pc3-cliente  | eth0      | 2001:db8:3::10/64 | Cliente externo               |
| pc1-servidor | wg0       | fd00:vpn::1/64    | Extremo VPN servidor          |
| pc3-cliente  | wg0       | fd00:vpn::2/64    | Extremo VPN cliente           |

---

## DECISIONES DE DISEÑO IMPORTANTES

### Por qué R1 es Docker Linux y no Cisco 3745:

- La imagen c3745-advipservicesk9-mz.124-25d NO soporta NAT66 ni NPTv6
- IOS 12.4 clásico no tiene el comando `ipv6 nat` — solo IOS-XE lo tiene
- Solución: R1-Linux Docker con Ubuntu 22.04 + FRRouting (OSPFv3) + ip6tables (NAT66 DNAT)
- R2 y R3 siguen siendo Cisco 3745 IOS 12.4 — ellos solo hacen OSPFv3

### Por qué PC1 solo tiene ULA (sin GUA pública):

- El enunciado exige que R1 haga el NAT — PC1 no debe ser visible directamente
- R1-Linux hace DNAT: 2001:db8:12::1:{80,53,51820} → fd00:1::10:{80,53,51820}
- PC1 solo tiene fd00:1::10/64

### Por qué el endpoint VPN de PC3 apunta a R1 y no a PC1:

- El enunciado dice "PC3 inicia VPN hacia R1 que redirige el puerto"
- wg0.conf de PC3: Endpoint = [2001:db8:12::1]:51820
- R1-Linux hace DNAT :51820 → fd00:1::10:51820

### Switch GNS3:

- Se usa Ethernet Switch built-in de GNS3 (no Cisco, no Docker)
- Tiene 8 puertos por defecto, ampliable a 48 en Configure → Ports
- No necesita configuración IPv6 — es capa 2 pura

---

## ESTRUCTURA DE ARCHIVOS (versión final v5)

```
lab-ipv6-v5/
├── docker/
│   ├── r1-linux/                  ← NUEVO en v5
│   │   ├── Dockerfile             (Ubuntu + FRR + ip6tables)
│   │   ├── configs/frr/
│   │   │   ├── frr.conf           (OSPFv3 router-id 1.1.1.1)
│   │   │   └── daemons            (zebra=yes, ospf6d=yes)
│   │   └── scripts/start.sh       (IPs + NAT66 DNAT + ACL + FRR)
│   ├── pc1-servidor/
│   │   ├── Dockerfile             (Ubuntu + nginx + bind9 + wireguard)
│   │   ├── configs/
│   │   │   ├── nginx/             (dominio.com.conf, intranet.conf)
│   │   │   ├── bind/              (named.conf.local, options, zonas)
│   │   │   └── wireguard/         (wg0.conf — generado por script)
│   │   ├── web/                   (index.html dominio.com e intranet)
│   │   └── scripts/start.sh       (configura ULA, ip6tables, servicios)
│   └── pc3-cliente/
│       ├── Dockerfile             (Ubuntu + wireguard)
│       ├── configs/wireguard/     (wg0-client.conf — generado por script)
│       └── scripts/start.sh       (configura IPv6, levanta VPN)
├── routers/
│   ├── R2/r2-config.txt           (Cisco 3745 — OSPFv3 fa0/0 y fa0/1)
│   └── R3/r3-config.txt           (Cisco 3745 — OSPFv3 s0/0 y fa0/0)
├── generar-claves-y-rebuild.sh    (genera claves WG y hace docker build x3)
└── guia-pruebas.sh                (6 fases de verificación paso a paso)
```

---

## CONFIGURACIÓN R1-Linux (lo más importante)

### IPs:

- eth0: fd00:1::1/64 (LAN interna)
- eth1: 2001:db8:12::1/64 (red pública)

### NAT66 DNAT (ip6tables):

```bash
ip6tables -t nat -A PREROUTING -i eth1 -p tcp --dport 80   -j DNAT --to-destination [fd00:1::10]:80
ip6tables -t nat -A PREROUTING -i eth1 -p tcp --dport 53   -j DNAT --to-destination [fd00:1::10]:53
ip6tables -t nat -A PREROUTING -i eth1 -p udp --dport 53   -j DNAT --to-destination [fd00:1::10]:53
ip6tables -t nat -A PREROUTING -i eth1 -p udp --dport 51820 -j DNAT --to-destination [fd00:1::10]:51820
ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

### ACL (ip6tables) — bloquea todo excepto puertos permitidos:

```bash
ip6tables -A INPUT -i eth1 -m state --state ESTABLISHED,RELATED -j ACCEPT
ip6tables -A INPUT -i eth1 -p icmpv6 -j ACCEPT
ip6tables -A INPUT -i eth0 -j ACCEPT
ip6tables -A INPUT -i lo   -j ACCEPT
ip6tables -A INPUT -i eth1 -j DROP
ip6tables -A FORWARD -i eth1 -o eth0 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
ip6tables -A FORWARD -i eth0 -o eth1 -m state --state ESTABLISHED,RELATED -j ACCEPT
```

### OSPFv3 (FRR):

```
router ospf6
 ospf6 router-id 1.1.1.1
 interface eth1 area 0.0.0.0
 interface eth0 area 0.0.0.0
```

---

## CONFIGURACIÓN R2 (Cisco 3745 IOS 12.4)

```cisco
ipv6 unicast-routing
ipv6 cef
interface FastEthernet0/0
 ipv6 address 2001:db8:12::2/64
 ipv6 ospf 1 area 0
 no shutdown
interface FastEthernet0/1
 ipv6 address 2001:db8:23::1/64
 ipv6 ospf 1 area 0
 no shutdown
ipv6 router ospf 1
 router-id 2.2.2.2
```

## CONFIGURACIÓN R3 (Cisco 3745 IOS 12.4)

```cisco
ipv6 unicast-routing
ipv6 cef
interface Serial0/0
 ipv6 address 2001:db8:23::2/64
 ipv6 ospf 1 area 0
 no shutdown
interface FastEthernet0/0
 ipv6 address 2001:db8:3::1/64
 ipv6 ospf 1 area 0
 no shutdown
ipv6 router ospf 1
 router-id 3.3.3.3
 passive-interface FastEthernet0/0
```

---

## PC2 VPCS

```
ip fd00:1::20/64 fd00:1::1
save
```

---

## PERSISTENT DIRECTORIES en GNS3

### r1-linux:

```
/etc/frr
/etc/network/interfaces.d
```

### pc1-servidor:

```
/etc/wireguard
/etc/bind/zones
/var/www
/var/log/nginx
/etc/network/interfaces.d
```

### pc3-cliente:

```
/etc/wireguard
/etc/network/interfaces.d
```

### r1-linux — Network adapters: 2 (eth0 + eth1)

---

## FLUJO DE TRÁFICO COMPLETO

### Sin VPN:

```
PC3 (2001:db8:3::10)
 → R3 fa0/0 (2001:db8:3::1)
 → R2 fa0/1 (2001:db8:23::1) via OSPFv3
 → R1-Linux eth1 (2001:db8:12::1)
   [ACL: permite :80 :53 :51820 — bloquea resto]
   [DNAT: :80 → fd00:1::10:80]
 → PC1 nginx responde
```

### Con VPN:

```
PC3 → R3 → R2 → R1-Linux eth1:51820
  [ACL permite :51820]
  [DNAT: :51820 → fd00:1::10:51820]
  → PC1 WireGuard establece túnel
  → PC3 obtiene fd00:vpn::2
  → PC3 accede a fd00:1::10 (intranet.dominio.local)
```

### DNS:

```
dominio.com   → 2001:db8:12::1 (IP pública R1-Linux)
dominio.local → fd00:1::10     (solo accesible por VPN)
```

---

## PASOS PARA CONTINUAR

1. Descargar lab-ipv6-v5-nat66-real.tar.gz
2. Ejecutar: ./generar-claves-y-rebuild.sh
   (genera claves WireGuard y hace docker build de las 3 imágenes)
3. En GNS3:
   - Agregar templates Docker: r1-linux (2 adaptadores), pc1-servidor, pc3-cliente
   - Configurar Persistent Directories por template
   - Conectar cables según tabla de topología
4. Aplicar configs a R2 y R3 (Cisco IOS)
5. Configurar PC2 VPCS: ip fd00:1::20/64 fd00:1::1 + save
6. Seguir guia-pruebas.sh fase por fase

## ARCHIVOS ENTREGADOS (todos en outputs):

- lab-ipv6-v5-nat66-real.tar.gz ← versión final con todo
- guia-pruebas-v5.sh
- generar-claves-v5.sh
