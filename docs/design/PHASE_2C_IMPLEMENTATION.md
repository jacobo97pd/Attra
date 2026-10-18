# Attra · Fase 2C

Implementación visual Flutter de «Nota fotográfica». 18 de octubre de 2026.

Se utilizó exclusivamente **Impeccable**, instalada en `.agents/skills/impeccable`, versión 4.6.0. Se leyó completo su [SKILL.md](../../.agents/skills/impeccable/SKILL.md), se ejecutó `impeccable context --target lib/app.dart` y se leyeron las instrucciones relevantes de refinamiento, extracción, adaptación nativa, robustez y comprobación visual. No se invocaron Apple Design, Taste ni Emil, ni se delegó trabajo a otros agentes en esta fase.

## Estado comprobado antes de implementar

Los tres pilotos de Fase 2B **sí estaban implementados** en el código de entrada: descubrimiento y fichas, perfil propio/público y chats/conversaciones. Se comprobaron sus composiciones y los usos reales de `AttraContentFrame`, `AttraPromptNote`, `AttraPhotoNote` y la navegación adaptativa. Se consultó el informe de Fase 2B como contexto del trabajo existente.

El repositorio ya tenía cambios sin confirmar de fases anteriores, fuentes, pruebas y archivos del usuario. Se conservaron. El inventario de este informe diferencia los cambios de esta fase del diff acumulado del repositorio; no atribuye a Fase 2C los pilotos ni los tokens creados anteriormente.

## Criterios de Impeccable aplicados

| Instrucción cargada | Aplicación en Flutter |
| --- | --- |
| [Polish](../../.agents/skills/impeccable/reference/polish.md) | Alineación de texto y controles, jerarquías más contenidas, espacios consistentes y eliminación de halos, sombras y bordes decorativos. |
| [Extract](../../.agents/skills/impeccable/reference/extract.md) | Etiquetas tonales, cuadrículas de altura determinada por el contenido y reutilización de marcos, superficies y cabeceras existentes. |
| [Adaptación nativa](../../.agents/skills/impeccable/reference/adapt.native.md), [iOS](../../.agents/skills/impeccable/reference/ios.md), [Android](../../.agents/skills/impeccable/reference/android.md) | Controles Flutter, áreas seguras, objetivos táctiles, columna de lectura y navegación lateral en Android ancho. Se conserva Cupertino en iOS. |
| [Harden](../../.agents/skills/impeccable/reference/harden.md) | Texto ampliado, contenido que envuelve, formularios y teclado PIN desplazables, estados de error legibles y semántica de los controles. |
| [Craft floor](../../.agents/skills/impeccable/reference/craft-floor.md) | Revisión agrupada de renders, ajustes derivados de esa revisión y una comprobación final. Contraste y movimiento reducido conservados; ninguna animación nueva de adorno. |

Las instrucciones web se adaptaron a widgets, temas y pruebas de Flutter. No se generaron HTML, CSS ni React. El contexto y los renders no se presentaron como una puntuación automática de calidad.

## Sistema visual consolidado

- Se mantienen carbón `#111111`, grafito `#1D1D1D`, superficie elevada `#2A2A2A`, plata como identidad y champagne para distinciones concretas. No se reemplaza la dirección aprobada.
- `ColorScheme` resuelve las superficies de contenedores y el texto secundario con los tokens existentes. Pestañas, menús, chips, diálogos y hojas comparten la misma jerarquía tonal.
- Se conserva Manrope editorial y la fuente de plataforma para lectura y controles. Los chips heredan ahora explícitamente la tipografía del tema.
- `AttraAdaptiveGrid` sustituye geometrías rígidas en Connection Lab, IA visual y saldos de cartera. El número de columnas responde al ancho y al tamaño de lectura; la altura depende del contenido.
- `AttraLabel` unifica metadatos y distintivos de Lab, planes, membresía y conexiones. El porcentaje de compatibilidad deja de depender de un subtítulo de 7,5–8 puntos.
- `AttraCard`, los botones comunes y el fondo compartido utilizan superficies planas. Se conserva la API de los parámetros históricos de gradiente para mantener sus consumidores, representándolos mediante color plano.
- `AttraContentFrame`, `AttraSectionHeading` y `AttraEmptyState` se reutilizan para lectura, cabeceras y estados. Las hojas usan el tirador del componente Flutter, evitando dibujarlo dos veces.
- Los loaders mantienen sus controladores y su respuesta a movimiento reducido; se eliminan sus halos. Los velos que hacen legible el contenido sobre fotografías/vídeo y los desenfoques de privacidad se conservan.

