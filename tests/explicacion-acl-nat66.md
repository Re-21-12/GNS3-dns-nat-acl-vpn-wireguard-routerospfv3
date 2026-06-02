# Explicacion de ACL y NAT66 — Lab IPv6 v5

---

## POR QUE SE NECESITA NAT66 EN IPv6

En IPv4 el NAT es obligatorio porque las IPs privadas (192.168.x.x, 10.x.x.x)
no son enrutables en internet. En IPv6 el NAT no deberia ser necesario porque
hay suficientes IPs para todos. Sin embargo, en este lab se usa NAT66 por
una razon de diseno especifica:

El enunciado exige que R1 sea el punto de entrada publico y que PC1 no
sea directamente visible desde internet. PC1 solo tiene una direccion ULA
(fd00:1::10) que no es enrutable en la red publica. R1-Linux recibe el
trafico publico y lo redirige a PC1.

Esto es un DNAT (Destination NAT) o redireccion de puertos, equivalente
al "port forwarding" de routers domesticos pero en IPv6.

---

## ARQUITECTURA DE FILTRADO EN R1-Linux

R1-Linux tiene dos interfaces:
- `eth0` — red PUBLICA (2001:db8:12::1) — conectada a R2
- `eth1` — red PRIVADA (fd00:1::1) — conectada a Switch1/PC1

El trafico entra por eth0, se filtra con ACL, se redirige con NAT66
y sale por eth1 hacia PC1.

```
INTERNET
   |
   v
eth0 [2001:db8:12::1]
   |
   +---> [ip6tables PREROUTING] --> DNAT reescribe destino
   |
   +---> [ip6tables INPUT]      --> filtra trafico para R1 mismo
   |
   +---> [ip6tables FORWARD]    --> deja pasar trafico hacia eth1
   |
   v
eth1 [fd00:1::1]
   |
   v
PC1 [fd00:1::10]
```

---

## NAT66 DNAT — REGLAS Y EXPLICACION

### Que es DNAT

DNAT (Destination Network Address Translation) reescribe la direccion
de destino de un paquete entrante. El cliente cree que habla con R1-Linux
pero en realidad el paquete llega a PC1.

### Reglas configuradas

```bash
ip6tables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 \
    -j DNAT --to-destination [fd00:1::10]:80
```
**Que hace:** Todo paquete TCP que llega por eth0 al puerto 80
tiene su destino reescrito de `2001:db8:12::1:80` a `fd00:1::10:80`.
PC1 recibe el paquete como si fuera el destino original.

```bash
ip6tables -t nat -A PREROUTING -i eth0 -p tcp --dport 53 \
    -j DNAT --to-destination [fd00:1::10]:53

ip6tables -t nat -A PREROUTING -i eth0 -p udp --dport 53 \
    -j DNAT --to-destination [fd00:1::10]:53
```
**Que hace:** Igual para DNS. Se redirigen tanto TCP como UDP al
puerto 53 de PC1 (BIND9). DNS usa UDP normalmente pero TCP para
respuestas grandes.

```bash
ip6tables -t nat -A PREROUTING -i eth0 -p udp --dport 51820 \
    -j DNAT --to-destination [fd00:1::10]:51820
```
**Que hace:** Redirige el trafico WireGuard (UDP:51820) a PC1.
PC3 conecta al puerto 51820 de R1-Linux y el paquete llega a PC1
sin que PC3 sepa la IP real de PC1.

### MASQUERADE en POSTROUTING

```bash
ip6tables -t nat -A POSTROUTING -o eth1 -j MASQUERADE
```
**Que hace:** Cuando R1-Linux reenvía el paquete de PC3 hacia PC1,
reescribe el origen del paquete con su propia IP (fd00:1::1).
PC1 ve que el trafico viene de fd00:1::1 (R1-Linux) y no de
2001:db8:3::10 (PC3 real). Asi PC1 puede responder via su
gateway (R1-Linux) sin necesitar una ruta especial hacia PC3.

