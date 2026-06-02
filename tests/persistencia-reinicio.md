# Persistencia ante Reinicios — Lab IPv6 v5

## Respuesta directa

**No es totalmente automatico.** La mayoria de la configuracion
persiste, pero hay componentes que necesitan intervencion manual
tras un reinicio completo del proyecto GNS3. Se detalla a continuacion.

---

## COMPONENTE POR COMPONENTE

---

### r1-linux (Docker) — PERSISTENCIA COMPLETA

| Elemento | Como persiste | Estado |
|----------|---------------|--------|
| IPs eth0/eth1 | start.sh las asigna en cada arranque | Automatico |
| ip6tables NAT66 | start.sh aplica las reglas en cada arranque | Automatico |
| ip6tables ACL + regla OSPF | start.sh aplica en cada arranque | Automatico |
| FRR frr.conf | /etc/frr es directorio persistente GNS3 | Automatico |
| OSPFv3 vecinos | Se re-forman solos (~30-60s tras arranque) | Automatico |
| Espera de interfaces | Loop de 30s en start.sh da tiempo a GNS3 | Automatico |

**Condicion:** La regla `ip6tables -p ospf -j ACCEPT` esta baked en
la imagen actual (verificado: imagen creada 2026-06-01T19:19:44).
Si se hace `docker build` de nuevo sin esa regla, se pierde.

**Resultado: tras reinicio GNS3, r1-linux arranca sin intervencion.**

---

### pc1-servidor (Docker) — PERSISTENCIA COMPLETA

| Elemento | Como persiste | Estado |
|----------|---------------|--------|
| IP fd00:1::10/64 | start.sh crea/lee NET_CONF en dir persistente | Automatico |
| nginx | start.sh inicia en cada arranque | Automatico |
| BIND9 | start.sh inicia en cada arranque | Automatico |
| WireGuard wg0.conf | /opt/wg-baked/wg0.conf en imagen (no persistente) | Automatico |
| WireGuard tunel | PersistentKeepalive=25 reconecta solo | Automatico |
| Zonas DNS | /etc/bind/zones es dir persistente GNS3 | Automatico |
| Web /var/www | dir persistente GNS3 | Automatico |

**Mecanismo clave — wg0.conf:**
Si GNS3 monta /etc/wireguard vacio (primer arranque o dir borrado),
start.sh detecta que falta wg0.conf y lo restaura desde
`/opt/wg-baked/wg0.conf` que esta horneado en la imagen Docker.
Nunca se pierde la configuracion WireGuard.

**Resultado: tras reinicio GNS3, pc1-servidor arranca sin intervencion.**

---

### pc3-cliente (Docker) — PERSISTENCIA COMPLETA

| Elemento | Como persiste | Estado |
|----------|---------------|--------|
| IP 2001:db8:3::10/64 | start.sh crea/lee NET_CONF en dir persistente | Automatico |
| WireGuard wg0.conf | /opt/wg-baked/wg0.conf en imagen + dir persistente | Automatico |
| Tunel VPN | PersistentKeepalive=25 reconecta solo en ~25s | Automatico |

**Resultado: tras reinicio GNS3, pc3-cliente arranca sin intervencion.**

---

### R2 Cisco 3745 (GNS3 "R1") — PERSISTENCIA COMPLETA

| Elemento | Como persiste | Estado |
|----------|---------------|--------|
| Todas las interfaces | write memory -> NVRAM de Dynamips | Automatico |
| OSPFv3 config | write memory | Automatico |
| clock rate Serial0/0 | write memory | Automatico |
| Vecinos OSPF | Se re-forman solos | Automatico |

**Condicion:** Se ejecuto `write memory` (wr) en la sesion actual.
Si no se guarda antes de reiniciar, se pierde el config.

**Resultado: persistente siempre que se haya guardado con wr.**

---

### R3 Cisco 3745 (GNS3 "R2") — PERSISTENCIA COMPLETA