## Pantallas y módulos intervenidos

| Área | Resultado |
| --- | --- |
| Descubrimiento y fichas | Se conserva la composición fotográfica de Fase 2B y todos sus controles. El estado final del feed pierde el halo decorativo; cabeceras y superficies reciben el tema compartido. |
| Perfil propio y público | Se mantienen fotografía, respuestas y biografía como estructura principal. Se refinan editores, presentación audiovisual y etiquetas mediante los componentes comunes. El botón de audio tiene control nativo, nombre accesible y área mínima de 48 puntos. |
| Chats y conversaciones | Se conserva la composición del piloto. Las propuestas de cita y el bloque de juegos/IA usan superficies discretas. En grupos se unifican burbujas, compositor, columna de lectura y botón de envío con tooltip. |
| Acceso y autenticación | Paneles de teléfono/SMS oscuros, título editorial contenido, composición centrada y botones de altura flexible. Se mantienen los avisos, las validaciones y el requisito de aceptación del EULA. |
| Onboarding manual/voz y tutoriales | Progreso tonal, selección legible, selfie sin halo y marcos de lectura coherentes. Las opciones conservan selección anunciada y objetivos de 48 puntos. Se mantiene el recorrido y sus acciones. |
| Likes, Attras y matches | Foto separada de nombre, distintivos y comentario; metadatos sobre grafito. La cuadrícula pasa a una columna con texto grande o ancho reducido. Se mantienen tarjetas bloqueadas, condiciones de revelado, orden, acciones y comentarios existentes. Se retira el resplandor decorativo del diálogo de match. |
| Historias y descubrimiento a ciegas | Pila de historias sin sombra ornamental y controles que heredan el sistema común. Se conservan scrims, medios, contadores, temporizadores y capas de revelado. Los visores inmersivos no se reconstruyeron. |
| Filtros y viajes | Metadatos legibles, superficies tonales y composición de hojas coherente; mismos campos, gates y acciones. |
| Configuración | Columna de lectura, cabecera de jerarquía editorial, filas nativas agrupadas, iconos contenidos y distintivos comunes. Se mantienen destinos, preferencias y condiciones. |
| Plus, Pro y cartera | Selector de periodo con selección inequívoca; tarjetas sin degradados ni marcos dorados extensos. Champagne puntual en la distinción. Paywall limitado al ancho de lectura en tableta y saldos adaptables. Se conservan precios de tienda, ofertas, derechos, consumos y callbacks de compra/restauración. |
| IA visual | Cabecera sobria, secciones sin numeración ornamental, búsqueda próxima a la referencia y cuadrícula flexible de capacidades. Permanecen consentimiento, revocación, errores, condiciones de acceso y solicitudes existentes. |
| Spark, juegos y Connection Lab | Menos cajas anidadas, fichas abiertas de contenido, iconos discretos, lectura adaptable y acciones nativas. Se conservan los seis destinos de Lab y las acciones de los juegos. |
| Live | Cámara con objetivo de 48 puntos y tooltip; avisos de error y cuenta atrás legibles. Sin cambios de reloj, umbrales, RTC, moderación ni decisiones. |
| SafeDate | Columna de lectura, metadatos y superficies coherentes en inicio, plan, contactos, check-ins, lugares, comprobaciones y reseña. Sin cambios de operaciones de seguridad. |
| Grupos y amistad | Superficies neutras, cabeceras de reserva sin gradientes y chat adaptativo; se conservan fotografías, modos, pertenencia y permisos. |
| Notificaciones | Estado de error explícito, estado vacío común, texto que envuelve y respuesta visual al toque. Se conserva marcar, borrar y abrir la ruta correspondiente. |
| PIN, bloqueo y biometría | Teclado desplazable en ventanas bajas, nombres accesibles de dígitos/borrado/biometría y anuncio de cantidad de dígitos introducidos sin exponer el PIN. Mismos verificadores y callbacks. |
| Navegación | Mismos cuatro destinos y mismo despacho. Barra inferior nativa en compacto/iOS; rail en Android desde 840 puntos. Durante el tutorial se conserva la barra inferior a la que apunta su indicación visual. |