### Flujo completo de una peticion HTTP

```
PC3                R1-Linux              PC1
2001:db8:3::10     eth0: 2001:db8:12::1  fd00:1::10
                   eth1: fd00:1::1

1. PC3 envia:
   src=2001:db8:3::10  dst=2001:db8:12::1  dport=80

2. PREROUTING DNAT:
   src=2001:db8:3::10  dst=fd00:1::10      dport=80
   (destino reescrito)

3. MASQUERADE POSTROUTING:
   src=fd00:1::1       dst=fd00:1::10      dport=80
   (origen tambien reescrito para que PC1 pueda responder)

4. PC1 recibe y responde:
   src=fd00:1::10      dst=fd00:1::1       sport=80

5. Conntrack revierte el NAT automaticamente:
   src=2001:db8:12::1  dst=2001:db8:3::10  sport=80

6. PC3 recibe la respuesta de quien esperaba (R1-Linux)
```

### Conntrack (seguimiento de conexiones)

ip6tables mantiene una tabla de conexiones activas (conntrack).
Cuando aplica DNAT a un paquete SYN, guarda el mapeo:
`2001:db8:3::10:XXXX <-> fd00:1::10:80`

Los paquetes de respuesta de PC1 son automaticamente revertidos
al origen correcto sin necesitar reglas adicionales.

---

## ACL (ip6tables FILTER) — REGLAS Y EXPLICACION

### Que es una ACL en este contexto

Una ACL (Access Control List) define que trafico se permite y que
se descarta. En R1-Linux se implementa con ip6tables en la cadena
INPUT (trafico hacia R1 mismo) y FORWARD (trafico que pasa por R1).

### Cadena INPUT — trafico destinado a R1-Linux

```bash
ip6tables -A INPUT -i eth0 -p ospf -j ACCEPT
```
**Que hace:** Permite los paquetes OSPFv3 (protocolo 89) desde eth0.
Sin esta regla R1-Linux no podria recibir los Hello de R2 y no
formaria adjacencia OSPFv3. Se pone ANTES del DROP final.

```bash
ip6tables -A INPUT -i eth0 -m state --state ESTABLISHED,RELATED -j ACCEPT
```
**Que hace:** Permite respuestas a conexiones que R1 inicio desde eth0.
Sin esto R1 no podria recibir respuestas a sus propios pings o
conexiones salientes. ESTABLISHED = parte de una sesion ya abierta.
RELATED = trafico relacionado (como respuestas ICMP de error).

```bash
ip6tables -A INPUT -i eth0 -p ipv6-icmp -j ACCEPT
```
**Que hace:** Permite todo ICMPv6 desde eth0. Necesario para:
- NDP (Neighbor Discovery Protocol) — equivalente de ARP en IPv6
- Echo replies — para que los pings a R1-Linux funcionen
- Mensajes de error de red

Sin esto el NDP falla y no hay comunicacion IPv6 posible.

```bash
ip6tables -A INPUT -i eth1 -j ACCEPT
ip6tables -A INPUT -i lo   -j ACCEPT
```
**Que hace:** Permite TODO el trafico desde la interfaz interna (eth1)
y loopback. La LAN interna es de confianza: PC1, PC2, etc. pueden
comunicarse con R1-Linux sin restricciones.

```bash
ip6tables -A INPUT -i eth0 -j DROP
```
**Que hace:** DESCARTA todo lo que llega por eth0 y no fue aceptado
por las reglas anteriores. Esta es la regla de seguridad principal:
nadie desde internet puede conectarse a R1-Linux en puertos no
autorizados (SSH, Telnet, etc.).

**IMPORTANTE:** Esta regla NO bloquea el trafico DNAT. Los paquetes
que van a PC1 pasan por PREROUTING (donde se aplica el DNAT) ANTES
de llegar a INPUT. Despues del DNAT, el destino ya es PC1, no R1,
por lo que van a la cadena FORWARD, no a INPUT.

### Cadena FORWARD — trafico que pasa por R1-Linux hacia otro destino

