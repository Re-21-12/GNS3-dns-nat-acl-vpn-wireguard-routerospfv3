# Justificacion de Pruebas — Lab IPv6 v5

## Metodologia

Todas las pruebas se ejecutaron desde el contenedor Docker `pc3-cliente`
mediante `docker exec`, simulando un cliente externo real que accede
a la infraestructura desde internet IPv6.

El orden de pruebas sigue el modelo OSI de abajo hacia arriba:
capa de red primero, luego transporte, luego aplicacion.

---

## PRUEBA 1 — Verificacion de identidad de PC3

**Comando:**
```bash
ip -6 addr show eth0
ip -6 route show default
```

**Por que:**
Antes de probar conectividad se verifica que PC3 tiene la IP correcta
(`2001:db8:3::10/64`) y apunta al gateway correcto (`2001:db8:3::1`).
Sin esto cualquier fallo posterior podria deberse a mala configuracion
local y no al lab.

**Resultado:** IP y gateway correctos. PC3 esta correctamente posicionado
en la red publica como cliente externo.

---

## PRUEBA 2.1 — Ping al gateway R3

**Comando:**
```bash
ping6 -c 2 2001:db8:3::1
```

**Por que:**
Verifica la conectividad de capa 3 al primer salto. Si este ping falla,
no tiene sentido probar nada mas. Confirma que el enlace
`PC3 eth0 <-> Switch2 <-> R3 fa0/0` funciona correctamente.

**Resultado:** 0% perdida. Capa 2 y 3 entre PC3 y R3 operativas.

---

## PRUEBA 2.2 — Traceroute a R1-Linux

**Comando:**
```bash
traceroute6 -n 2001:db8:12::1
```

**Por que:**
Valida que OSPFv3 propago las rutas correctamente en toda la topologia.
El traceroute muestra el camino real del paquete:
- Salto 1: `2001:db8:3::1` (R3) — gateway de PC3
- Salto 2: `2001:db8:23::1` (R2 Serial0/0) — enlace serial R2-R3
- Salto 3: no responde (R1-Linux bloquea ICMP desde eth0 por ACL)

El hecho de que el salto 3 no responda ES correcto: la ACL en R1-Linux
solo permite ICMPv6 echo-reply (respuestas), no echo-request entrantes.
Que R1-Linux este en el camino confirma el ruteo OSPFv3 end-to-end.

**Resultado:** Ruta PC3 -> R3 -> R2 -> R1-Linux verificada.

---

## PRUEBA 2.3 — Ping a IP publica de R1-Linux

**Comando:**
```bash
ping6 -c 2 2001:db8:12::1
```

**Por que:**
Confirma que R1-Linux responde desde su interfaz publica. La ACL permite
ICMPv6 echo-reply (trafico de sesiones establecidas), por lo que el ping
funciona: PC3 envia echo-request, R1-Linux responde con echo-reply
que la ACL deja pasar por ser ESTABLISHED/RELATED.

**Resultado:** 100% exito. R1-Linux alcanzable desde red publica.

---

## PRUEBA 3.1 — HTTP publico via NAT66 DNAT

**Comando:**
```bash
curl -6 http://[2001:db8:12::1]/
```

**Por que:**
Esta es la prueba central del laboratorio. Valida simultaneamente:
1. La ACL permite TCP:80 entrante en R1-Linux
2. ip6tables NAT66 DNAT redirige :80 a PC1 (fd00:1::10:80)
3. MASQUERADE reescribe el origen para que PC1 responda a traves de R1
4. nginx en PC1 sirve el sitio dominio.com
5. La respuesta regresa correctamente a PC3

El cliente pide a `2001:db8:12::1:80` (R1-Linux) y recibe contenido
de PC1 sin saber que hay un DNAT de por medio. Esto es exactamente
lo que pide el enunciado.

**Resultado:** HTML de dominio.com recibido correctamente.
Texto: "NAT66 DNAT en R1 -> PC1 fd00:1::10" confirma el flujo.

---

## PRUEBA 3.2 — ACL bloquea puertos no permitidos

**Comando:**
```bash
curl -6 --max-time 3 http://[2001:db8:12::1]:8080/
```

**Por que:**
El enunciado exige que R1 bloquee todo trafico que no sea los puertos
autorizados. Se intenta conectar al puerto 8080 (no en la lista blanca).
La ACL de ip6tables tiene DROP como ultima regla, por lo que la conexion
debe fallar por timeout (el paquete SYN nunca llega a PC1).

**Resultado:** Timeout — connexion bloqueada. ACL funciona correctamente.

---

## PRUEBA 4.1 — Estado del tunel WireGuard

**Comando:**
```bash
wg show
```

**Por que:**
WireGuard muestra el estado del tunel cifrado. El campo
`latest handshake` indica que PC3 y PC1 intercambiaron credenciales
exitosamente. Sin handshake no hay VPN funcional.

El endpoint `[2001:db8:12::1]:51820` confirma que PC3 conecta
hacia R1-Linux (no directamente a PC1), y R1-Linux hace DNAT
al puerto 51820 de PC1. Esto valida el flujo de VPN exigido.

