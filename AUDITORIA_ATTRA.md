# Auditoria de Attra

Fecha: 2026-06-06  
Alcance: estado actual del workspace local, incluyendo cambios sin commit y archivos nuevos.

## Resumen ejecutivo

Attra esta en fase MVP/prototipo avanzado, no en fase produccion.

El codigo Flutter esta razonablemente ordenado por features, `flutter analyze` pasa sin issues y el build web release compila. La app ya tiene login, onboarding completo, selfie, assets geograficos offline, perfil, feed con seed profiles y una plataforma de ajustes bastante ambiciosa.

El bloqueo principal no es de sintaxis: es de producto, seguridad y operacion. El feed real todavia no existe, los likes no se persisten, no hay matches/chats, la validacion critica vive demasiado en cliente, el borrado de cuenta tiene un riesgo serio de orden de operaciones, Android no compila con la toolchain actual y los tests ahora fallan por una expectativa desactualizada.

Estado recomendado:

- Demo web interna: viable.
- MVP cerrado con usuarios reales: viable solo tras corregir borrado de cuenta, reglas/validacion y Android si se quiere mobile.
- Produccion publica: no listo.

## Verificaciones ejecutadas

| Comando | Resultado |
| --- | --- |
| `flutter analyze` | OK, no issues. |
| `flutter build web --release` | OK, genera `build/web`. |
| `flutter test` | Falla 1 test de 8 por mismatch de mensaje en `permission-denied`. |
| `flutter build apk --debug` | Falla por Android Gradle Plugin 8.1.0, minimo requerido 8.1.1 por Flutter actual. |
| `flutter doctor -v` | Flutter 3.41.7 stable, Dart 3.11.5. Android licenses pendientes. Visual Studio no instalado. |
| `flutter pub outdated` | 37 dependencias bloqueadas en versiones antiguas y 12 constraints por debajo de versiones resolubles. |
| `firebase --version` | Firebase CLI 15.16.0 instalado. |

Nota: `flutter build apk --debug` intento autoajustar `android/app/build.gradle`; el contenido fue restaurado. No queda diff real de ese archivo.

## Estado del repositorio

El worktree esta sucio. Hay cambios modificados y muchos archivos nuevos no versionados. Esto es importante antes de cualquier commit.

Cambios modificados destacados:

- `firestore.rules`
- `pubspec.yaml` y `pubspec.lock`
- `lib/app.dart`
- Auth/session/onboarding/home/profile/splash
- Registrants generados de Linux, macOS y Windows

Archivos/carpetas nuevos destacados:

- `assets/geo/`: 250 JSON de ciudades + `countries.json`, aprox. 1.99 MB
- `lib/src/features/feed/`
- `lib/src/features/geo/`
- `lib/src/features/settings/`
- `lib/src/features/home/presentation/home_shell.dart`
- `lib/src/features/profile/presentation/`
- tests nuevos en `test/src/`
- scripts en `tool/`
- `cors.json`

Recomendacion de control: antes de seguir desarrollando, crear un checkpoint Git limpio con un commit del estado actual, pero solo despues de corregir el test roto y decidir si los registrants/platform files son parte del cambio.

## Mapa actual de la app

Stack:

- Flutter app multiplataforma.
- Firebase Auth, Firestore, Storage.
- Firestore usa base nombrada `attra-database`, configurada en `lib/app.dart`.
- Firebase Web tiene defaults embebidos en `lib/main.dart`.
- Arquitectura por features en `lib/src/features`.

Flujo de usuario:

- `SessionGate` decide entre splash, login, onboarding y home.
- Login soporta Google, Apple solo iOS y telefono/SMS.
- Onboarding tiene 7 pasos, autosave remoto de draft, validacion de edad 18+, pais/ciudad offline y selfie en vivo.
- Home usa `HomeShell` con tabs: Feed, Perfil, Ajustes.
- Perfil permite completar porcentaje, subir fotos adicionales, prompts y reclamar recompensas.
- Ajustes usa un catalogo declarativo con 8 secciones, consent records, audit events y privacy requests.

Firebase model:

- `users/{uid}`: documento privado del usuario.
- `users/{uid}/consentRecords/*`: ledger append-only desde cliente.
- `users/{uid}/privacyRequests/*`: solicitudes de privacidad creadas por cliente.
- `users/{uid}/auditEvents/*`: historial de cambios creado por cliente.
- `seed_profiles/{seedId}`: perfiles bot de prueba, lectura para usuarios autenticados.
- Storage:
  - `users/{uid}/private/live_selfie/*`
  - `users/{uid}/public/profile/*`
  - `users/{uid}/public/additional/*`
  - `seed_profiles/public/*`

## Lo que esta bien

