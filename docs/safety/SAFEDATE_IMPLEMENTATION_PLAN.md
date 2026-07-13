# Attra SafeDate — Plan de implementación

> Capa integral de seguridad para citas presenciales. **Desactivable por
> completo** (Remote Config) sin afectar al resto de la app. Privacidad por
> defecto; sin falsas garantías; sin emergencias automáticas.

Estado: **Fase 1 (fundamentos) + contactos de confianza** implementados. Resto
por fases (ver §Plan por fases).

---

## 1. Auditoría del estado actual (reutilizable)

| Área | Qué hay | Reutilización en SafeDate |
|---|---|---|
| **Modelo de usuario** | `AppUser` (`users/{uid}`), reglas ligeras `_withRequiredUserFields`, claves top-level permitidas incluyen `location`, `profile`, `photos` | Subcolección `users/{uid}/trustedContacts` |
| **Matches** | `matches/{matchId}` (IDs deterministas `pairId`), backend-autoritativo | Validar pertenencia al match antes de crear plan |
| **Chats** | `chats/{chatId}` = matchId, mensajes; CF `sendMessage` | Entrada "Planear cita segura" en el chat |
| **Propuestas de cita** | **Attra Plans** (`matches/{id}/datePlans`, `createDatePlanProposal`, `generateDatePlanSuggestions` con Google Places) | SafeDate consume el plan propuesto (lugar público, horario) |
| **IA** | Vertex AI (`ai.ts`: embeddings, `requireProAiConsent`); reglas puras espejo Dart↔TS | Fase 6: detección de riesgos con ventana pequeña de mensajes + redacción de PII |
| **Auth** | Firebase Auth (Google/Apple), `requireAuthUid` | App Check + auth en todas las CF |
| **Firestore** | Base con **nombre** `attra-database`; reglas por colección (participantes leen, backend escribe) | Nuevas colecciones con mismas convenciones |
| **Functions** | onCall v2, `europe-west1`, `col`, transacciones, `existsBlockBetween` | `functions/src/safedate.ts` |
| **Messaging** | FCM + APNs, `createNotification` (in-app + push), tokens en `users/{uid}.fcmTokens` | Notificaciones de check-in discretas |
| **Analytics** | `FeedMetricsService` (feedEvents), `productMetrics` | Eventos SafeDate agregados/anónimos |
| **Remote Config / flags** | `config/featureFlags` (Firestore) → `MonetizationFeatureFlags.rawConfig`; patrón `Config.fromMap(rawConfig)` (RankingConfig, AntiGhostingConfig) | `SafeDateFlags.fromMap(rawConfig)` |
| **Reportes/bloqueos/moderación** | `reportUser`, `blockUser`, `unmatch`, `existsBlockBetween`, `moderation.ts` | Reusar en revisión post-cita |
| **Navegación** | `HomeShell` (tabs) + push de screens; callbacks vía `SessionController`→`SessionGate`→`HomeShell` | Entrada desde perfil/chat |
| **Estado** | `ValueNotifier`/controllers + `SessionController`; repos/servicios inyectados en `app.dart` | `SafeDateService` inyectado igual |
| **Diseño** | `AppTheme` (claro Piedra / oscuro coral), `AttraColors`, tarjetas redondeadas, `context.colors` | Componentes SafeDate con el mismo sistema |

**Conclusión:** NO se crea arquitectura paralela. SafeDate reutiliza flags,
config, CF onCall, reglas por colección, notificaciones, reportes/bloqueos, IA
Vertex y el sistema de diseño.

---

## 2. Componentes reutilizables

- Config remota: `SafeDateFlags.fromMap(flags.rawConfig)` (patrón existente).
- CF: `requireAuthUid`, `requireStringArg`, `col`, `existsBlockBetween`,
  `nextJourneyStatus`, transacciones.
- Reportes/bloqueos: `reportUser`, `blockUser` (revisión post-cita).
- Notificaciones: `createNotification` (nuevo `kind` `safedate_*`).
- IA: patrón `requireProAiConsent` + reglas puras espejo (Fase 6).
- Diseño: `context.colors`, tarjetas, `AttraEmptyState`.

---

## 3. Nuevas colecciones Firestore

```
users/{uid}/trustedContacts/{contactId}         (privado del dueño)
safeDatePlans/{planId}                           (owner + backend)
safeDatePlans/{planId}/checkIns/{checkInId}
safeDatePlans/{planId}/alerts/{alertId}
safeDateSafetyReviews/{reviewId}                 (privado, sin exposición)
safeDateLiveLocations/{planId}                   (temporal, TTL, sin historial)
safeDateShareTokens/{tokenId}                    (enlace temporal revocable)
```

Datos sensibles separados de consulta frecuente. Ubicación en vivo: documento
único por plan (sin historial de puntos), con `expiresAt` (TTL Firestore).

