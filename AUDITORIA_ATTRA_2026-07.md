# Auditoría completa de Attra

**Fecha:** 2026-07-07
**Versión auditada:** `1.0.26+29`
**Rama:** `apple-validation` (con cambios sin commit)
**Alcance:** estado real del workspace (código Flutter + Cloud Functions + reglas + config), verificado con métricas del repositorio, no de memoria.
**Supersede a:** `AUDITORIA_ATTRA.md` (2026-06-06), que quedó obsoleta (describía la app sin feed/likes/matches/chats, que hoy sí existen).

---

## 1. Resumen ejecutivo

Attra es una **app de citas en Flutter + Firebase** con una superficie funcional **muy amplia para su etapa**: feed con ranking, likes/super-likes (Attras), matches, chats con multimedia, stories 24h, minijuegos, IA visual (Pro), anti-ghosting, monetización por niveles, notificaciones y una capa de "AI connection" para revisión de App Store. Es un **MVP avanzado / pre-producción**, no un prototipo.

**Lo bueno:** arquitectura backend-autoritativa sólida (el cliente casi nunca escribe datos sensibles: pasa por Cloud Functions), modularidad por features, uso extensivo de feature flags + kill switches, postura RGPD cuidada (base de datos con nombre en la UE, registros de consentimiento, protección anti-captura, bloqueo por PIN/biometría) y `flutter analyze` limpio con 247 tests en verde.

**Lo que bloquea producción:** la **validación de compras (IAP) es un placeholder** — hoy se conceden consumibles/suscripciones sin verificar el recibo, lo que es un agujero de ingresos y de seguridad. Además **no hay CI** ni tests automatizados del backend (TypeScript), y hay **trabajo importante sin commitear**.

**Veredicto de madurez:**

| Escenario | ¿Listo? |
|---|---|
| Demo / TestFlight interno | ✅ Sí |
| Beta cerrada con usuarios reales (sin cobrar) | ✅ Sí, con matices |
| Monetización real (cobrar dinero) | ❌ No — falta validación de recibos IAP |
| Producción pública a escala | ⚠️ Requiere CI, tests backend y endurecer pagos |

---

## 2. Métricas del proyecto

| Métrica | Valor |
|---|---|
| Módulos de feature (Flutter) | 24 |
| Archivos Dart | 185 |
| Líneas Dart (`lib/`) | ~47.900 |
| Archivos de test | 33 |
| Tests (pasando) | **247** (0 fallos) |
| `flutter analyze` | **0 issues** |
| Cloud Functions (TS) exportadas | **51** (callables + triggers + scheduled) |
| Archivos TypeScript | 29 |
| Líneas TypeScript (`functions/src/`) | ~7.100 |
| Reglas Firestore | 399 líneas |
| Plataformas presentes | android, ios, web, macos, windows, linux |
| Commits | 47 (2026-04-04 → 2026-07-03) |

---

## 3. Arquitectura

- **Patrón:** feature-first (`lib/src/features/<feature>/{domain,data,presentation}`). Dominio puro y testeable, datos vía repositorios/servicios, presentación en widgets.
- **Backend-autoritativo:** el cliente **no escribe** matches, chats, saldo, entitlements ni planes. Todo pasa por **Cloud Functions (Admin SDK)**. Las reglas de Firestore son mayormente `read` para participantes y `write: false`.
- **Firebase:**
  - Firestore con **nombre**: `attra-database` (NO la default). Punto de fallo histórico recurrente: olvidarlo rompe lecturas.
  - Cloud Functions en **`europe-west1`** (gen2), defaults conservadores de CPU/memoria por cuota regional.
  - Storage bucket `attra-database.firebasestorage.app`.
- **Tema:** sistema de diseño premium (tema oscuro coral por defecto + tema claro "Piedra" con acento pizarra), tokens y componentes propios.

---

## 4. Inventario funcional (por módulo)