- La base de codigo ya tiene separacion razonable entre data, domain y presentation.
- `flutter analyze` limpio es una buena senal.
- Build web release OK.
- Onboarding esta bastante avanzado: draft remoto, normalizacion, payload compatible con reglas, selfie duplicada en ruta privada/publica, pais/ciudad offline.
- Firestore/Storage cierran por defecto en rutas no contempladas.
- Settings Platform esta bien planteada como catalogo declarativo, con metadatos legales y auditoria visible.
- Hay tests utiles para `OnboardingRepository`, no solo el placeholder.
- Los assets geograficos estan empaquetados y cargan lazy por pais.

## Riesgos criticos

### 1. Borrado de cuenta puede dejar al usuario sin datos antes de borrar Auth

En `SessionController.deleteAccount`, primero se ejecuta `deleteUserData(uid)` y despues `deleteCurrentUserAccount()`.

Referencias:

- `lib/src/features/auth/presentation/session_controller.dart:328`
- `lib/src/features/auth/presentation/session_controller.dart:349`
- `lib/src/features/auth/data/user_repository.dart:504`

Riesgo:

Si Firebase Auth exige reautenticacion reciente, el documento y fotos ya pueden estar borrados, pero la cuenta Auth sigue viva. Esto puede dejar una cuenta autenticable sin perfil o recrear estado inconsistente al volver a sincronizar.

Ademas, borrar un documento Firestore no borra subcolecciones. `consentRecords`, `privacyRequests` y `auditEvents` pueden quedar retenidos como subcolecciones huerfanas.

Accion:

Mover borrado real a backend/Cloud Function con reautenticacion previa, borrado recursivo y estado de solicitud. Si se mantiene cliente, reautenticar primero y despues borrar datos/Auth en una secuencia controlada.

### 2. Las reglas permiten demasiada confianza en cliente

`firestore.rules` limita claves top-level, pero permite que el owner actualice campos sensibles como:

- `profileCompleted`
- `onboardingCompleted`
- `profileCompletionPercent`
- `profileCompletionRewardsClaimed`
- `availableProfileRewards`
- `verification`
- `aiData`
- `photos`
- `settings`

Referencias:

- `firestore.rules:21`
- `firestore.rules:108`

Riesgo:

Un usuario autenticado puede autoescribirse estados de perfil, verificacion o recompensas si manipula el cliente. Para MVP interno puede pasar; para produccion no.

Accion:

Separar campos client-writable de server-writable. `verification`, rewards, completion y futuros matches deben calcularse o validarse en backend. Agregar tests de reglas con emulador.

### 3. No existe todavia el producto core de citas

El feed actual carga `seed_profiles`, filtra por genero/interes y los swipes solo avanzan la tarjeta.

Referencias:

- `lib/src/features/auth/data/user_repository.dart:492`
- `lib/src/features/feed/presentation/feed_screen.dart:36`
- `lib/src/features/feed/presentation/feed_screen.dart:73`
- `lib/src/features/home/presentation/home_screen.dart:633`

Falta:

- Descubrimiento de usuarios reales.
- Persistencia de likes/pass.
- Match cuando hay reciprocidad.
- Chat/mensajeria.
- Bloquear/reportar.
- Ranking/matching real.
- Exclusion de perfiles ocultos o incognito.

### 4. Ajustes y privacidad estan modelados, pero no aplicados end-to-end

Settings crea valores, consent records, audit events y privacy requests. Aun asi, muchas consecuencias no estan conectadas al sistema real.

Referencias:

- `lib/src/features/settings/data/settings_repository.dart:62`
- `lib/src/features/settings/data/settings_repository.dart:81`
- `lib/src/features/settings/data/settings_repository.dart:126`
- `lib/src/features/settings/presentation/settings_controller.dart:155`
- `lib/src/features/settings/presentation/settings_controller.dart:194`

Riesgo:

El usuario puede activar `hideProfile`, pedir exportacion o revisar consentimiento, pero no hay backend que procese exportaciones, enforcement real del feed o ciclo legal completo.

Accion:

Crear procesadores backend para privacy requests y hacer que feed/matching respeten settings de privacidad.

### 5. Android no compila con Flutter actual

`flutter build apk --debug` falla por Android Gradle Plugin 8.1.0, minimo requerido 8.1.1. Gradle wrapper 8.3 ademas esta cerca de quedar fuera de soporte.

Referencias:

- `android/settings.gradle`
- `android/gradle/wrapper/gradle-wrapper.properties`
- `android/app/build.gradle:38`

Accion:

Actualizar AGP y Gradle wrapper, aceptar licencias Android y configurar signing release real. Ahora mismo release usa debug signing.

### 6. Tests fallan

`flutter test` falla porque `onboardingSaveErrorMessage(permissionDenied)` devuelve ahora:

`No se pudo guardar onboarding (code: permission-denied). Detalle: Missing or insufficient permissions.`

El test espera el mensaje anterior:

`No se pudo guardar onboarding. Firestore denego la escritura. (code: permission-denied)`

Referencias:

- `lib/src/features/onboarding/data/onboarding_error_messages.dart:12`
- `test/src/features/onboarding/data/onboarding_repository_test.dart:61`

Accion:

