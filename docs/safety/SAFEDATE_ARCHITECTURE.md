# SafeDate — Arquitectura

## Módulo
`lib/src/features/safedate/` (domain / data / presentation), siguiendo la
convención feature-first del proyecto. No duplica arquitectura existente.

## Config remota (flags)
`config/featureFlags` (Firestore) → `MonetizationFeatureFlags.rawConfig` →
`SafeDateFlags.fromMap(rawConfig)`. Patrón idéntico a `RankingConfig` y
`AntiGhostingConfig`. **Todo OFF por defecto**; fallback seguro
(`SafeDateFlags.disabled`) si Remote Config falla. `enabled` es el master switch:
si está OFF, cada `*Active` es false → SafeDate invisible y desactivado.

Claves: `feature_safedate_enabled`, `..._trusted_contacts_enabled`,
`..._date_plan_enabled`, `..._checkins_enabled`, `..._live_location_enabled`,
`..._discreet_alert_enabled`, `..._post_date_review_enabled`,
`..._ai_risk_detection_enabled`, `..._verified_only_filter_enabled`,
`..._safe_places_enabled`; tiempos `safedate_checkin_*_minutes`;
`safedate_emergency_number`.

## Modelos (domain, puros/testeables)
`TrustedContact`/`TrustedContactInput` (validación+normalización),
`SafeDatePlan`+`SafeDatePlanStatus`, `SafeDateCheckIn`+`CheckInType/Status`,
`SafeDateAlert`+`AlertType/Severity`, `PostDateSafetyReview`+`PostDateConcern`,
`SafePlace`, `SafeDateFlags`, `SafeDateEvents`.

## Servicio (data)
`SafeDateService`: lecturas de datos PROPIOS vía Firestore (reglas: solo el
dueño); escrituras vía Cloud Functions (backend-autoritativo). Inyectado en
`app.dart` → `SessionController` → `SessionGate` → `HomeShell` (mismo patrón que
`DatePlanService`/servicios sociales).

## Backend (`functions/src/safedate.ts`)
onCall v2, `europe-west1`, Admin SDK contra `attra-database`. Todas exigen auth
y `requireSafeDateEnabled()` (lee el master switch). Implementadas (Fase 1-2):
`saveTrustedContact`, `deleteTrustedContact`, `createSafeDatePlan`,
`setSafeDatePlanStatus`. Pendientes por fase: check-ins programados
(`onSchedule`), alertas, ubicación en vivo + limpieza, enlace temporal
(generar/validar/revocar), IA de riesgos, safe places.

## Firestore (colecciones + reglas)
```
users/{uid}/trustedContacts/{id}    read: owner · write: backend
safeDatePlans/{planId}              read: ownerUserId==uid · write: backend
  /checkIns/{id}                    read: owner del plan · write: backend
  /alerts/{id}                      read: owner del plan · write: backend
safeDateLiveLocations/{planId}      read/write: false (solo backend + enlace)
safeDateSafetyReviews/{id}          read/write: false (privado, solo backend)
safeDateShareTokens/{id}            read/write: false (solo backend)
safePlaces/{id}                     read: signedIn · write: backend
```
Ubicación temporal: documento único por plan, `expiresAt` (TTL/limpieza), sin
historial. Se elimina al cerrar la cita.

## UI
`SafeDateHomeScreen` (centro, tono calmado, 112, privacidad),
`TrustedContactsScreen` (+ formulario validado). Entrada: tile "SafeDate" en el
perfil (HomeScreen), visible solo si el master switch está ON y hay servicio.
Diseño con `context.colors`/tarjetas del sistema; claro y oscuro.

## Integraciones (por fase)
- Chat: acción "Planear cita segura" (Fase 2/4) — reutiliza `chatId`/matchId.
- Attra Plans (IA): consumir el lugar propuesto (Fase 7).
- Reportes/bloqueos: revisión post-cita (Fase 5) reusa `reportUser`/`blockUser`.
- Notificaciones: `createNotification` con `kind` `safedate_*` (Fase 3).