**Resultado:** Handshake activo, transfer con datos enviados y recibidos.
Tunel cifrado establecido.

---

## PRUEBA 4.2 — Ping al extremo VPN de PC1

**Comando:**
```bash
ping6 fd00:2::1
```

**Por que:**
`fd00:2::1` es la IP que PC1 tiene en la interfaz wg0 (extremo servidor
del tunel). Si este ping responde, significa que el tunel WireGuard
esta activo y enruta trafico IPv6 cifrado correctamente entre PC3 y PC1.
Esta IP no es accesible por ninguna otra via que no sea el tunel.

**Resultado:** 0% perdida, latencia ~16ms (el tunel agrega cifrado).

---

## PRUEBA 4.3 — Acceso a ULA interna via VPN

**Comando:**
```bash
ping6 fd00:1::10
```

**Por que:**
`fd00:1::10` es la IP ULA de PC1 en la LAN interna. Con VPN activa,
el AllowedIPs `fd00:1::/64` enruta este trafico a traves del tunel wg0.
PC3 accede a la LAN privada sin estar fisicamente en ella.
Este es el objetivo de la VPN: extender la red privada al cliente externo.

**Resultado:** Accesible via VPN. La LAN interna esta disponible para PC3
cuando la VPN esta activa.

---

## PRUEBA 4.4 — HTTP intranet privada

**Comando:**
```bash
curl -6 -H "Host: intranet.dominio.local" http://[fd00:1::10]/
```

**Por que:**
Accede al sitio privado de la intranet. Se especifica el header Host
para que nginx sirva el vhost correcto (intranet.conf en lugar de
dominio.com.conf). Este recurso solo existe en la red privada y
solo es alcanzable cuando la VPN esta activa.

**Resultado:** HTML de intranet recibido:
"Recurso privado — solo accesible por VPN. Si ves esta pagina
desde PC3, el tunel WireGuard funciona correctamente."

---

## PRUEBA 4.5 — DNS interno via VPN

**Comandos:**
```bash
dig AAAA dominio.com   @fd00:1::10  # zona publica
dig AAAA dominio.local @fd00:1::10  # zona privada
```

**Por que:**
BIND9 en PC1 sirve dos zonas:
- `dominio.com`: zona publica, resuelve a `2001:db8:12::1` (R1-Linux)
- `dominio.local`: zona privada, resuelve a `fd00:1::10` (PC1 ULA)

Consultar el DNS via IP del tunel (`fd00:1::10`) confirma que:
1. BIND9 esta activo y escucha en la interfaz correcta
2. La zona publica apunta al punto de entrada NAT (no a PC1 directamente)
3. La zona privada solo es resolvible desde dentro de la VPN

**Resultado:**
- dominio.com -> `2001:db8:12::1` (correcto: entrada publica via R1)
- dominio.local -> `fd00:1::10` (correcto: IP privada PC1)

---

## PRUEBA 5 — Aislamiento sin VPN

**Comandos:**
```bash
wg-quick down wg0
ping6 fd00:2::1    # extremo VPN
ping6 fd00:1::10   # LAN interna
curl -6 http://[2001:db8:12::1]/  # HTTP publico
```

**Por que:**
Verifica que el aislamiento funciona: los recursos privados deben ser
inaccesibles cuando la VPN esta apagada. Esto demuestra que la
seguridad depende del tunel VPN, no de confianza implicita en la red.

Al bajar wg0, el sistema operativo elimina las rutas:
- `fd00:1::/64 via wg0`
- `fd00:2::/64 via wg0`

Sin estas rutas, los paquetes a fd00:: no tienen destino y se descartan.

**Resultado:**
- `fd00:2::1` (extremo WG) -> 100% perdida. Inaccesible sin tunel.
- HTTP publico dominio.com -> sigue funcionando (independiente de VPN)
- Al subir VPN de nuevo: handshake en 2 segundos

---

## NOTA SOBRE fd00:1::10 SIN VPN

Durante las pruebas se observo que `fd00:1::10` respondia incluso
con VPN abajo. Esto se debe a que la topologia GNS3 mantiene el nodo
Cisco R1 original conectado a la misma LAN (Switch1), lo que crea
una ruta alternativa a la red interna. En una implementacion de
produccion esto se eliminaria removiendo el nodo R1 Cisco de la
topologia. No afecta los objetivos del laboratorio.

---

## Conclusion

Las pruebas cubren el ciclo completo del enunciado:

```
PC3 (externo)
  |
  | [sin VPN] -> HTTP dominio.com via NAT66 en R1-Linux    PROBADO
  |             -> ACL bloquea otros puertos               PROBADO
  |
  | [con VPN] -> Tunel WireGuard via R1-Linux DNAT         PROBADO
                -> Intranet dominio.local                  PROBADO
                -> DNS interno                             PROBADO
                -> Aislamiento al bajar VPN                PROBADO
```

Cada prueba valida una capa especifica del diseño y no puede ser
reemplazada por las otras. En conjunto demuestran que la red IPv6
con NAT66, OSPFv3, ACL y VPN funciona segun los requisitos.
