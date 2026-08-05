# Perfil rápido por voz: checklist de lanzamiento

La función está deliberadamente **apagada por defecto**. El onboarding manual
permanece disponible aunque falle cualquier dependencia de IA.

## 1. Bucket efímero europeo

1. Crear un bucket dedicado dentro de la UE y confirmar su ubicación real.
2. Aplicar `storage.rules` al bucket y validar que el cliente solo puede crear
   y borrar su propio objeto bajo
   `ephemeral/onboarding_voice/{uid}/voice_{timestamp}.{ext}`.
3. Revisar versionado, soft delete, retención, backups y logs: el audio debe
   borrarse tras el intento y el barrido de seguridad elimina huérfanos con más
   de una hora.
4. Configurar el mismo bucket en ambos lados:

   - Flutter:
     `--dart-define=VOICE_PROFILE_STORAGE_BUCKET=nombre-del-bucket`
   - Cloud Functions:
     `VOICE_PROFILE_STORAGE_BUCKET=nombre-del-bucket`

El bucket Firebase actual fue detectado en `US-CENTRAL1`; no debe usarse para
activar esta función si se promete residencia íntegra del audio en la UE.

## 2. Vertex AI

- Proyecto con Vertex AI habilitado y cuenta de servicio con el mínimo permiso
  necesario.
- Región fijada en `europe-west4`.
- Modelo por defecto `gemini-2.5-flash`; se puede sustituir con
  `VOICE_PROFILE_MODEL`.
- Revisar disponibilidad y ciclo de vida del modelo antes de cada release.

La Function usa salida JSON estructurada, no escribe el perfil y nunca registra
audio, transcripción, fecha de nacimiento ni texto generado en logs.

## 3. App Check y flags

1. Registrar Android, iOS/macOS y Web en Firebase App Check.
2. Validar tráfico real y métricas antes de exigir tokens.
3. Activar `VOICE_PROFILE_ENFORCE_APP_CHECK=true` en Functions.
4. Solo entonces habilitar en `config/featureFlags`:

   - `voiceProfileEnabled: true`
   - `aiProcessingEnabled: true`
   - `aiKillSwitch: false`

Tanto cliente como servidor exigen activación explícita. Desactivar cualquiera
de esos flags mantiene el alta manual operativa.

## 4. Verificación previa a producción

- Probar grabación, reproducción, regrabación y abandono en cada plataforma.
- Confirmar formatos WebM/Opus, M4A/AAC, OGG y WAV soportados.
- Verificar el borrado inmediato, el barrido programado y los objetos huérfanos.
- Comprobar el ledger de consentimiento y su caducidad de evidencia.
- Ejecutar `flutter analyze`, `flutter test`, `npm run build` en `functions/` y
  el dry-run de reglas de Storage.
- Probar kill switch, rate limit, usuario menor de 18, App Check inválido,
  timeout de Vertex y respuesta fuera de schema.

