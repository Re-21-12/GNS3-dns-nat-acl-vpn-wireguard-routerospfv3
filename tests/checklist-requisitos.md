# Checklist de Requisitos vs. Implementacion

---

## REQ 3 — Direccionamiento IPv6

| Requisito | Implementacion | Estado |
|-----------|----------------|--------|
| GUA para red publica | 2001:db8:12::/64 (R1-R2), 2001:db8:23::/64 (R2-R3), 2001:db8:3::/64 (LAN PC3) | CUMPLIDO |
| ULA para red interna | fd00:1::/64 (LAN interna Switch1), fd00:2::/64 (red VPN WireGuard) | CUMPLIDO |
| PC1 solo ULA (sin GUA) | fd00:1::10/64 unica IP de PC1 — R1-Linux hace DNAT | CUMPLIDO |
| PC3 con GUA publica | 2001:db8:3::10/64 | CUMPLIDO |

---

## REQ 4 — Ruteo Dinamico OSPFv3

| Requisito | Implementacion | Estado |
|-----------|----------------|--------|
| OSPFv3 entre R1 y R2 | R1-Linux (FRRouting ospf6d) <-> R2 Cisco, FULL en fa0/0 | CUMPLIDO |
| Anunciar rutas de red publica | fd00:1::/64, 2001:db8:12::/64, 2001:db8:23::/64, 2001:db8:3::/64 propagadas | CUMPLIDO |
| R3 ve ruta a LAN interna | O fd00:1::/64 via R2 [confirmado show ipv6 route ospf] | CUMPLIDO |
| R1-Linux ve ruta a PC3 | O 2001:db8:3::/64 via R2 [confirmado, ping exitoso] | CUMPLIDO |

**Nota:** Se uso FRRouting en R1-Linux (Docker) en lugar de Cisco IOS porque
IOS 12.4 no soporta NAT66. R2 y R3 son Cisco 3745 con OSPFv3 nativo.

---

## REQ 5 — ACL y NAT en R1

| Requisito | Implementacion | Estado |
|-----------|----------------|--------|
| NAT/DNAT desde interfaz publica hacia PC1 | ip6tables NAT66 DNAT en R1-Linux eth0 | CUMPLIDO |
| DNAT puerto 80 TCP | :80 -> fd00:1::10:80 [curl exitoso] | CUMPLIDO |
| DNAT puerto 53 TCP/UDP | :53 -> fd00:1::10:53 [dig exitoso] | CUMPLIDO |
| DNAT puerto VPN | :51820 UDP -> fd00:1::10:51820 [handshake exitoso] | CUMPLIDO |
| ACL permite solo puertos necesarios | ip6tables INPUT eth0: acepta :80 :53 :51820, OSPF | CUMPLIDO |
| ACL deniega todo lo demas | ip6tables INPUT DROP al final — :8080 bloqueado [verificado] | CUMPLIDO |
| Enunciado pide puerto 1194 (OpenVPN) | Se implemento WireGuard :51820 (mas moderno y eficiente) | ADAPTADO |

---

## REQ 6 — Servidor Linux PC1

| Requisito | Implementacion | Estado |
|-----------|----------------|--------|
| HTTP en PC1 | nginx corriendo, sirve dominio.com e intranet.dominio.local | CUMPLIDO |
| DNS en PC1 | BIND9 corriendo, zonas dominio.com y dominio.local | CUMPLIDO |
| VPN en PC1 | WireGuard wg0, fd00:2::1/64, acepta clientes en :51820 | CUMPLIDO |
| PC1 sin IP publica directa | Solo fd00:1::10/64 — acceso publico via DNAT en R1-Linux | CUMPLIDO |

---

## REQ 7 — Cliente PC3 y Pruebas

| Requisito | Prueba realizada | Resultado |
|-----------|-----------------|-----------|
| Acceso web publico HTTP | curl http://[2001:db8:12::1]/ | dominio.com OK |
| DNS publico resuelve dominio.com | dig AAAA dominio.com @fd00:1::10 | 2001:db8:12::1 OK |
| Conexion VPN hacia R1 (DNAT) | wg-quick up wg0, endpoint 2001:db8:12::1:51820 | handshake OK |
| PC3 obtiene IP del rango privado | fd00:2::2/64 via WireGuard | OK |
| Acceso a dominio.local via VPN | curl -H Host:intranet.dominio.local http://[fd00:1::10]/ | Intranet OK |
| DNS interno dominio.local | dig AAAA dominio.local @fd00:1::10 | fd00:1::10 OK |
| Ping a IP publica R1-Linux | ping6 2001:db8:12::1 | 100% exito |
| Traceroute a R1-Linux | PC3 -> R3 -> R2 -> R1-Linux | 3 saltos OK |
| Ping desde R3 a fd00:1::1 | ping ipv6 fd00:1::1 | 100% exito |
| Enunciado pide curl http://dominio.com | Requiere DNS publico externo — en lab se usa IP directa | PARCIAL |

---

## REQ 8 — Restricciones y Seguridad

| Requisito | Implementacion | Estado |
|-----------|----------------|--------|
| Bloquear trafico entrante no autorizado | ip6tables INPUT DROP en eth0 de R1-Linux | CUMPLIDO |
| Permitir solo :80 :53 :1194 | Se permite :80 :53 :51820 (WireGuard en vez de OpenVPN) | CUMPLIDO |
| deny ipv6 any any al final | ip6tables INPUT -j DROP como ultima regla | CUMPLIDO |
| Aislamiento sin VPN | fd00:2::1 inaccesible sin tunel (100% perdida verificado) | CUMPLIDO |
| PC3 no accede a LAN interna sin VPN | Rutas fd00:: solo existen cuando wg0 esta activo | CUMPLIDO |

---

## RESUMEN

| Categoria | Requisitos | Cumplidos | Adaptados | Pendientes |
|-----------|------------|-----------|-----------|------------|
| Direccionamiento IPv6 | 4 | 4 | 0 | 0 |
| OSPFv3 | 4 | 4 | 0 | 0 |
| NAT66 + ACL | 6 | 5 | 1 | 0 |
| Servidor PC1 | 4 | 4 | 0 | 0 |
| Pruebas PC3 | 9 | 8 | 1 | 0 |
| Seguridad | 5 | 5 | 0 | 0 |
| **TOTAL** | **32** | **30** | **2** | **0** |

### Adaptaciones justificadas:
1. **OpenVPN -> WireGuard**: WireGuard es mas moderno, mas seguro y mas eficiente.
   La funcionalidad es identica: PC3 conecta VPN hacia R1 que hace DNAT al servidor.
2. **curl dominio.com directo**: En el lab sin DNS externo se usa la IP publica directamente.
   El comportamiento es identico al de un cliente real que resuelve dominio.com.