| Módulo | Estado | Notas |
|---|---|---|
| **auth** | ✅ Operativo | Google + Apple (`signInWithProvider`), sesión, onboarding gate |
| **onboarding** | ✅ | Completo, con selfie y datos de perfil |
| **profile** | ✅ | Perfil enriquecido (catálogo de rasgos, visibilidad/consentimiento por campo), prompts, media de intro (audio/vídeo) |
| **feed** | ✅ | Ranking orgánico (RankingScorer), seed profiles, feedEvents/seenProfiles, boosts |
| **match** | ✅ | Likes/Attras, matches con IDs deterministas, journey del match |
| **chat** | ✅ | Texto, imagen, foto-bomba (view-once), nota de voz, propuesta de cita, cierre elegante |
| **stories** | ✅ | Vídeo 24h, viewer, expiración por scheduler, edición estilo IG |
| **monetization** | ⚠️ | Free/Plus/Pro, entitlements backend, paywall, boosts, Attras. **IAP sin validar (ver §7)** |
| **ai_visual** | 🟡 | Vertex AI embeddings (Pro): búsqueda por parecido estético + insights. Embedding facial real = punto de integración pendiente |
| **date_plans (Attra Plans)** | 🟡 En curso | Fases 1-2 hechas (manual + reglas/Places con fallback). Fases 3 (IA), 4 (votación), 5 (gating/notifs) pendientes |
| **anti_ghosting** | ✅ | Nudges, cierre respetuoso, follow-up post-cita, score de fiabilidad |
| **spark** | ✅ (flag) | Juego de 5 min tras match |
| **chat_game / connection_lab** | ✅ (flag) | Minijuegos + capa "AI connection" para revisión App Store 4.3(b) |
| **notifications** | 🟡 | Bandeja in-app + push FCM/APNs funcionando para like/match/mensaje/spark. Varios tipos del catálogo aún **no se generan** desde backend |
| **safety** | ✅ | Bloquear, reportar, unmatch |
| **security** | ✅ | Bloqueo de app (PIN hasheado + biometría) |
| **settings** | ✅ | Plataforma de ajustes dirigida por definiciones (8 secciones), privacidad |
| **integrations** | 🟡 | Spotify (OAuth) hecho; Instagram/contactos más adelante |
| **ads** | 🟡 (flag) | AdMob native en feed, ocultos a Plus/Pro, **IDs de test** (falta cuenta real) |
| **geo** | ✅ | Validación de ciudad offline |
| **i18n** | 🟡 | Infra gen-l10n + ARB es/en; migración de textos **incremental** |

Leyenda: ✅ operativo · 🟡 parcial/en curso · ⚠️ riesgo.

---

## 5. Backend — Cloud Functions (51)

Agrupadas por dominio (todas `europe-west1`, Admin SDK contra `attra-database`):

- **Likes/Match:** `sendLike`, `passProfile`, `sendAttra`, `rewindFeedAction`, `unmatch`, `blockUser`, `reportUser`
- **Chat:** `sendMessage`, `sendMediaMessage`, `openBombImage`, `markMessagesAsRead`, `markChatAsUnread`, `setTyping`, `sendDateProposal`, `respondDateProposal`, `closeConversationGracefully`
- **Attra Plans:** `createDatePlanProposal`, `generateDatePlanSuggestions`
- **Anti-ghosting:** `sendPendingReplyNudges`, `answerDateFollowUp`, `recomputeReliabilityScores`
- **Minijuegos:** `startChatGame`, `respondChatGame`, `finishChatGame`, `abandonChatGame`, `startDoubleAnswer`, `submitDoubleAnswer`, `startTwoTruths`, `guessTwoTruths`
- **Stories:** `createStory`, `viewStory`, `replyToStory`, `deleteStory`, `cleanupExpiredStories`
- **Spark:** `completeSparkSession`
- **Boosts:** `activateBoost`, `expireBoosts`, `getActiveBoostForUser`, `getBoostSummary`, `recordBoostImpression`
- **Monetización:** `grantConsumable` ⚠️, `verifyPurchase` ⚠️, `grantMonthlyAttras`, `runMonthlyAttraGrant`
- **IA visual:** `analyzeReferencePhoto`, `getProfileInsights`, `getVisualMatches`, `clearAiData`
- **Ranking:** `rankingOnLike/Match/Message/Report/Block/GameSession`, `rankingNightly`
- **Métricas:** `productMetricsOnEvent`, `productMetricsFinalize`
- **Discovery:** `onUserWrittenSyncDiscovery`, `backfillDiscovery`
- **Notificaciones:** `onLikeCreated`, `onMatchCreated`, `onMessageCreated`, `onSparkSessionCreated`, `sendComeBackNotifications`, `registerPushToken`, `unregisterPushToken`
- **Integraciones:** `spotifyConnect`, `spotifyRefresh`, `spotifyDisconnect`