```bash
ip6tables -A FORWARD -i eth0 -o eth1 \
    -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
```
**Que hace:** Permite reenviar trafico de eth0 a eth1. Este es el
trafico que ya paso el DNAT y va hacia PC1. Se permite NEW (nuevas
conexiones DNAT), ESTABLISHED y RELATED (el resto de la sesion).
Sin esta regla el DNAT no sirve de nada porque R1-Linux no
reenvíaria el paquete.

```bash
ip6tables -A FORWARD -i eth1 -o eth0 \
    -m state --state ESTABLISHED,RELATED -j ACCEPT
```
**Que hace:** Permite que las respuestas de PC1 (eth1) salgan
por eth0 hacia internet. Solo ESTABLISHED/RELATED: PC1 no puede
iniciar conexiones salientes hacia internet, solo responder
a las que le llegaron via DNAT.

---

## DIFERENCIA ENTRE ACL CISCO IOS Y ip6tables

El enunciado original pedia ACL en Cisco IOS 12.4, pero ese IOS
no soporta NAT66. Por eso se uso R1-Linux con ip6tables.

| Concepto | Cisco IOS ACL | ip6tables |
|----------|---------------|-----------|
| Permitir puerto | permit tcp any host X eq 80 | -A INPUT -p tcp --dport 80 -j ACCEPT |
| Denegar resto | deny ipv6 any any | -A INPUT -j DROP |
| Stateful | permit tcp any any established | -m state --state ESTABLISHED -j ACCEPT |
| NAT DNAT | no soportado en IOS 12.4 | -t nat -A PREROUTING -j DNAT |
| NAT MASQUERADE | no soportado | -t nat -A POSTROUTING -j MASQUERADE |

La logica es identica, la sintaxis es diferente. ip6tables ademas
permite NAT66 que es el requisito central del lab.

---

## ORDEN DE EVALUACION DE REGLAS ip6tables

ip6tables evalua las reglas en orden y para en la primera coincidencia.
El orden importa:

```
Paquete entrante por eth0
    |
    v
[1] PREROUTING (tabla nat)
    - DNAT si dport=80/53/51820 -> reescribe destino a PC1
    |
    v
Decision de enrutamiento:
    - Si destino es R1 mismo -> INPUT
    - Si destino es otro host -> FORWARD
    |
    +-------> INPUT (filter) ----------+-------> FORWARD (filter)
    |         1. ospf: ACCEPT          |         1. eth0->eth1 NEW/EST: ACCEPT
    |         2. ESTABLISHED: ACCEPT   |         2. eth1->eth0 EST: ACCEPT
    |         3. icmpv6: ACCEPT        |
    |         4. eth1: ACCEPT          |
    |         5. lo: ACCEPT            |
    |         6. DROP (todo lo demas)  |
    |
    v
[2] POSTROUTING (tabla nat)
    - MASQUERADE si sale por eth1 -> reescribe origen a fd00:1::1
```

---

## RESUMEN VISUAL

```
INTERNET
   |
   | Paquete: src=PC3, dst=2001:db8:12::1:80
   v
[eth0 R1-Linux]
   |
   | PREROUTING DNAT: dst -> fd00:1::10:80
   |
   | FORWARD: permite NEW (viene de DNAT)
   |
   | POSTROUTING MASQUERADE: src -> fd00:1::1
   |
[eth1 R1-Linux]
   |
   | Paquete: src=fd00:1::1, dst=fd00:1::10:80
   v
[PC1 nginx]
   |
   | Respuesta: src=fd00:1::10:80, dst=fd00:1::1
   v
[eth1 R1-Linux]
   |
   | Conntrack revierte: src -> 2001:db8:12::1:80, dst -> PC3
   |
[eth0 R1-Linux]
   |
   v
INTERNET -> PC3 recibe respuesta de 2001:db8:12::1
```

PC3 nunca sabe que PC1 existe. Solo ve la IP publica de R1-Linux.