La extensión combina cambios locales y herencia de tema/componentes. No significa que todos los visores inmersivos o cada subestado de una función se hayan recompuesto individualmente.

## Límites funcionales respetados

No se modificaron archivos de servicios, repositorios, dominio, Firebase, reglas, funciones de servidor ni contratos de backend en esta fase. `pubspec.yaml` permanece idéntico al estado de entrada: no hay nuevas dependencias de aplicación.

No se cambiaron los umbrales ni callbacks de swipes, reglas de likes/Attras/matches, precios, catálogo, derechos heredados, visibilidad, revelado ni reglas de seguridad. Se contrastaron los métodos de estado y acción previos al `build` de IA visual, paywall y feed con su estado de entrada; permanecen idénticos. El acceso cambia sus constantes visuales y su representación, conservando los métodos de validación y autenticación. Las pruebas existentes de gates, privacidad, viajes, consumibles, suscripciones, revelado y swipes siguen pasando.

No se encontró una mejora visual que obligara a modificar negocio. No se realizaron push, despliegues ni operaciones sobre cuentas reales. No se inició la fase de animaciones de Emil. Los cambios de movimiento se limitan a respetar la preferencia de movimiento reducido en transiciones existentes.

## Pruebas y comprobaciones

| Comprobación | Resultado |
| --- | --- |
| `flutter analyze --no-pub` | Sin incidencias. |
| `flutter test --no-pub --reporter expanded --dart-define=ATTRA_REVIEW_OUTPUT=docs/design/phase2c/evidence/after` | **1.221 pruebas superadas**, sin fallos, incluyendo toda la suite existente. |
| `git diff --check` | Sin errores de whitespace. |
| Fuente de dependencias | `pubspec.yaml` idéntico al de entrada de Fase 2C. |

Pruebas añadidas: 12 renders de seis pantallas en dos tamaños, cinco casos de componentes/accesibilidad y dos casos de conexiones con texto al 200 %. Se comprueban etiquetas largas, saldos extensos, modo claro/oscuro, selección semántica, área táctil, callbacks únicos, navegación lateral y entrada del mismo PIN en una ventana de 320 × 360. En conexiones se comprueban 320 y 390 puntos con texto al 200 % sin desbordamiento. No se debilitaron las expectativas existentes.

La primera ejecución completa encontró imports ausentes y usos inválidos de `const` en los últimos ajustes. Se corrigieron y la suite completa volvió a ejecutarse. El paywall usa una tienda falsa solamente en las pruebas visuales; no se hicieron compras ni se inventaron precios.

Los registros resumidos están en [validation.txt](phase2c/validation.txt).

## Evidencia visual y límites

Se generaron 12 PNG anteriores y 12 posteriores con el **motor de widgets de Flutter**, fuentes locales y fixtures, a 390 × 844 y 1024 × 768. Son renders de las pantallas reales, no mockups generados. No son capturas de un dispositivo Android/iOS ni una ejecución autenticada contra Firebase.

