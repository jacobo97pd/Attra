# Attra — Preparación del reenvío a App Review

Respuesta a la **Submission ID 91170659-678e-46d8-8241-beabd7ae4c5b**: revisión
del 4 de agosto de 2026, versión 1.0 (61), iPad Air 11-inch (M3).

Estado del 16 de septiembre de 2026: las correcciones están en el código, las
páginas legales actualizadas están publicadas en Firebase Hosting y las dos
cuentas de prueba tienen contenido en Firebase. El acceso por número de prueba
y código fijo se ha verificado mediante la API de Firebase, sin SMS. **Falta
verificar la build en un iPhone/iPad físico, grabar la evidencia y actualizar
los campos de App Store Connect.** No se ha enviado una respuesta a Apple ni se
han modificado los metadatos de App Store desde este entorno.

**Cambio de fondo respecto a la versión anterior de este documento: el muro de
historias ya no se usa.** `config/featureFlags.storiesEnabled` está en `false`
(verificado en Firestore el 16 de septiembre de 2026), así que **Descubrir
muestra tarjetas de perfil**. El motivo es directamente la 2.1(a): las historias
caducan a las 72 horas, de modo que la pantalla principal se vaciaba sola si la
revisión se demoraba, y había que resembrarlas a mano contrarreloj. Un perfil no
caduca. Todo el recorrido de este documento se apoya ahora en perfiles.

`pubspec.yaml` indica `1.0.83+91`. De ahí sale **solo el nombre de versión**
(`--build-name`, codemagic.yaml:125-126): el número de build lo pone la variable
**`PROJECT_BUILD_NUMBER`** de Codemagic, no el `+90`. Poner ahí un número mayor
que el de la última build subida; Codemagic rechaza números iguales o inferiores
a la build 61 rechazada.

El registro de versión de App Store Connect tiene que llamarse **1.0.83** para
que acepte esta build: Apple revisó «1.0 (61)», así que si el registro sigue
siendo `1.0` hay que crear el de `1.0.83` o cambiar el nombre de versión aquí.

Validación local: **868 tests Flutter, 65 tests de backend y 23 tests Python de
preparación de la demo** superados; `flutter analyze` sin incidencias. Los endpoints de denuncia/bloqueo
y los triggers asociados también se han desplegado. Esto no acredita el funcionamiento de
StoreKit, las llamadas ni las vistas en un dispositivo físico.

## Trabajo externo pendiente

- [ ] Construir la IPA con Codemagic/macOS, instalarla mediante TestFlight y
  completar el recorrido de este documento en un iPhone/iPad físico.
- [ ] Revisar todos los productos y periodos en StoreKit; los precios deben
  cargar desde la tienda. Revisar restauración y gestión de suscripciones.
- [ ] Completar Privacy Policy URL, descripción con EULA estándar Apple,
  credenciales privadas y Notes en App Store Connect.
- [ ] Grabar la aceptación, denuncia, bloqueo y apertura de los documentos
  legales; adjuntar el vídeo y su referencia en App Review Information → Notes.
- [ ] Reemplazar todos los campos entre corchetes de los textos preparados.
  Un vídeo no sustituye las credenciales que permiten entrar en la app.

## 3.1.2(c) — Suscripciones y metadatos

La ruta con una cuenta Pro es **Perfil → Tu plan: Attra Pro** (subtítulo:
«Gestiona tu suscripción y compara los planes.»). Con una cuenta Free, la misma
tarjeta dice **Mejora a Attra Plus o Pro**. También se puede llegar desde una
función de pago.

| Información | Presentación en la pantalla de suscripciones |
| --- | --- |
| Nombre | Attra Plus / Attra Pro |
| Periodo | 1 mes o 1 año, con renovación automática |
| Precio | Importe localizado de StoreKit; sin precio inventado mientras la tienda no responde |
| Precio por unidad | Equivalente mensual del plan anual, calculado desde el precio real |
| EULA | Enlace **EULA de Apple** a la licencia estándar |
| Normas de la comunidad | Enlace **Condiciones de uso** de Attra |
| Privacidad | Enlace **Política de privacidad** |

El bloque de condiciones explica renovación, cargo, cancelación y gestión de
la suscripción. Los tres enlaces están también en el acceso y en
**Perfil → Ajustes → Legal y seguridad**:

- EULA estándar Apple: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
- Condiciones Attra y comunidad: https://attra-database.web.app/terms.html
- Privacidad: https://attra-database.web.app/privacy.html

