# Attra — App Store Review Notes

> Respuesta al rechazo de la **Submission ID 91170659-678e-46d8-8241-beabd7ae4c5b**
> (revisión del 4 de agosto de 2026, versión 1.0 (61), iPad Air 11-inch M3).

Esta build resuelve los tres puntos señalados: **3.1.2(c)** (información de las
suscripciones), **2.1(a)** (acceso de la cuenta demo) y **1.2** (contenido
generado por usuarios).

---

## 1. Guideline 3.1.2(c) — Suscripciones de renovación automática

**Dentro de la app**, la pantalla de suscripciones (*Perfil → Hazte Plus/Pro*,
o cualquier función de pago) muestra ahora, para cada plan:

| Requisito de Apple | Dónde aparece |
| --- | --- |
| Título de la suscripción | Título de la tarjeta: **Attra Plus** / **Attra Pro** |
| Duración | Bajo el precio: *«Suscripción de 1 mes · se renueva automáticamente cada mes»* (o *1 año*) |
| Precio | Precio del producto real de StoreKit (`9,99 € / mes`, `99,99 € / año`) |
| Precio por unidad | En el plan anual: *«Equivale a 8,33 € / mes»* (calculado desde el precio real) |
| Enlace funcional al EULA | Bloque **«Condiciones de la suscripción»** → *Condiciones de uso (EULA)* |
| Enlace funcional a la privacidad | Mismo bloque → *Política de privacidad* |

Ambos enlaces abren el navegador del sistema:

- Términos de uso (EULA): https://attra-database.web.app/terms.html
- Política de privacidad: https://attra-database.web.app/privacy.html

El mismo bloque explica la renovación automática, el cargo en las 24 horas
previas, la cancelación desde los ajustes de la cuenta de App Store y que
eliminar la app no cancela la suscripción.

**En los metadatos de App Store Connect** (confirmar antes de enviar):

- *App Privacy Policy URL* → `https://attra-database.web.app/privacy.html`
- *License Agreement* → EULA personalizado en `App Information → License
  Agreement`, con el texto de `https://attra-database.web.app/terms.html`, y
  además el enlace al EULA añadido al final de la *App Description*.

---

## 2. Guideline 2.1(a) — Cuenta demo con contenido

La cuenta demo usa un **número de teléfono de prueba de Firebase Auth**: no
envía SMS y el código es fijo, así que funciona desde cualquier red y país.

- **User name:** `__________` (teléfono de prueba, formato `+34600000000`)
- **Password:** `__________` (código fijo de 6 dígitos)

> Rellenar en *App Store Connect → App Review Information* antes de enviar.
> El teléfono y su código se dan de alta en
> *Firebase Console → Authentication → Sign-in method → Phone → Phone numbers
> for testing*.

La cuenta llega **pre-poblada** (script `tool/seed_review_demo.py`):

- Perfil completo, onboarding y tutorial ya finalizados: el revisor entra
  directo a la app.
- **Feed con otros usuarios** visibles y con fotos.
- **Likes recibidos** de varias personas (pestaña *Conexiones*).
- **Dos chats con historial de mensajes** (pestaña *Chats*).
- **Attra Pro activo**, de modo que todas las funciones de pago son
  verificables sin realizar ninguna compra.

Pasos para acceder: abrir la app → marcar la casilla de aceptación de las
Condiciones → *Continuar con teléfono* → introducir el teléfono de prueba →
introducir el código fijo → la app abre directamente en *Descubrir*.

---

## 3. Guideline 1.2 — Contenido generado por usuarios

### a) EULA aceptado antes de registrarse o iniciar sesión

La primera pantalla de la app muestra, **encima de todos los métodos de
acceso**, una casilla obligatoria:

> «Tengo 18 años o más y acepto las **Condiciones de uso (EULA)** y la
> **Política de privacidad**. Attra tiene **tolerancia cero** con el contenido
> ofensivo y con los usuarios abusivos.»