Se inspeccionaron comparativamente acceso, Connection Lab y paywall en móvil; también tutorial, reto, perfil público y vistas de tableta. La última comprobación confirmó el acceso reequilibrado, los intereses renderizados con la fuente del tema y el paywall acotado en tableta.

| Pantalla | Antes | Después |
| --- | --- | --- |
| Acceso, móvil | [PNG](phase2c/evidence/before/login-phone.png) | [PNG](phase2c/evidence/after/login-phone.png) |
| Connection Lab, móvil | [PNG](phase2c/evidence/before/connection-lab-phone.png) | [PNG](phase2c/evidence/after/connection-lab-phone.png) |
| Tutorial, móvil | [PNG](phase2c/evidence/before/tutorial-phone.png) | [PNG](phase2c/evidence/after/tutorial-phone.png) |
| Connection Lab, tableta | [PNG](phase2c/evidence/before/connection-lab-tablet.png) | [PNG](phase2c/evidence/after/connection-lab-tablet.png) |
| Paywall, tableta | Referencia anterior con limitación de tienda descrita abajo | [PNG](phase2c/evidence/after/plans-tablet.png) |
| Perfil público, móvil | Referencia tipográfica limitada por el entorno de pruebas | [PNG](phase2c/evidence/after/public-profile-phone.png) |

Las referencias anteriores del paywall se pintaron durante una ejecución que encontró un canal de compras nativo no disponible. Se conservan como referencia de composición, pero no acreditan equivalencia de estado de tienda: la visibilidad de «Restaurar» difiere por el fixture. La tienda falsa aisló el problema y todas las pruebas finales pasan. Los precios posteriores se muestran como no disponibles porque no hay productos cargados. No se interpreta esa diferencia como un cambio de lógica de compra.

El fixture de perfil público no contiene fotografías: esa captura acredita jerarquía de texto y etiquetas, no encuadre fotográfico. El motor de pruebas utilizó inicialmente Ahem para ciertos chips sin familia explícita; el tema ahora declara su tipografía. No se atribuye la aparición de esos bloques de prueba a un fallo observado en dispositivos.

El vídeo de acceso utiliza el fallback estático porque el plugin de vídeo no está implementado en el runner. La reproducción real no se ha validado aquí. No hay dispositivos ADB conectados y falta el ejecutable de emulador Android; no se generaron capturas nativas. La fuente Roboto de `test/visual/fonts`, con licencia OFL incluida, se usa exclusivamente para estas pruebas; no se añadió a los assets de producción.

## Pendientes y riesgos de regresión

- Validación manual en dispositivos iOS y Android: VoiceOver/TalkBack, tipografía de sistema, teclado real, áreas seguras, navegación y texto grande.
- Comprobar con sesiones reales todos los subestados de fotos/historias, comentarios extensos, conversación con medios, IA, Live, SafeDate y biometría. La suite de widgets no sustituye esa revisión visual.
- Verificar vídeo, cámara, micrófono y pagos nativos con sus plugins y productos reales. Los servicios no se modificaron, pero su presentación no queda acreditada por los fixtures.
- La adopción del tema y componentes afecta 71 archivos de implementación: el riesgo principal es de composición en estados poco frecuentes y de densidad con datos reales. Los gates y la suite existente siguen pasando, pero esto no garantiza ausencia de regresiones visuales en cada combinación.
- La cuadrícula de conexiones reserva altura para metadatos y comentario; las fichas siguen truncando ciertos textos de resumen y permiten abrir el detalle mediante la acción existente. Revisar con perfiles reales especialmente extensos.

## Archivos afectados

Inventario completo de esta fase: **71 archivos Dart de implementación y 3 de pruebas**, más las fuentes de prueba, este informe, registros e imágenes. Se puede consultar de forma estructurada en [changed-files.json](phase2c/changed-files.json). Los archivos ya modificados antes de Fase 2C y que esta fase no tocó no se incluyen.