---

## 6. Seguridad y privacidad

**Fortalezas:**
- Escritura de datos críticos **solo por backend**; reglas Firestore restrictivas (participantes leen, cliente no escribe).
- **RGPD:** base de datos en la UE, `consentRecords`, `privacyRequests`, `auditEvents` por usuario; datos biométricos (embeddings IA) **nunca** salen al cliente.
- **Protección anti-captura** (ScreenGuard) en fotos-bomba (móvil).
- **Bloqueo de app** con PIN hasheado (no en claro) + biometría.
- Foto-bomba **view-once real**: se descargan bytes y se borra el objeto de Storage.
- Anti-abuso en Attra Plans (máx propuestas abiertas, cooldown, TTL) y validación server-side de pertenencia/bloqueo.

**Riesgos:**
- 🔴 **API key de Google Places compartida en texto plano** (en esta conversación). Está en `functions/.env` (gitignored) pero **debe restringirse a Places API y preferiblemente rotarse**.
- 🟠 Validación de compras en cliente/placeholder (ver §7).
- 🟡 Reglas de `users/{uid}` deliberadamente ligeras (no validan tipos exhaustivamente): aceptable, pero conviene revisarlas antes de escala.

---

## 7. Monetización — ⚠️ el punto más crítico

Niveles Free/Plus/Pro con entitlements backend-autoritativos, paywall, catálogo de productos determinista, Attras (consumibles) y Boosts. La arquitectura de gating es buena (fuente de verdad centralizada).

**PERO la validación de recibos NO está implementada:**
- `functions/src/consumables.ts` → `grantConsumable` **abona directamente** el saldo. Comentario en el código: *"⚠️ PLACEHOLDER DE COMPRA: hoy abona directamente (MVP/pruebas)"*.
- `functions/src/subscriptions.ts` → `verifyPurchase` **confía en el recibo** sin verificarlo contra la tienda.
- `boost_service.dart` documenta el mismo placeholder.

**Impacto:** en el estado actual, un cliente modificado podría **conceder consumibles o Pro sin pagar**. Esto es **bloqueante para monetizar en producción**.

**Acción requerida antes de cobrar:** implementar validación real de recibos contra **Google Play Developer API** (Android) y **App Store Server API** (iOS), con service account / clave firmada, idempotencia por `orderId`/`transactionId`, y manejo de reembolsos/revocaciones.

---

## 8. Inteligencia artificial

- **IA visual (Pro):** Vertex AI `multimodalembedding@001` para ordenar candidatos por parecido **estético** (no identidad), con caché por hash y consentimiento explícito (`requireProAiConsent`). El embedding facial "real" queda como punto de integración de proveedor.
- **Attra Plans:** hoy la "IA" es **reglas deterministas** (extracción de intereses por keywords, espejo Dart↔TS testeado). La IA generativa real (Vertex) para afinar intereses/tono llega en Fase 3. **No inventa lugares**: los verifica Google Places.

---

## 9. Feature flags y kill switches

Config remota en `config/featureFlags` (Firestore), parseo snake_case + camelCase, con defaults seguros. Flags activos: `ads_enabled`, `spark_enabled`, `match_journey_enabled`, `icebreakers_enabled`, `mini_games_enabled`, `double_answer_enabled`, `two_truths_enabled`, `this_or_that_enabled`, `chat_game_enabled`, `date_builder_enabled`, `match_reactivation_enabled`, y **Attra Plans**: `date_plans_enabled`, `date_plans_ai_enabled`, `date_plans_places_enabled`, `date_plans_auto_nudge_enabled`, `date_plans_kill_switch`, `date_plans_free_limit`. Hay `aiKillSwitch` global. **Muy buen higiene operativa.**

---

## 10. Calidad, tests y CI

- **Tests Dart:** 247 pasando, 33 archivos, cubriendo dominio de chat, match, feed/ranking, monetización, stories, perfil, seguridad, onboarding, connection_lab y date_plans.
- 🟠 **No hay tests de Cloud Functions (TypeScript):** la lógica más crítica (saldo, pagos, matching, anti-abuso) **no tiene tests automatizados**. La lógica de reglas de Attra Plans se testea en Dart (espejo), pero el resto del backend no. No hay runner (jest/vitest) configurado.
- 🟠 **No hay CI/CD:** no existe pipeline (`.github/workflows` ausente) que ejecute `flutter analyze` + `flutter test` + `tsc` en cada push/PR.
- **Análisis estático:** `flutter analyze` limpio.