Debajo hay dos enlaces funcionales que abren los documentos completos. Mientras
la casilla no esté marcada, **ningún método de acceso funciona** (teléfono,
Apple ni Google): al pulsarlos, la app avisa de que hay que aceptar las
condiciones. La versión del EULA aceptada queda registrada en el ledger de
consentimientos del usuario (`users/{uid}/consentRecords/terms_<versión>`).

El EULA (https://attra-database.web.app/terms.html) abre con la sección
**«1. Tolerancia cero con el contenido ofensivo y los usuarios abusivos»**, que
enumera el contenido prohibido y establece que el contenido infractor se
elimina y la cuenta se expulsa, con revisión de los reportes **en menos de 24
horas**.

### b) Mecanismo para denunciar contenido objetable

Disponible sin necesidad de match previo:

- **Feed** (*Descubrir*): botón **⋮** en la esquina superior derecha de cada
  tarjeta de perfil → *Reportar* → lista de motivos (contenido inapropiado,
  acoso o abuso, spam o estafa, perfil falso, parece menor de edad, otro).
- **Ficha de perfil** (desde *Conexiones* o desde un chat): menú **⋮** de la
  barra superior → *Reportar*.
- **Chat**: menú **⋮** → *Reportar*.

El reporte se envía a la función de backend `reportUser`, queda en la cola de
moderación y la app confirma que se revisa en menos de 24 horas.

### c) Mecanismo para bloquear usuarios abusivos

En los mismos tres sitios (feed, ficha de perfil y chat): **⋮ → Bloquear**, con
diálogo de confirmación. El bloqueo cierra el match y el chat existentes,
impide nuevos mensajes y retira a la persona del feed al instante.

### Guion sugerido para la grabación de pantalla

1. Abrir la app: se ve la casilla del EULA y los enlaces; pulsar un método de
   acceso sin marcarla y mostrar que **no** deja continuar.
2. Abrir *Condiciones de uso (EULA)* y mostrar la sección de tolerancia cero.
3. Marcar la casilla e iniciar sesión con la cuenta demo.
4. En *Descubrir*, pulsar **⋮** sobre una tarjeta → *Reportar* → elegir motivo
   → confirmación.
5. Repetir **⋮** → *Bloquear* → confirmar → el perfil desaparece del feed.
6. Abrir un chat de la pestaña *Chats* → **⋮** → mostrar *Reportar* y
   *Bloquear*.
7. Abrir la pantalla de suscripciones y mostrar título, duración, precio y los
   enlaces al EULA y a la política de privacidad.

---

## Navegación de esta build

`Descubrir` · `Conexiones` · `Chats` · `Perfil`

- **Descubrir** → feed de descubrimiento (con reportar/bloquear en cada
  tarjeta).
- **Conexiones** → likes recibidos y matches.
- **Chats** → conversaciones, con las herramientas de IA (retos guiados,
  Anti-Ghosting Coach, compatibilidad, planificador de citas).
- **Perfil** → perfil, ajustes, suscripciones y la sección **Legal y
  seguridad** (EULA, privacidad, seguridad infantil y soporte).

## Qué hace diferente a Attra

- **Retos de conversación guiados por IA** con feedback en tiempo real.
- **Anti-Ghosting Coach**: equilibrio de la conversación y siguiente acción
  saludable sugerida. Nunca envía nada por su cuenta.
- **Compatibilidad explicada**: no solo un porcentaje, sino 3-5 razones.
- **Planificador de citas con IA**: ideas de primera cita y un mensaje de
  propuesta listo para revisar y enviar.
- **Juegos de conversación**: Rompe el hielo, Attra Spark, Esto o aquello…
- **Attra SafeDate**: plan de cita seguro, check-ins y contactos de confianza.

Attra nunca envía un mensaje en nombre del usuario: cada sugerencia se coloca
en el campo de texto para que la persona la revise, edite y envíe.

## Notas para el revisor

- La app está localizada en español e inglés y sigue el idioma del sistema.
- El teléfono demo es un número de prueba de Firebase: no se envía SMS y el
  código no caduca.
- Las compras usan exclusivamente la pasarela nativa de App Store; la concesión
  del plan se verifica siempre en el servidor.
