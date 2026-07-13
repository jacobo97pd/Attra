# SafeDate — Eventos de Analytics

> **Nunca** se envían datos sensibles: nombre, teléfono, email, dirección,
> coordenadas, mensajes, notas de reporte, identificadores externos ni motivos
> que identifiquen a una persona. Solo el nombre del evento y valores
> categóricos/agregados. La defensa está en código: `SafeDateEvents.safeParams`
> filtra las claves prohibidas (`forbiddenParamKeys`).

| Evento | Cuándo | Parámetros permitidos (categóricos) |
|---|---|---|
| `safedate_opened` | Se abre el centro SafeDate | — |
| `safedate_plan_started` | Empieza el flujo de crear plan | `source` (chat/ai) |
| `safedate_plan_created` | Plan creado | `has_contacts` (bool), `duration_bucket` |
| `safedate_plan_cancelled` | Plan cancelado | — |
| `safedate_plan_completed` | Cita marcada completada | — |
| `safedate_trusted_contact_added` | Contacto añadido | `contacts_count_bucket` |
| `safedate_checkin_created` | Check-in programado | `type` (arrival/during/return) |
| `safedate_checkin_completed` | Check-in respondido OK | `type` |
| `safedate_checkin_missed` | Check-in perdido | `type` |
| `safedate_alert_triggered` | Alerta emitida | `alert_type` (sin metadatos personales) |
| `safedate_post_review_completed` | Revisión post-cita enviada | `felt_safe` (bool), `has_concern` (bool) |
| `safedate_report_started` | Se inicia un reporte | — |
| `safedate_ai_warning_shown` | Advertencia IA mostrada | `pattern_category` |
| `safedate_ai_warning_dismissed` | Advertencia IA descartada | `pattern_category` |
| `safedate_live_location_enabled` | Ubicación temporal activada | — |
| `safedate_live_location_disabled` | Ubicación temporal desactivada | — |

**Prohibido enviar:** contenido de mensajes, coordenadas exactas, `reason`
detallado, identidad del reportado/reportante, uid en claro como dimensión de
usuario más allá del identificador estándar de Analytics.

**Buckets sugeridos:** `duration_bucket` = `<60`/`60-120`/`>120` min;
`contacts_count_bucket` = `1`/`2-3`/`4+`.