Las condiciones de Attra y la privacidad se actualizaron y publicaron el
13 de septiembre de 2026. La versión de consentimiento del código es
`2026-09-13`. No introducir el documento comunitario como si fuera un contrato
EULA personalizado de Apple: la implementación usa **la licencia estándar de
Apple**, además de las condiciones del servicio de Attra.

En **App Store Connect → App Information → License Agreement**, utilizar el
acuerdo estándar Apple. Verificar el estado actual del campo antes de guardar;
no se ha leído desde este entorno. En el campo **Privacy Policy URL**, introducir:

```text
https://attra-database.web.app/privacy.html
```

Añadir al final de la descripción en **cada idioma publicado**:

```text
Condiciones de uso (EULA de Apple): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Condiciones del servicio y normas de la comunidad: https://attra-database.web.app/terms.html
Política de privacidad: https://attra-database.web.app/privacy.html
```

Para la descripción en inglés:

```text
Terms of Use (Apple Standard EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Service Terms and Community Rules: https://attra-database.web.app/terms.html
Privacy Policy: https://attra-database.web.app/privacy.html
```

Referencia de Apple: [Provide a custom license agreement](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement/).

## 2.1(a) — Acceso real y contenido precargado

Se reutilizaron las dos cuentas de teléfono de prueba ya existentes,
identificadas por el perfil **Apple** y por la nota de concesión de revisión de
App Store. No se crearon cuentas personales ni se cambiaron sus códigos.

Las credenciales están en el archivo local **privado e ignorado por Git**:
[build/app-review/review-credentials.txt](build/app-review/review-credentials.txt).
Copiarlas únicamente a los campos privados de App Review Information:

- **User name:** teléfono de PRIMARY, completo con prefijo internacional.
- **Password:** código fijo de PRIMARY, de seis dígitos.
- En **Notes**, añadir teléfono y código de COMPANION para usar un segundo
  dispositivo en juegos y llamadas. No publicar estas credenciales en la
  descripción pública ni añadirlas al repositorio.

