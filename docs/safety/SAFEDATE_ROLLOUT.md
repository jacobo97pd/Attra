# SafeDate — Plan de rollout

## Estado de despliegue
- **Cloud Functions**: `saveTrustedContact`, `deleteTrustedContact`,
  `createSafeDatePlan`, `setSafeDatePlanStatus` — **escritas, PENDIENTES de
  desplegar** (`firebase deploy --only functions:saveTrustedContact,...`).
- **Reglas Firestore**: nuevas colecciones — **pendientes de desplegar**
  (`firebase deploy --only firestore:rules`).
- **Flags**: NINGUNA en `config/featureFlags` → SafeDate **invisible** (fallback
  seguro). Nada que revertir en cliente.

## Orden de activación (Remote Config)
1. Desplegar CF + reglas.
2. `feature_safedate_enabled: true` + `feature_safedate_trusted_contacts_enabled: true`
   al **1-5%** (o cuenta interna). Verifica: centro visible, contactos CRUD.
3. `feature_safedate_date_plan_enabled` (crear plan desde chat — cuando la UI de
   Fase 2 esté completa).
4. `feature_safedate_checkins_enabled` (tras desplegar la Fase 3).
5. `feature_safedate_live_location_enabled` + `..._discreet_alert_enabled`
   (Fase 4; requiere App Check y revisión de permisos de ubicación).
6. `feature_safedate_post_date_review_enabled` (Fase 5).
7. `feature_safedate_ai_risk_detection_enabled` (Fase 6, con límites de coste).
8. `feature_safedate_verified_only_filter_enabled`, `..._safe_places_enabled`.

## Métricas a vigilar
`safedate_opened`, `_plan_created`, `_trusted_contact_added`,
`_checkin_missed`, `_alert_triggered`, tasa de errores de las CF, coste IA
(Fase 6). Sin datos personales (ver SAFEDATE_EVENTS.md).

## Plan de rollback
Poner `feature_safedate_enabled: false` en `config/featureFlags` → SafeDate
desaparece al instante para todos (el master switch corta todos los
sub-features). No requiere nueva build ni redeploy. Los datos existentes quedan
inertes (nada los lee con la flag OFF).

## Requisitos previos a producción
- Habilitar **App Check** en las CF sensibles.
- **Revisión jurídica** de bases legales y plazos (ver SAFEDATE_PRIVACY.md).
- Completar Fases 3-7 y sus tests antes de activar sus flags.
