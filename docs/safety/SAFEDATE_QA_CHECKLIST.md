# SafeDate — Checklist de QA

## Master switch / fallback
- [ ] Con `feature_safedate_enabled: false` (o sin doc) → NO aparece el tile
      SafeDate ni el centro; la app va exactamente como antes.
- [ ] Si Remote Config falla → SafeDate desactivado; ninguna función de
      ubicación queda activa sin confirmación.
- [ ] Apagar el master switch con datos existentes → todo SafeDate desaparece.

## Contactos de confianza (Fase 2 — implementado)
- [ ] Añadir contacto con teléfono válido → aparece en la lista.
- [ ] Añadir con email válido → OK.
- [ ] Nombre vacío / sin canal / email o teléfono inválidos → error claro.
- [ ] Marcar "principal" → solo uno queda principal.
- [ ] Editar y eliminar contacto.
- [ ] Los contactos NO son visibles para el match (verificar reglas).

## Plan de cita (backend — pendiente UI completa)
- [ ] Crear plan desde un chat del que soy participante → OK.
- [ ] Crear plan en un chat ajeno → denegado.
- [ ] Cancelar/completar plan propio → estado cambia; ubicación temporal se borra.

## Reglas Firestore (emulador — pendiente tests)
- [ ] Leer `safeDatePlans` ajeno → denegado.
- [ ] Leer `trustedContacts` de otro usuario → denegado.
- [ ] Escribir cualquier colección SafeDate desde cliente → denegado.
- [ ] `safeDateSafetyReviews` / `safeDateLiveLocations` / `safeDateShareTokens`
      → read/write cliente denegado.

## UI / accesibilidad
- [ ] Centro y contactos: modo claro y oscuro.
- [ ] Pantallas pequeñas, texto grande, SafeArea, scroll, teclado.
- [ ] Lectores de pantalla (etiquetas semánticas).
- [ ] Botón 112 identificable; disclaimer "no sustituye a emergencias" visible.
- [ ] Sin textos de falsa garantía ("persona segura", "100% fiable").

## Copy / seguridad
- [ ] No hay puntuaciones públicas de seguridad.
- [ ] La revisión post-cita no se muestra al evaluado (cuando exista).
- [ ] No se llama automáticamente a emergencias por un check-in perdido.

## Analytics / privacidad
- [ ] Los eventos no contienen nombre/teléfono/email/coordenadas/mensajes.
- [ ] `SafeDateEvents.safeParams` filtra claves prohibidas.

## Pendiente por fase (3-7)
Check-ins programados + notificaciones + perdido; cita activa + acciones
discretas + 112 + ubicación temporal; revisión post-cita + reporte/bloqueo; IA
preventiva; integración con citas propuestas + safe places.