| Elemento | Como persiste | Estado |
|----------|---------------|--------|
| Todas las interfaces | write memory -> NVRAM | Automatico |
| OSPFv3 config | write memory | Automatico |
| passive-interface fa0/0 | write memory | Automatico |

**Resultado: persistente siempre que se haya guardado con wr.**

---

### PC2 VPCS — PERSISTENCIA CONDICIONAL

| Elemento | Como persiste | Estado |
|----------|---------------|--------|
| IP fd00:1::20/64 | Comando save en VPCS | Solo si se guardo |
| Gateway fd00:1::1 | Comando save en VPCS | Solo si se guardo |

**ADVERTENCIA:** Si no se ejecuto `save` en VPCS, la IP se pierde
al reiniciar y hay que reconfigurar:
```
ip fd00:1::20/64 fd00:1::1
save
```

---

## QUE NO SOBREVIVE UN REINICIO

### 1. Reglas ip6tables aplicadas manualmente

Si se agrego alguna regla con `docker exec` directamente (no via start.sh),
esa regla desaparece al reiniciar el contenedor.

**En este lab:** Todas las reglas se agregan en start.sh y estan en la
imagen. No hay reglas aplicadas solo manualmente.

### 2. Adjacencias OSPF (temporal)

Tras reinicio hay ~30-60 segundos donde OSPF no ha convergido.
Es normal. No requiere intervencion.

### 3. Tunel WireGuard (temporal)

Tras reinicio hay ~25 segundos antes de que el keepalive
re-establezca el tunel. Es normal. No requiere intervencion.

---

## ESCENARIOS DE REINICIO

### Escenario A — Reinicio normal (Stop/Start en GNS3)

```
1. GNS3 detiene los contenedores y routers
2. GNS3 reinicia los nodos
3. r1-linux: wait loop espera interfaces, aplica config -> ~35s
4. pc1-servidor: aplica IP, inicia nginx/bind9/wg -> ~10s
5. pc3-cliente: aplica IP, sube wg0 -> ~5s
6. R2, R3: arrancan con config guardada en NVRAM -> ~30s
7. OSPFv3 converge -> ~60s
8. WireGuard reconecta -> ~25s
```
**Tiempo total hasta funcional: ~2 minutos. Sin intervencion manual.**

### Escenario B — Rebuild de imagen Docker

Si se ejecuta `./generar-claves-y-rebuild.sh` de nuevo:
- Se generan NUEVAS claves WireGuard
- La nueva imagen tiene nuevas claves horneadas
- Los contenedores deben eliminarse y recrearse (docker rm + Start en GNS3)
- Si /etc/wireguard tenia el conf antiguo en dir persistente,
  start.sh lo sobrescribe con el nuevo desde /opt/wg-baked

**Accion requerida:** Borrar contenedores GNS3 y hacer Start de nuevo.

### Escenario C — Proyecto GNS3 "Wipe" (borrar datos persistentes)

Si se hace Wipe en GNS3 (borra directorios persistentes):
- Docker: primer arranque recrea todo desde la imagen -> OK
- Cisco NVRAM: se borra la config guardada -> hay que repegar los configs

**Accion requerida:** Repegar r2-config.txt y r3-config.txt en las consolas.

---

## RESUMEN DE PERSISTENCIA

| Componente | Auto tras Stop/Start | Requiere intervencion |
|------------|---------------------|----------------------|
| r1-linux | Si | No |
| pc1-servidor | Si | No |
| pc3-cliente | Si | No |
| R2 Cisco | Si (si se guardo con wr) | Solo si no se guardo |
| R3 Cisco | Si (si se guardo con wr) | Solo si no se guardo |
| PC2 VPCS | Si (si se ejecuto save) | Solo si no se guardo |
| OSPFv3 | Auto en ~60s | No |
| WireGuard | Auto en ~25s | No |

**Conclusion:** El lab esta correctamente configurado para sobrevivir
reinicios normales de GNS3 sin intervencion manual, siempre que:
1. Los routers Cisco tengan `write memory` ejecutado (ya hecho)
2. PC2 VPCS tenga `save` ejecutado
3. No se haga Wipe del proyecto GNS3
