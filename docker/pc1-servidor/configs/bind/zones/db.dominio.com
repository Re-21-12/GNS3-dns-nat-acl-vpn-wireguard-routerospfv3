; ============================================================
; dominio.com — zona publica
; Apunta a la IP publica de R1-Linux (2001:db8:12::1)
; R1-Linux hace NAT66 DNAT: :80 :53 → fd00:1::10 (PC1 ULA)
; PC1 NO tiene GUA — solo fd00:1::10/64
; ============================================================
$TTL 86400
@   IN  SOA  ns1.dominio.com. admin.dominio.com. (
        2024010103  ; Serial
        3600        ; Refresh
        900         ; Retry
        604800      ; Expire
        86400 )     ; Negative TTL

@       IN  NS   ns1.dominio.com.

; ns1 apunta a R1-Linux (puerta de entrada publica con DNAT DNS)
ns1     IN  AAAA 2001:db8:12::1

; dominio.com y www apuntan a R1-Linux (DNAT :80 → PC1:80)
@       IN  AAAA 2001:db8:12::1
www     IN  AAAA 2001:db8:12::1
