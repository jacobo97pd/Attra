# SafeDate — Privacidad y retención

> **Borrador técnico. La política final debe revisarla el equipo jurídico antes
> de producción.** Los plazos son configurables (Remote Config), no verdad legal
> definitiva.

## Principio rector
Privacidad por defecto. La ubicación **nunca** se comparte sin consentimiento
explícito, granular y revocable, y solo durante un periodo limitado. Sin
historial permanente de ubicaciones. Sin uso publicitario. Sin puntuaciones
públicas de seguridad.

## Datos tratados

| Dato | Finalidad | Base legal (validar jurídicamente) | Retención propuesta |
|---|---|---|---|
| Contactos de confianza (nombre + tel/email) | Avisar a alguien de confianza | Consentimiento | Hasta que el usuario los borre |
| Plan de cita (lugar, hora, duración) | Acompañamiento de la cita | Consentimiento | Plan completado: 30 días |
| Check-ins | Confirmar que la persona está bien | Consentimiento | 30 días |
| Alertas | Respuesta ante un aviso; moderación | Interés vital / consentimiento | Según gravedad y necesidad de moderación |
| Ubicación temporal en vivo | Compartir posición durante la cita | Consentimiento explícito por sesión | Inmediata al terminar; máx 24h; TTL |
| Revisión post-cita (privada) | Moderación interna, detección de reincidencia | Interés legítimo / consentimiento | Según política legal y de moderación |
| Tokens de enlace | Compartir plan con contacto | Consentimiento | Hasta expiración/revocación |
| Verificación de perfil | Mostrar señales de confianza (no garantías) | Consentimiento | Según sistema de verificación |

## Consentimientos
- Ubicación en vivo: opt-in **por cita**, con explicación de quién la ve,
  cuánto dura y cuándo se elimina; revocable en cualquier momento.
- Aviso a contactos ante check-in perdido: requiere autorización previa.
- IA de detección de riesgos: gated por flag; no comparte mensajes; advertencias
  descartables.

## Eliminación / revocación / exportación
Controles para: eliminar un plan, revocar un enlace, borrar un contacto,
desactivar la ubicación, eliminar todos los datos SafeDate. Exportación si existe
sistema de exportación de datos.

## Ubicación (detalle)
`safeDateLiveLocations/{planId}`: documento único por plan (sin historial de
puntos), con `expiresAt`. Escritura solo backend; lectura solo destinatarios
autorizados vía enlace temporal validado. Se elimina al `completed`/`cancelled`.
TTL de Firestore si está disponible; si no, limpieza por `onSchedule`.

## Contactos de confianza
Nunca se sube la agenda del dispositivo. Solo los contactos seleccionados
explícitamente. Privados: el match no los ve ni sabe si se ha enviado un aviso.

## IA
No acusa, no diagnostica, no infiere delitos, no crea puntuaciones públicas, no
comparte el contenido con terceros sin base legal. Ventanas pequeñas de mensajes
y redacción de PII (teléfonos/emails/direcciones) antes de procesar.

## Reportes
No se revela quién reportó. Evidencia mínima necesaria para moderación. Se puede
reportar incluso tras deshacer el match.

## Medidas de seguridad
Auth + (pendiente) App Check, Firestore Rules estrictas por colección,
validación server-side, tokens aleatorios con expiración/revocación,
comprobación de ownership y pertenencia al match, rate limiting, idempotencia,
mínimo privilegio, sin secretos en el repositorio.

## Riesgos pendientes
- App Check no configurado aún (habilitar antes de exponer CF sensibles).
- Revisión jurídica de bases legales y plazos.
- Ubicación en background (fuera del MVP): requiere UX y permisos específicos.
