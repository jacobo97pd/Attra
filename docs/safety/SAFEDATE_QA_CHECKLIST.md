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

## Plan de cita (Fase 2 UI — implementado)
- [ ] Menú del chat muestra "Planear cita segura" solo con
      `feature_safedate_date_plan_enabled` ON.
- [ ] Crear plan desde un chat del que soy participante → OK; aparece en SafeDate.
- [ ] Crear plan en un chat ajeno → denegado (backend).
- [ ] Selección de contactos a avisar (chips) se guarda en el plan.
- [ ] El match NO ve el plan ni los contactos.
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

## Check-ins + notificaciones (Fase 3 — implementado)
- [ ] Crear plan con `feature_safedate_checkins_enabled` ON → se generan 3
      check-ins (llegada, mitad, regreso previsto) en `checkIns`.
- [ ] Al vencer un check-in → notificación in-app + push `safedate_checkin_due`.
- [ ] Sin respuesta pasado el 1er intervalo → `safedate_checkin_reminder`.
- [ ] Sin respuesta pasado el umbral → check-in `missed` +
      `safedate_checkin_missed`; NO se llama a nadie automáticamente.
- [ ] "Estoy bien" / "Recuérdame luego" / "Necesito ayuda" responden el check-in.
- [ ] "Necesito ayuda" ofrece 112 + contactos, pero la acción la inicia la
      persona (ninguna llamada automática).
- [ ] Check-in perdido con contactos autorizados → alerta prudente registrada
      (`alerts/missed_*`), `outboundDelivered:false` (entrega SMS/email = fase
      posterior; no se afirma envío no confirmado).
- [ ] Cancelar/completar plan → check-ins pendientes pasan a `cancelled`.
- [ ] Barrido `safeDateCheckinSweep`: con master switch OFF o checkins OFF → no
      hace nada (inerte).
- [ ] Tiempos configurables por Remote Config
      (`safedate_checkin_{first,second}_reminder_minutes`,
      `safedate_checkin_missed_threshold_minutes`).

E2E: crear plan desde el chat (menú → "Planear cita segura") con la fase de
check-ins ON genera los 3 check-ins y dispara el flujo de recordatorios.

## Cita activa + ubicación temporal + alertas (Fase 4 — implementado)
- [ ] Botón "Estoy en la cita" abre la pantalla de cita en curso (con
      `live_location` o `discreet_alert` activos).
- [ ] Compartir ubicación pide CONSENTIMIENTO explícito antes de empezar.
- [ ] Con el consentimiento → `startLiveLocation`; actualiza cada ~45s mientras
      la pantalla está abierta; al pararla/salir/terminar → `stopLiveLocation`
      borra la ubicación (sin historial).
- [ ] `updateLiveLocation` con sesión caducada → rechazado (no reactiva).
- [ ] Barrido `safeDateLiveLocationSweep` borra ubicaciones caducadas.
- [ ] Acciones discretas: "Pedir que me llamen" / "Necesito salir" / "Alerta
      silenciosa" registran alerta; NUNCA informan al match ni llaman solas.
- [ ] Alerta silenciosa/emergencia → plan pasa a `alerted` sin nada llamativo.
- [ ] 112 accesible; disclaimer "no sustituye a emergencias".
- [ ] En web: la ubicación en directo se oculta (no soportada); resto va.
- [ ] `safeDateLiveLocations` no legible/escribible por el cliente (backend-only).

## Revisión post-cita + reporte/bloqueo (Fase 5 — implementado)
- [ ] Al terminar la cita (o con "¿Cómo fue?" tras el regreso previsto) se
      ofrece la revisión, gated `feature_safedate_post_date_review_enabled`.
- [ ] La revisión es PRIVADA: no se muestra al evaluado, sin puntuación pública
      ni rankings.
- [ ] Solo se puede revisar a la persona del plan (no a un tercero).
- [ ] "Reportar" → crea reporte estándar; el evaluado no sabe quién reporta.
- [ ] "Bloquear" → aplica bloqueo estándar (cierra match/chat).
- [ ] El reporte NO incluye texto libre con PII (solo categorías).
- [ ] `safeDateSafetyReviews` no legible/escribible por el cliente (backend-only).

## Pendiente por fase (6-7)
IA preventiva; integración con citas propuestas + safe places. Entrega externa
a contactos (SMS/email) por definir.