Decidir si el nuevo mensaje con detalle es el comportamiento deseado. Si si, actualizar el test. Si no, volver al copy anterior.

## Riesgos altos y deuda importante

### Firebase defaults apuntan a proyecto real

`lib/main.dart` trae valores por defecto para Firebase Web, incluyendo API key y project id.

Referencia:

- `lib/main.dart:27`

La API key de Firebase no es un secreto por si sola, pero el default a produccion aumenta riesgo de escribir en el proyecto real por accidente.

Accion:

Definir flavors/envs para dev/staging/prod y evitar defaults productivos en builds locales.

### Fotos con download URLs quedan accesibles por token

El cliente obtiene `getDownloadURL()`. Aunque Storage Rules requieran usuario autenticado para rutas publicas, esos download tokens suelen permitir acceso a quien tenga la URL.

Referencias:

- `storage.rules:24`
- `storage.rules:29`
- `lib/src/features/onboarding/data/onboarding_repository.dart:604`

Accion:

Asumir que fotos de perfil son publicables dentro del producto, documentarlo en privacidad, y agregar moderacion/revocacion de tokens si hace falta.

### Verificacion y edad son cliente-only

La edad minima y la selfie se validan en cliente/onboarding. El campo final queda `liveSelfieVerified: false`.

Referencias:

- `lib/src/features/onboarding/presentation/onboarding_screen.dart:51`
- `lib/src/features/onboarding/presentation/onboarding_screen.dart:405`
- `lib/src/features/onboarding/data/onboarding_repository.dart:529`

Accion:

Para usuarios reales: backend o servicio de verificacion, control anti-manipulacion y flujo de rechazo/reintento.

### `empresa` es una invariante tecnica rara

Las reglas exigen `empresa` en cada write de usuario. El repositorio lo inyecta con `UserDocumentDefaults`.

Referencias:

- `firestore.rules:104`
- `firestore.rules:110`
- `lib/src/features/auth/data/user_document_defaults.dart`

Riesgo:

Acopla seguridad a un campo de negocio poco claro y obliga a contaminar todos los writes.

Accion:

Renombrar o eliminar si no es realmente necesario. Si es tenant/company, documentarlo como tal.

### Metadatos y release aun genericos

Referencias:

- `README.md`: minimo.
- `web/index.html:21`
- `web/manifest.json:8`
- `android/app/build.gradle:38`

Accion:

Actualizar descripcion, title, iconos, signing, app id final, privacy policy, terms y release notes.

### Dependencias antiguas

`flutter pub outdated` muestra actualizaciones directas disponibles para Firebase, image_picker, geolocator, google_sign_in, sign_in_with_apple y lints.

Accion:

No hacer upgrade masivo a ciegas. Primero estabilizar tests/build Android. Luego subir dependencias por grupos: FlutterFire, auth providers, media/location, lints.

## Plan recomendado

### Fase 0: estabilizar el checkpoint

1. Corregir el test roto de onboarding.
2. Actualizar Android Gradle Plugin y wrapper hasta que `flutter build apk --debug` pase.
3. Aceptar licencias Android.
4. Actualizar README y web metadata basica.
5. Decidir si los archivos generados de Linux/macOS/Windows se commitean.
6. Crear commit de checkpoint del estado actual.

### Fase 1: seguridad y datos

1. Rehacer borrado de cuenta con backend o reautenticacion previa.
2. Crear borrado recursivo de subcolecciones.
3. Endurecer `firestore.rules` por campos sensibles.
4. Agregar tests de reglas con Firebase Emulator.
5. Separar campos client-writable y server-writable.

### Fase 2: producto core

1. Crear modelo de discovery de usuarios reales.
2. Persistir pass/like.
3. Crear matches por reciprocidad.
4. Agregar bloqueo y reporte.
5. Aplicar settings de privacidad al feed.
6. Definir si chat entra en MVP o fase posterior.

### Fase 3: compliance y safety

1. Terms, privacy policy, edad minima y consentimiento explicito.
2. Moderacion de fotos/perfiles.
3. Proceso real de exportacion/borrado.
4. Historial/auditoria con backend, no solo cliente.
5. Politicas de retencion.

### Fase 4: produccion

1. Flavors dev/staging/prod.
2. CI con analyze, tests, build web y build Android.
3. Signing release Android.
4. Firebase App Check.
5. Monitoreo de errores.
6. Indices Firestore para queries reales.

## Prioridad inmediata

Orden recomendado para la proxima sesion:

1. Arreglar `flutter test`.
2. Arreglar build Android.
3. Corregir flujo de borrado de cuenta.
4. Endurecer reglas de campos sensibles.
5. Crear commit limpio de checkpoint.

Mi lectura: la app tiene una base prometedora y bastante trabajo ya hecho, pero necesita una semana corta de estabilizacion antes de meter mas features grandes. Ahora mismo, el riesgo no esta en "hacer mas pantallas"; esta en convertir el prototipo en un sistema controlado.