| M?dulo | Archivos |
| --- | --- |
| ai_visual | [ai_visual_screen.dart](../../lib/src/features/ai_visual/presentation/ai_visual_screen.dart) |
| anti_ghosting | [anti_ghosting_nudge_card.dart](../../lib/src/features/anti_ghosting/presentation/anti_ghosting_nudge_card.dart), [busy_mode_sheet.dart](../../lib/src/features/anti_ghosting/presentation/busy_mode_sheet.dart), [close_conversation_sheet.dart](../../lib/src/features/anti_ghosting/presentation/close_conversation_sheet.dart), [date_follow_up_sheet.dart](../../lib/src/features/anti_ghosting/presentation/date_follow_up_sheet.dart), [pending_limit_sheet.dart](../../lib/src/features/anti_ghosting/presentation/pending_limit_sheet.dart), [reliability_badge.dart](../../lib/src/features/anti_ghosting/presentation/reliability_badge.dart) |
| auth | [login_screen.dart](../../lib/src/features/auth/presentation/login_screen.dart), [login_video_background.dart](../../lib/src/features/auth/presentation/login_video_background.dart) |
| chat | [chat_detail_screen.dart](../../lib/src/features/chat/presentation/chat_detail_screen.dart), [date_proposal_sheet.dart](../../lib/src/features/chat/presentation/date_proposal_sheet.dart) |
| connection_lab | [ai_compatibility_screen.dart](../../lib/src/features/connection_lab/presentation/ai_compatibility_screen.dart), [anti_ghosting_coach_screen.dart](../../lib/src/features/connection_lab/presentation/anti_ghosting_coach_screen.dart), [chat_ai_challenge_card.dart](../../lib/src/features/connection_lab/presentation/chat_ai_challenge_card.dart), [connection_lab_screen.dart](../../lib/src/features/connection_lab/presentation/connection_lab_screen.dart), [conversation_games_screen.dart](../../lib/src/features/connection_lab/presentation/conversation_games_screen.dart), [date_planner_screen.dart](../../lib/src/features/connection_lab/presentation/date_planner_screen.dart), [demo_challenge_screen.dart](../../lib/src/features/connection_lab/presentation/demo_challenge_screen.dart), [lab_widgets.dart](../../lib/src/features/connection_lab/presentation/lab_widgets.dart) |
| date_plans | [date_plan_proposal_sheet.dart](../../lib/src/features/date_plans/presentation/date_plan_proposal_sheet.dart), [date_plans_strip.dart](../../lib/src/features/date_plans/presentation/date_plans_strip.dart), [plan_preferences_sheet.dart](../../lib/src/features/date_plans/presentation/plan_preferences_sheet.dart) |
| feed | [feed_screen.dart](../../lib/src/features/feed/presentation/feed_screen.dart), [filters_screen.dart](../../lib/src/features/feed/presentation/filters_screen.dart), [quick_filter_sheet.dart](../../lib/src/features/feed/presentation/quick_filter_sheet.dart), [travel_sheet.dart](../../lib/src/features/feed/presentation/travel_sheet.dart) |
| home | [home_landing_screen.dart](../../lib/src/features/home/presentation/home_landing_screen.dart), [home_shell.dart](../../lib/src/features/home/presentation/home_shell.dart) |
| live | [live_screen.dart](../../lib/src/features/live/presentation/live_screen.dart) |
| match | [date_builder_sheet.dart](../../lib/src/features/match/presentation/date_builder_sheet.dart), [icebreaker_sheet.dart](../../lib/src/features/match/presentation/icebreaker_sheet.dart), [likes_received_screen.dart](../../lib/src/features/match/presentation/likes_received_screen.dart), [match_created_dialog.dart](../../lib/src/features/match/presentation/match_created_dialog.dart) |
| monetization | [boost_store_sheet.dart](../../lib/src/features/monetization/presentation/boost_store_sheet.dart), [paywall_screen.dart](../../lib/src/features/monetization/presentation/paywall_screen.dart) |
| notifications | [notifications_screen.dart](../../lib/src/features/notifications/presentation/notifications_screen.dart) |
| onboarding | [interested_in_picker.dart](../../lib/src/features/onboarding/presentation/interested_in_picker.dart), [onboarding_screen.dart](../../lib/src/features/onboarding/presentation/onboarding_screen.dart), [voice_profile_setup.dart](../../lib/src/features/onboarding/presentation/voice_profile_setup.dart) |
| profile | [edit_traits_screen.dart](../../lib/src/features/profile/presentation/edit_traits_screen.dart), [interested_in_sheet.dart](../../lib/src/features/profile/presentation/interested_in_sheet.dart), [intro_media_editor.dart](../../lib/src/features/profile/presentation/intro_media_editor.dart), [intro_media_view.dart](../../lib/src/features/profile/presentation/intro_media_view.dart) |
| safedate | [active_date_screen.dart](../../lib/src/features/safedate/presentation/active_date_screen.dart), [checkins_section.dart](../../lib/src/features/safedate/presentation/checkins_section.dart), [create_plan_sheet.dart](../../lib/src/features/safedate/presentation/create_plan_sheet.dart), [post_date_review_sheet.dart](../../lib/src/features/safedate/presentation/post_date_review_sheet.dart), [safe_places_screen.dart](../../lib/src/features/safedate/presentation/safe_places_screen.dart), [safedate_home_screen.dart](../../lib/src/features/safedate/presentation/safedate_home_screen.dart), [safety_check_sheet.dart](../../lib/src/features/safedate/presentation/safety_check_sheet.dart), [trusted_contacts_screen.dart](../../lib/src/features/safedate/presentation/trusted_contacts_screen.dart) |
| security | [lock_screen.dart](../../lib/src/features/security/presentation/lock_screen.dart), [pin_pad.dart](../../lib/src/features/security/presentation/pin_pad.dart) |
| settings | [settings_screen.dart](../../lib/src/features/settings/presentation/settings_screen.dart), [settings_section_screen.dart](../../lib/src/features/settings/presentation/settings_section_screen.dart) |
| social | [group_chat_screen.dart](../../lib/src/features/social/presentation/group_chat_screen.dart), [groups_screen.dart](../../lib/src/features/social/presentation/groups_screen.dart), [intent_mode_selector.dart](../../lib/src/features/social/presentation/intent_mode_selector.dart) |
| spark | [spark_game_screen.dart](../../lib/src/features/spark/presentation/spark_game_screen.dart), [spark_summary_sheet.dart](../../lib/src/features/spark/presentation/spark_summary_sheet.dart) |
| stories | [story_stack_card.dart](../../lib/src/features/stories/presentation/story_stack_card.dart) |
| tutorial | [tutorial_screen.dart](../../lib/src/features/tutorial/presentation/tutorial_screen.dart) |
| theme | [app_theme.dart](../../lib/src/theme/app_theme.dart) |
| widgets | [attra_backgrounds.dart](../../lib/src/widgets/attra_backgrounds.dart), [attra_badges.dart](../../lib/src/widgets/attra_badges.dart), [attra_buttons.dart](../../lib/src/widgets/attra_buttons.dart), [attra_destination_bar.dart](../../lib/src/widgets/attra_destination_bar.dart), [attra_editorial.dart](../../lib/src/widgets/attra_editorial.dart), [attra_image.dart](../../lib/src/widgets/attra_image.dart), [attra_loader.dart](../../lib/src/widgets/attra_loader.dart), [attra_states.dart](../../lib/src/widgets/attra_states.dart) |
| Prueba | [likes_gate_test.dart](../../test/src/features/match/likes_gate_test.dart) |
| Prueba | [attra_refinement_test.dart](../../test/src/widgets/attra_refinement_test.dart) |
| Prueba | [phase2c_surfaces_test.dart](../../test/visual/phase2c_surfaces_test.dart) |