La ruta de acceso en la app es: casilla de aceptación → **Continuar con teléfono** →
teléfono de prueba → código fijo. Firebase no envía SMS a estos números
configurados. La prueba REST verificó que ambos códigos devuelven el UID
esperado; la verificación de la app de Firebase en iOS aún debe probarse en la
build física. [Pruebas de teléfono en Firebase](https://firebase.google.com/docs/auth/flutter/phone-auth#testing).

| Cuenta | Contenido preparado |
| --- | --- |
| PRIMARY — Apple | Perfil y fotos existentes conservados; Pro activo; cuatro likes recibidos; chats con Ana, Inés y Alex Demo |
| COMPANION — Alex Demo | Perfil y dos fotos de prueba; onboarding/tutorial completos; Pro activo; cuatro likes recibidos; chats con Ana, Inés y Apple |
| Ambas | Modo viajes activado para España, sin ciudad concreta, para acceder a los perfiles semilla desde cualquier país |
| Descubrir | **96 perfiles semilla** permanentes, sin caducidad, todos con foto y con `currentCountryName` en España |

La lectura posterior a la siembra confirmó tres matches/chats y cuatro likes
recibidos por cuenta. Con tokens de las propias cuentas, Firebase devolvió
HTTP 200 para perfil, match, chat, mensaje y perfil semilla, y HTTP 404 para el
consentimiento vigente aún no aceptado (sin errores de permisos). Esto valida
acceso a datos; la interfaz física sigue pendiente.

La configuración real es `config/featureFlags.storiesEnabled=false`, así que la
pestaña **Descubrir** muestra tarjetas de perfil. Los perfiles semilla son mocks
compartidos (`isBot: true`), no detectan al revisor ni activan comportamiento
oculto. Ana/Inés y el resto de mocks no responden por sí solos; el chat entre
Apple y Alex Demo permite operar ambos lados en dos dispositivos.

**Cobertura de los perfiles semilla.** El 16 de septiembre de 2026 se sembraron
37 perfiles nuevos (`tool/seed_identity_matrix.py`, prefijo `mock_ix_`) para que
el feed no dependa de quién mire: cubren las **8 identidades de género**, las
**10 orientaciones** y los **4 modos de intención** que ofrece el onboarding, con
edades de 19 a 58. Antes solo había perfiles `male` y `female`, de modo que una
cuenta que se declarase no binaria, trans o agénero podía terminar el onboarding
y encontrarse el feed vacío. Si el revisor crea una cuenta propia con cualquier
identidad, ahora ve perfiles.

No se han falsificado aceptaciones legales ni consentimientos de IA. Al entrar
en la nueva build, completar los consentimientos que se soliciten. Ambas
cuentas mantienen su Pro existente; las concesiones manuales no representan
compras reales de App Store.

### Mantenimiento de la demo

El script hace un **commit atómico por ejecución**, usa máscaras de campos que
conservan ajustes y consentimientos ajenos a la siembra, y verifica los perfiles
requeridos antes de escribir. Los backups previos a esta preparación se guardan
en `build/app-review/demo-backup-primary.json` y
`build/app-review/demo-backup-companion.json`, también ignorados por Git.

Inspección totalmente offline:

```powershell
python -m unittest tool.test_seed_review_demo
python tool/seed_review_demo.py --dry-run --uid demo_offline --peer-uid peer_offline --travel-spain
python tool/seed_identity_matrix.py --dry-run
```

Comprobación de requisitos en Firebase, sin escribir:

```powershell
$env:GTOKEN = gcloud auth print-access-token
$env:DEMO_UID = "[UID PRIMARY del archivo privado]"
python tool/seed_review_demo.py --check-only --keep-profile
```

Resembrar los perfiles de la matriz de identidades (idempotente, no toca las
cuentas de revisión ni sus chats):

```powershell
$env:GTOKEN = gcloud auth print-access-token
python tool/seed_identity_matrix.py
```

`--with-stories` y `--stories-only` de `seed_review_demo.py` **ya no se usan**:
el muro de historias está apagado y las historias eran justamente lo que
caducaba a las 72 horas. Los perfiles no caducan, así que no hay nada que
renovar contrarreloj durante la revisión.

La siembra completa restablece estados de los likes y resúmenes de los chats de
prueba, y conserva los mensajes adicionales. Usarla solo si hace falta preparar
de nuevo el contenido; no ejecutarla como mecanismo periódico de renovación:

```powershell
python tool/seed_review_demo.py --keep-profile --travel-spain --peer-uid "[UID COMPANION]"
```

La siembra no elimina bloqueos, denuncias ni dislikes previos. Después de grabar,
comprobar que siguen quedando perfiles visibles; usar un perfil distinto para el
bloqueo y no bloquear la cuenta compañera necesaria para juegos/llamadas.
Validar también herramientas de IA, permisos de cámara/micrófono, consumibles y
servicios externos de la build. No afirmar que las funciones con otro
participante funcionan solo porque hay mensajes sembrados.

## Arreglos de producto hechos al preparar este reenvío

Ninguno lo pidió Apple; salieron al probar el recorrido con identidades que
antes no se habían probado. Se anotan aquí porque cambian lo que el revisor ve.

1. **Cinco de las ocho identidades de género eran invisibles en el feed.** El
   onboarding deja declarar ocho géneros, pero «a quién buscas» solo tiene tres
   casillas, y el filtro comparaba los dos campos en crudo. Una mujer trans, un
   hombre trans, una persona de género fluido, agénero o «otro» no coincidía con
   nadie que hubiera dicho a quién busca: feed vacío, sin error y sin arreglo
   posible desde la app. Se traduce cada identidad a su casilla en
   `lib/src/features/profile/domain/gender_matching.dart` (una mujer trans entra
   en «Mujer»; género fluido y agénero, en «No binario»; «otro» no excluye).
   Aplicado en `FeedFilter`, en el filtro «Mostrarme» del panel, en
   `functions/src/live.ts` y en los sinónimos de `functions/src/promptMatch.ts`.
2. **El feed solo leía 30 perfiles semilla, siempre los mismos.** La consulta
   era `where('isBot',==,true).limit(30)` sin `orderBy`, así que Firestore
   devolvía los 30 primeros por id de documento. Con 96 perfiles en la
   colección, todo lo que ordenara después no existía: de los 37 perfiles
   sembrados para cubrir identidades, **solo 5 habrían llegado al feed**. Tope
   subido a 150 en `user_repository.dart`.
3. **Textos en inglés dentro de una interfaz en castellano.** El estado vacío de
   Chats y tres entradas del menú ⋮ de una conversación estaban en inglés
   («No conversations yet», «AI Compatibility»...). Traducidos.

4. **Se pagaba y el plan no llegaba.** Tres eslabones rotos en la misma
   cadena: (a) `verifyPurchase` trataba un recibo ya visto devolviendo sin tocar
   nada, así que si el entitlement se había perdido, «restaurar compras» decía
   que restauraba y no restauraba; (b) en iOS el recibo cambia en cada llamada,
   así que cada reintento entraba como compra nueva y regalaba un periodo (en
   producción había nueve apuntes de la misma suscripción); (c) el cliente leía
   el plan UNA vez, de modo que el tier concedido segundos después de la compra
   —o al renovarse— no llegaba hasta reiniciar la app. Ahora un duplicado
   reconcilia el entitlement, reentregar la misma suscripción vigente no alarga
   nada, y el cliente escucha `userEntitlements` y los flags en vivo (los
   streams ya existían y no los usaba nadie). `verifyPurchase` desplegado el
   18-sep-2026. La decisión de qué conceder vive en `resolveGrant`, con 11
   tests.

**Pendiente, no bloqueante:** el módulo `lib/src/features/connection_lab/`
(1.761 líneas: Demo Challenge, Anti-Ghosting Coach, AI Compatibility, AI Date
Planner) está **entero en inglés** y se llega a él desde el ⋮ de cualquier chat.
No es motivo de rechazo, pero un revisor lo verá.

## 1.2 — Acuerdo, denuncias y bloqueo

La pantalla inicial exige marcar explícitamente:

> Tengo 18 años o más y acepto las Condiciones de uso y el EULA, y he leído la
> Política de privacidad. Attra tiene tolerancia cero con el contenido ofensivo
> y con los usuarios abusivos.

La condición se presenta antes de teléfono, Apple y Google. Los tres documentos
completos se abren desde esa misma pantalla. La aceptación de la versión vigente
se registra en `users/{uid}/consentRecords/terms_<versión>`; si falla, la app pide
reintentar. Una sesión restaurada que carezca de una aceptación vigente muestra
la puerta de consentimiento antes de dar acceso. El script de demo no registra
consentimiento en nombre de nadie.

Las condiciones de la comunidad prohíben el contenido ofensivo y a los usuarios
abusivos, describen retirada y expulsión y comprometen revisión en menos de
24 horas. Ese compromiso requiere que el equipo atienda la cola de moderación.

| Acción | Ruta en la interfaz |
| --- | --- |
| Denunciar desde el feed | Descubrir → ⋮ de la tarjeta de perfil → hoja **Reportar / Bloquear** → **Reportar** → motivo → enviar |
| Bloquear desde el feed | Descubrir → ⋮ de la tarjeta → hoja → **Bloquear** → confirmar |
| Denunciar/bloquear un perfil completo | Conexiones → abrir perfil, o abrir perfil desde la cabecera del chat → ⋮ → **Reportar** / **Bloquear** |
| Denunciar/bloquear desde el chat | Chats → conversación → ⋮ → **Reportar** / **Bloquear** |

Dos matices que conviene conocer antes de grabar, porque cambian el número de
toques: desde la **tarjeta del feed** el ⋮ abre primero una hoja con las dos
opciones, mientras que desde el ⋮ del **chat** y del **perfil completo** se va
directo a la acción. Y ninguna de las dos exige match previo: la llamada de
backend solo pide sesión iniciada.

Una denuncia entra en la cola del backend. El bloqueo impide interacción y
retira a la persona; si ya existía, cierra el match/chat. Quien queda bloqueado
no vuelve al feed, ni siquiera con «Dar una segunda vuelta»; quien solo se pasa
sí vuelve. Verificar en dispositivo que la acción aparece confirmada y que el
contenido queda excluido.

## Guion de grabación en dispositivo físico

Usar **la build que se enviará**, instalada en un iPhone o iPad físico. Registrar
modelo, versión iOS/iPadOS, versión de Attra y número de build. Mantener
**Perfil → Ajustes → Seguridad → Proteger capturas de pantalla** desactivado.
Cerrar sesión antes del primer paso; no eliminar la cuenta.

1. Iniciar **Centro de control → Grabación de pantalla** y volver a Attra.
2. Mostrar la pantalla de acceso completa, la casilla desmarcada y los enlaces.
   Pulsar **Continuar con teléfono** para mostrar que exige aceptar.
3. Abrir **Condiciones de uso** y mostrar la sección de tolerancia cero. Volver
   y abrir **EULA de Apple** y **Política de privacidad** para demostrar acceso.
4. Marcar la casilla e iniciar sesión con PRIMARY. Mostrar la entrada a
   **Descubrir** con tarjetas de perfil cargadas, y deslizar una o dos para que
   se vea que hay contenido de sobra.
5. En una tarjeta de perfil: **⋮ → Reportar** → elegir motivo → enviar y mostrar
   la confirmación. Usar exclusivamente perfiles de prueba (`mock_*`).
6. En otra tarjeta: **⋮ → Bloquear** → confirmar → mostrar que esa persona ya no
   aparece en el feed.
7. **Chats → Ana o Inés → ⋮**: mostrar las opciones de reportar/bloquear y el
   historial de mensajes. Mantener disponible el chat Apple ↔ Alex Demo.
8. **Perfil → Tu plan: Attra Pro**: mostrar títulos, selector mensual/anual,
   duración, precio localizado y condiciones. Abrir **EULA de Apple**,
   **Condiciones de uso** y **Política de privacidad** desde esa pantalla,
   volviendo a la app tras cada documento.
9. Detener la grabación. Verificar en Fotos que el vídeo contiene todos los
   pasos, sin pantallas negras y con los enlaces cargados. Conservar el original.

Guardar la copia entregable, por ejemplo, en
`build/app-review/Attra-[VERSION]-[BUILD]-[DEVICE]-review.mp4`. Esta ruta es una
convención de entrega: **todavía no existe una grabación física generada**.
Adjuntar el archivo en la respuesta a App Review y su referencia o un enlace
accesible en **App Review Information → Notes**, también para futuros envíos.

## Texto para App Review Information → Notes

Copiar solo tras verificar el recorrido y completar los campos privados y los
marcadores. Si no se ha grabado, no afirmar que existe el vídeo.

```text
Review access — version [VERSION], build [BUILD]

The Username field contains a configured Firebase test phone number. The
Password field contains its fixed six-digit verification code. No SMS is sent.
Accept the Terms of Use/EULA on the initial screen, tap "Continuar con teléfono",
enter the full phone number and then enter the code from the Password field.

The primary account is named Apple and has Pro access, received likes and
pre-populated conversations. Discover ("Descubrir") shows a deck of 96 sample
profiles covering every gender identity, orientation and intent mode the app
offers. Travel mode is configured to Spain so the test profiles are available
independently of your device location.

Second account for two-person features:
Username: [COMPANION PHONE — PRIVATE]
Password: [COMPANION FIXED CODE — PRIVATE]
Display name: Alex Demo
Sign into this account on a second device and open the existing Apple ↔ Alex
Demo conversation to test games and calls from both sides. The other sample
profiles do not respond automatically. [ADD ANY VERIFIED ADDITIONAL STEPS.]

Subscription information and legal documents: Profile ("Perfil") → "Tu plan:
Attra Pro". The page shows plan names, billing periods, localized StoreKit prices
and links to Apple Standard EULA, Attra Service Terms and Privacy Policy.

UGC safety: Discover → three-dot menu on a profile card → Report or Block. The
same actions are available from conversation and full-profile menus. Neither
requires a previous match.

Physical-device recording: [ATTACHED FILENAME / ACCESSIBLE LINK]
Device and OS: [MODEL / IOS OR IPADOS VERSION]
Build shown in recording: [BUILD]
The recording shows agreement before login, reporting, blocking and opening
both required legal links from the subscription flow.
```

## Respuesta preparada a Apple

**Enviar solo después de completar la build física, metadatos y grabación.**
Este es un borrador, no una respuesta ya enviada.

```text
Hello App Review team,

We are resubmitting version [VERSION], build [BUILD], in response to submission
91170659-678e-46d8-8241-beabd7ae4c5b.

3.1.2(c): Profile → "Tu plan: Attra Pro" opens the subscription screen, which
shows subscription names, billing periods, localized StoreKit prices and
renewal information. The purchase flow contains working links to Apple
Standard EULA, Attra Service Terms and Privacy Policy. We have added the Apple
Standard EULA link to every published App Description localization and entered
the Privacy Policy URL in the corresponding App Store Connect field.

2.1(a): App Review Information contains a configured test phone number and
fixed verification code. Select "Continuar con teléfono" and use the Password
field as the verification code; no SMS is required. The account has Pro access,
sample profiles, received likes and populated conversations. Notes also include
a second account and instructions for reviewing two-person features.

1.2: Users must explicitly accept the Terms of Use and EULA before registering
or logging in. The community terms prohibit objectionable content and abusive
behavior. Users can report content and block users from story, profile and
conversation menus.

The attached recording [FILENAME / ACCESSIBLE LINK], captured on a physical
[DEVICE / OS] running build [BUILD], demonstrates the agreement before login,
reporting, blocking and opening the EULA and Privacy Policy from the purchase
flow. We have included the recording reference and review instructions in
App Review Information → Notes for future submissions.

Thank you.
```