---

## 4. Nuevos servicios

- **Cliente** `SafeDateService` (lecturas Firestore + escrituras vía CF).
- **Backend** `functions/src/safedate.ts`: contactos, plan, check-ins, alertas,
  ubicación en vivo, enlace de compartición, limpieza programada.
- **Config** `SafeDateFlags` (flags + tiempos de check-in configurables).
- **Analytics** `SafeDateAnalytics` (eventos agregados).

---

## 5. Nuevas pantallas (§15 del brief)

`SafeDateHomeScreen`, `CreateSafeDatePlanScreen`, `SafeDatePlanSummaryScreen`,
`ActiveSafeDateScreen`, `TrustedContactsScreen`, `TrustedContactFormScreen`,
`SafeDateCheckInScreen`, `SafeDateAlertScreen`, `PostDateSafetyReviewScreen`,
`SafeDatePrivacyInfoScreen`.

Componentes: `SafeDateStatusCard`, `TrustedContactCard`, `CheckInCard`,
`SafetyTipCard`, `DiscreetActionButton`, `EmergencyActionSheet`,
`ProfileVerificationSummary`, `SafePlaceCard`, `DatePlanSummaryCard`.

---

## 6. Riesgos técnicos

- **TTL Firestore** en base con nombre: verificar disponibilidad; fallback =
  limpieza por `onSchedule` (scheduler) borrando `expiresAt < now`.
- **App Check**: no está configurado hoy → habilitar antes de exponer CF
  sensibles (o al menos auth + rate limit + reglas estrictas de entrada).
- **Ubicación en background**: iOS/Android exigen permisos y UX específicos; MVP
  usa ubicación en primer plano puntual (no tracking continuo en background).
- **Enlace de compartición**: hosting público requerido (hoy `hosting/` mínimo);
  MVP entrega el token vía CF de validación; página pública = fase posterior.
- **Coste IA** (Fase 6): ventanas pequeñas + redacción de PII + rate limit.

## 6b. Riesgos legales y de privacidad

- Datos de ubicación y contactos = categoría sensible (RGPD). Base legal =
  **consentimiento explícito**, granular y revocable. Retención mínima.
- Contactos de confianza: NO subir agenda; solo los seleccionados.
- Revisión post-cita: **privada**, sin puntuación pública, sin exponer al
  evaluado. Evidencia solo para moderación interna.
- IA: no acusa, no diagnostica, no infiere delitos, no comparte mensajes.
- **La política final debe revisarla el equipo jurídico antes de producción.**

---

## 7. Plan por fases

| Fase | Contenido | Estado |
|---|---|---|
| **1 — Fundamentos** | Auditoría, docs, flags, modelos, servicio, reglas, analytics base, centro vacío, tests | ✅ HECHO |
| **2 — Contactos + plan** | Contactos de confianza (CRUD), crear plan, resumen, entrada chat, enlace temporal + revocación | 🟡 Contactos hechos; plan/enlace parcial |
| **3 — Check-ins** | Programación, notificaciones, respuestas, perdido, aviso prudente, reintentos, offline | ⬜ Pendiente |
| **4 — Cita activa** | Pantalla activa, acciones discretas, llámame, salir, alerta silenciosa, 112, ubicación temporal | ⬜ Pendiente |
| **5 — Post-cita** | Evaluación privada, bloqueo, reporte, evidencia, moderación | ⬜ Pendiente |
| **6 — IA preventiva** | Detección de patrones, advertencias suaves, privacidad, coste, rate limit | ⬜ Pendiente |
| **7 — Citas propuestas + Safe Places** | Lugares reales públicos, SafeDate automático, alternativas | ⬜ Pendiente |

---

## 8. Estrategia de migración

No destructiva. Modelos nuevos con parsers tolerantes y defaults. Ningún
usuario/chat/match/perfil antiguo se ve afectado (SafeDate off por defecto).

## 9. Estrategia de testing

Unitarios (modelos, flags, estados, tokens, caducidad) — Fase 1 incluidos.
Widgets, reglas (emulador), functions (jest si se añade), integración — por fase.

## 10. Despliegue progresivo

Todas las flags `feature_safedate_*` **OFF en producción**. Orden de activación:
1) `feature_safedate_enabled` (centro visible, solo contactos + plan) al 1-5%.
2) `..._trusted_contacts_enabled`, `..._date_plan_enabled`.
3) `..._checkins_enabled` → `..._live_location_enabled` / `..._discreet_alert_enabled`.
4) `..._post_date_review_enabled`.
5) `..._ai_risk_detection_enabled` (con límites de coste).
6) `..._verified_only_filter_enabled`, `..._safe_places_enabled`.

Fallback seguro: si Remote Config falla → SafeDate **desactivado**; nunca una
función de ubicación activa sin confirmación del usuario.