---

## 11. Riesgos y deuda técnica (priorizados)

### 🔴 P0 — Bloqueante antes de producción/monetización
1. **Validación de recibos IAP ausente** (`consumables.ts`, `subscriptions.ts`). Se pueden conceder pagos sin verificar. Implementar validación real por tienda antes de cobrar.
2. **API key de Places expuesta.** Restringir a Places API (New) + application restriction, y rotar.

### 🟠 P1 — Importante (antes de escalar)
3. **Sin CI** que corra analyze/test/tsc automáticamente.
4. **Sin tests del backend TS.** Añadir jest/vitest al menos para pagos, matching y anti-abuso.
5. **Trabajo sin commitear** en `apple-validation` (tema Piedra + Attra Plans fases 1-2). Riesgo de pérdida → commitear/mergear.
6. **Attra Plans incompleto:** faltan Fase 3 (IA), 4 (votación/confirmación) y 5 (gating/notifs). Además solo se abre desde la pestaña **Chats**: `feed_screen` y `likes_received_screen` construyen `ChatDetailScreen` sin los parámetros nuevos (inconsistencia de UX).
7. **Notificaciones incompletas:** varios tipos del catálogo (`dateProposed`, `matchCooling`, `likesWaiting`, `profileOnFire`, `dailyLikesReset`) no se generan desde backend todavía.

### 🟡 P2 — Deuda / mejoras
8. **Build Android sin re-verificar** (la auditoría de junio reportaba que no compilaba con la toolchain; no revalidado en esta sesión → comprobar).
9. **6 plataformas presentes** pero foco real móvil/web; desktop probablemente sin mantener.
10. **AdMob con IDs de test** (falta cuenta real + config de plataforma).
11. **i18n a medias** (infra lista, textos migrándose de forma incremental).
12. **IA visual:** embedding facial real pendiente de proveedor.
13. **Documentación de arquitectura/onboarding de devs** escasa (README + notas dispersas).

---

## 12. Estado de release / App Store

- Versión `1.0.26+29`. Existe `APP_STORE_REVIEW_NOTES.md` con la estrategia de reposicionamiento **4.3(b)** (capa "AI connection": Connection Lab, Demo Challenge, Anti-Ghosting Coach, AI Compatibility, Date Planner, Conversation Games) sin ocultar features ni detectar revisores.
- Login Apple, push (APNs producción) e IAP-IDs ya resueltos en iteraciones previas.

---

## 13. Recomendaciones priorizadas (plan de acción)

1. **Antes de cobrar un euro:** implementar validación real de recibos IAP (Google Play Developer API + App Store Server API), idempotente. *(P0)*
2. **Hoy mismo:** restringir/rotar la API key de Places. *(P0)*
3. **Commitear y mergear** el trabajo pendiente de `apple-validation`. *(P1)*
4. **Montar CI** (GitHub Actions): `flutter analyze`, `flutter test`, `npm --prefix functions run build`. *(P1)*
5. **Añadir tests TS** para pagos, matching y anti-abuso. *(P1)*
6. **Cerrar Attra Plans:** Fase 4 (votación) para cerrar el bucle de producto + unificar el punto de entrada del chat (feed/likes). *(P1)*
7. **Completar generación de notificaciones** backend para los tipos del catálogo ya definidos. *(P1)*
8. **Verificar build Android** y decidir qué plataformas se mantienen. *(P2)*

---

## 14. Conclusión

Attra tiene una **base técnica notablemente madura y bien pensada** para un producto de una sola persona: arquitectura backend-autoritativa, features de citas modernas (stories, IA, anti-ghosting, planes reales), y una operativa con flags y kill switches que da mucho control. El código está limpio (`analyze` sin issues, 247 tests).

El salto a producción **no es cuestión de más features, sino de endurecimiento**: cerrar los pagos (validación de recibos), automatizar calidad (CI + tests backend) y terminar los flujos a medias (Attra Plans, notificaciones). Con esos frentes cubiertos, es una app perfectamente lanzable.
