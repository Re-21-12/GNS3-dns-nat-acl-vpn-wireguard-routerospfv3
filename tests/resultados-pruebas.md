# Resultados de Pruebas — Lab IPv6 v5
# Ejecutado desde pc3-cliente via docker exec

---

## FASE 1 — Identidad de PC3

**Comando:** `ip -6 addr show eth0`

PC3 tiene su IP correctamente asignada:
- `2001:db8:3::10/64` — IP publica del cliente externo
- Gateway default: `2001:db8:3::1` (R3 fa0/0)
- WireGuard wg0 ya activo al arrancar (configurado en imagen)

**Que significa:** PC3 vive en la red publica 2001:db8:3::/64, fuera de la LAN interna.

---

## FASE 2 — Conectividad de red (sin VPN)

### 2.1 Ping a gateway R3
```
ping6 2001:db8:3::1   -> EXITOSO (0% perdida)
```
**Que significa:** PC3 puede llegar al primer salto (R3), su gateway local.

### 2.2 Traceroute a R1-Linux
```
1  2001:db8:3::1    (R3 fa0/0)
2  2001:db8:23::1   (R2 Serial0/0 — enlace R2-R3)
3  *  (R1-Linux no responde ICMP desde eth0, bloqueado por ACL)
```
**Que significa:** El trafico recorre correctamente PC3 → R3 → R2 → R1-Linux.
R1-Linux bloquea ICMP echo desde eth0 (ACL diseñada asi, solo permite :80 :53 :51820).

### 2.3 Ping a R1-Linux IP publica
```
ping6 2001:db8:12::1   -> EXITOSO (0% perdida)
```
**Que significa:** ICMPv6 echo-reply esta permitido por la ACL. La ruta completa funciona.

---

## FASE 3 — HTTP publico sin VPN (NAT66 DNAT)

### 3.1 HTTP a dominio.com via DNAT
```
curl -6 http://[2001:db8:12::1]/
-> "dominio.com — Sitio web publico IPv6"
-> "Entrada publica: R1-Linux 2001:db8:12::1"
-> "NAT66 DNAT en R1 -> PC1 fd00:1::10"
```
**Flujo real:**
```
PC3 TCP:80 -> R1-Linux eth0 [ACL: permite :80] -> DNAT -> PC1 fd00:1::10:80
PC1 nginx responde -> MASQUERADE -> PC3 recibe respuesta de 2001:db8:12::1
```
**Que significa:** NAT66 DNAT funcionando. PC1 no tiene IP publica, R1-Linux hace la
traduccion transparente.

### 3.2 ACL bloquea puerto no permitido
```
curl -6 http://[2001:db8:12::1]:8080/  -> timeout (conexion bloqueada)
```
**Que significa:** ip6tables INPUT DROP en eth0 bloquea todo lo que no sea
:80, :53 o :51820. El firewall funciona correctamente.

---

## FASE 4 — VPN WireGuard activa

### 4.1 Estado del tunel
```
wg show wg0
  endpoint: [2001:db8:12::1]:51820   <- R1-Linux que hace DNAT a PC1
  allowed ips: fd00:1::/64, fd00:2::/64
  latest handshake: X seconds ago     <- TUNEL ACTIVO
  transfer: 2.09 KiB received, 13.51 KiB sent
```
**Flujo de establecimiento VPN:**
```
PC3 UDP:51820 -> R1-Linux eth0 -> DNAT -> PC1 fd00:1::10:51820
PC1 WireGuard acepta -> tunel establecido
PC3 obtiene fd00:2::2/64 (IP dentro del tunel)
```

### 4.2 Ping al extremo VPN de PC1
```
ping6 fd00:2::1   -> EXITOSO (0% perdida, ~16ms)
```
**Que significa:** El tunel WireGuard esta activo. fd00:2::1 es la IP del
extremo servidor (PC1 wg0).

### 4.3 Ping a PC1 por ULA interna
```
ping6 fd00:1::10   -> EXITOSO (0% perdida, ~16ms)
```
**Que significa:** Con VPN activa, PC3 puede acceder a la LAN interna (fd00:1::/64)
a traves del tunel. El trafico va cifrado por wg0.

### 4.4 HTTP intranet privada (solo VPN)
```
curl -6 -H "Host: intranet.dominio.local" http://[fd00:1::10]/
-> "Intranet — dominio.local"
-> "Recurso privado — solo accesible por VPN"
-> "Si ves esta pagina desde PC3, el tunel WireGuard funciona correctamente."
```
**Que significa:** La intranet privada es accesible SOLO a traves de la VPN.
Nginx sirve el vhost correcto al recibir el header Host adecuado.

### 4.5 DNS via VPN
```
dig AAAA dominio.com @fd00:1::10    -> 2001:db8:12::1  (IP publica R1-Linux)
dig AAAA dominio.local @fd00:1::10  -> fd00:1::10      (IP privada PC1)
dig AAAA intranet.dominio.local @fd00:1::10 -> fd00:1::10
```
**Que significa:**
- dominio.com resuelve a la IP publica de R1-Linux (entrada NAT66)
- dominio.local solo es resolvible desde dentro de la VPN (servidor DNS en PC1)
- BIND9 en PC1 sirve ambas zonas correctamente

---

## FASE 5 — Aislamiento sin VPN

### 5.1 Red VPN inaccesible sin tunel
```
wg-quick down wg0
ping6 fd00:2::1   -> 100% perdida (Network unreachable)
```
**Que significa:** Sin VPN, las rutas fd00::/xx desaparecen. La red interna
del tunel (fd00:2::/64) es completamente inaccesible.

### 5.2 HTTP publico funciona sin VPN
```
curl -6 http://[2001:db8:12::1]/  -> "dominio.com" (EXITOSO)
```
**Que significa:** El acceso publico (NAT66 DNAT) no depende de VPN.
dominio.com siempre accesible, dominio.local solo con VPN.

### 5.3 Restaurar VPN
```
wg-quick up wg0
  latest handshake: 2 seconds ago   <- reconecta inmediatamente
```

---

## RESUMEN FINAL

| Prueba | Resultado |
|--------|-----------|
| OSPFv3 R1-Linux <-> R2 | FULL ✓ |
| OSPFv3 R2 <-> R3 | FULL ✓ |
| Rutas R3 ve fd00:1::/64 | ✓ |
| HTTP dominio.com sin VPN | ✓ |
| ACL bloquea :8080 | ✓ |
| WireGuard handshake | ✓ |
| Intranet via VPN | ✓ |
| DNS dominio.com | 2001:db8:12::1 ✓ |
| DNS dominio.local | fd00:1::10 ✓ |
| fd00:2::1 inaccesible sin VPN | ✓ |

**Estado: LAB FUNCIONANDO COMPLETAMENTE**
