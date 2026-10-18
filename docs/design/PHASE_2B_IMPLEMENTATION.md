# Attra · Fase 2B

Implementación Flutter de los tres pilotos de la dirección aprobada «Nota fotográfica». Fecha: 16 de octubre de 2026.

Se verificó y leyó completo [Apple Design Skill](../../.agents/skills/apple-design/SKILL.md). Fue la única skill utilizada en esta fase. La propuesta anterior de Taste se utilizó como referencia aprobada; no se volvió a invocar Taste ni ninguna otra skill.

## Criterios aplicados

- [Layout · Visual hierarchy](../../.agents/skills/apple-design/references/hig/layout.md): «Order content by relative importance.» Fotos, identidad y respuestas preceden a servicios y promociones; los bloques se agrupan con espacio.
- [Accessibility · Vision](../../.agents/skills/apple-design/references/hig/accessibility.md): «Support larger text sizes.» Casos de 320 dp y texto al 200%, contraste medido de los tokens y conservación de etiquetas, errores y movimiento reducido de Fase 1.
- [Typography](../../.agents/skills/apple-design/references/hig/typography.md): Manrope local para títulos de contenido; fuente de plataforma para cuerpo y controles. Escala principal 32/24/17/15/13.
- [Buttons · Best practices](../../.agents/skills/apple-design/references/hig/buttons.md): «Always include a press state for a custom button.» Botones Flutter con estados de foco, pulsación y deshabilitado; áreas de al menos 48 dp en controles intervenidos.
- [Tab bars · Best practices](../../.agents/skills/apple-design/references/hig/tab-bars.md): navegación principal siempre visible. `CupertinoTabBar` en iOS y `NavigationBar` Material 3 en Android, mismos destinos y selección. La barra iOS limita su texto como `CupertinoTabScaffold`; el contenido conserva el escalado del sistema.
- [Cross-platform](../../.agents/skills/apple-design/references/cross-platform.md), [Dark Mode](../../.agents/skills/apple-design/references/hig/dark-mode.md), [Color](../../.agents/skills/apple-design/references/hig/color.md), [Sheets](../../.agents/skills/apple-design/references/hig/sheets.md) y [Lists and tables](../../.agents/skills/apple-design/references/hig/lists-and-tables.md): colores adaptativos, áreas seguras, lectura acotada a 680 dp, hojas desplazables y controles familiares. Sin simular cristal ni añadir animaciones decorativas.

La geometría de fotos y notas, los radios 20/28 y las superficies planas son decisiones de dirección visual de Attra, no requisitos atribuidos a Apple.

## Resultado

- Descubrimiento: fotos 3:4, nombre y datos fuera de la imagen, respuestas abiertas, controles conservados, hojas de respuesta adaptables al teclado. Se conserva el umbral de gesto y el reloj de 260 ms.
- Perfil propio: identidad y foto principal, galería, respuestas y presentación audiovisual antes de los servicios. Completitud y todas sus tareas en un solo bloque. Servicios en filas agrupadas, con los mismos destinos y condiciones.
- Perfil público: fotografía y respuestas con la misma jerarquía y geometría; mismos datos, orden y acciones de seguridad.
- Chats: nombres y mensajes prioritarios, acceso a juegos conservado, contexto de foto y comentario como una nota, compositor tonal con entrada amplia. Cabeceras opcionales desplazables según el espacio real disponible.
- Componentes comunes: superficies sin sombras decorativas, botones flexibles, marco de lectura, encabezados y notas reutilizables. Fuente Manrope de Google Fonts incluida con SIL OFL.
- Compatibilidad: corregido el botón de referencia de IA que desbordaba con la nueva tipografía, mediante `OutlinedButton.icon`; sin cambios en consentimiento ni operaciones de IA.

No se modificaron servicios de Firebase, contratos, modelos, reglas de matching, derechos de suscripción, límites de swipes, likes o Attras ni restricciones de revelado. No se realizaron despliegues. Los cambios previos del repositorio se conservaron.

## Archivos de implementación

| Área | Archivos |
| --- | --- |
| Tokens | [app_theme.dart](../../lib/src/theme/app_theme.dart), [attra_colors.dart](../../lib/src/theme/attra_colors.dart), [app_spacing.dart](../../lib/src/theme/app_spacing.dart) |
| Componentes | [attra_editorial.dart](../../lib/src/widgets/attra_editorial.dart), [attra_destination_bar.dart](../../lib/src/widgets/attra_destination_bar.dart), [attra_backgrounds.dart](../../lib/src/widgets/attra_backgrounds.dart), [attra_buttons.dart](../../lib/src/widgets/attra_buttons.dart) |
| Navegación | [home_shell.dart](../../lib/src/features/home/presentation/home_shell.dart) |
| Descubrimiento | [feed_screen.dart](../../lib/src/features/feed/presentation/feed_screen.dart), [photo_response_sheet.dart](../../lib/src/features/match/presentation/photo_response_sheet.dart) |
| Perfil | [home_screen.dart](../../lib/src/features/home/presentation/home_screen.dart), [profile_view_screen.dart](../../lib/src/features/profile/presentation/profile_view_screen.dart), [profile_strength_card.dart](../../lib/src/features/profile/presentation/profile_strength_card.dart), [intro_media_editor.dart](../../lib/src/features/profile/presentation/intro_media_editor.dart) |
| Chats | [chats_screen.dart](../../lib/src/features/chat/presentation/chats_screen.dart), [chat_detail_screen.dart](../../lib/src/features/chat/presentation/chat_detail_screen.dart), [voice_note_bubble.dart](../../lib/src/features/chat/presentation/voice_note_bubble.dart) |
| Compatibilidad de IA | [ai_visual_screen.dart](../../lib/src/features/ai_visual/presentation/ai_visual_screen.dart) |
| Fuente y licencia | [pubspec.yaml](../../pubspec.yaml), [Manrope-Variable.ttf](../../assets/fonts/manrope/Manrope-Variable.ttf), [OFL.txt](../../assets/fonts/manrope/OFL.txt) |

## Pruebas

Se añadieron seis archivos de pruebas:

- [feed_editorial_profile_test.dart](../../test/src/features/feed/presentation/feed_editorial_profile_test.dart)
- [photo_response_editorial_test.dart](../../test/src/features/match/photo_response_editorial_test.dart)
- [profile_editorial_test.dart](../../test/src/features/profile/presentation/profile_editorial_test.dart)
- [chat_editorial_layout_test.dart](../../test/src/features/chat/presentation/chat_editorial_layout_test.dart)
- [attra_editorial_test.dart](../../test/src/widgets/attra_editorial_test.dart)
- [attra_destination_bar_test.dart](../../test/src/widgets/attra_destination_bar_test.dart)

Se adaptaron cinco archivos existentes:

- [app_theme_palette_test.dart](../../test/src/theme/app_theme_palette_test.dart): contraste de texto y acciones en ambos temas.
- [attra_backgrounds_test.dart](../../test/src/widgets/attra_backgrounds_test.dart): fondo continuo y contraste.
- [feed_rewind_test.dart](../../test/src/features/feed/presentation/feed_rewind_test.dart): desplazamiento hasta prompts virtualizados, con las mismas aserciones de límites y marcha atrás.
- [onboarding_age_gate_test.dart](../../test/src/features/onboarding/presentation/onboarding_age_gate_test.dart): desplazar hasta confirmar antes de pulsar, conservando la comprobación de edad y persistencia.
- [paywall_screen_test.dart](../../test/src/features/monetization/presentation/paywall_screen_test.dart): desplazar hasta renovación anual, conservando selección, precio y duración.

Las pruebas cubren ambos temas, objetivos táctiles, navegación iOS/Android, texto al 200%, teclado de 240 dp, recuperación de errores, fotos eliminadas, comentarios y sus destinos, callbacks del perfil y herramientas del chat.

Validación final sobre el código entregado:

- `flutter analyze --no-pub`: sin incidencias (47,2 s).
- `flutter test --no-pub --reporter expanded`: **1202 pruebas superadas** (61 s), 24 casos más que la suite de Fase 1.
- `git diff --check`: sin errores.

## Límites de validación y riesgos pendientes

- No se generaron capturas nativas ni comparativas antes/después. Las pruebas de widgets no se presentan como una validación visual en dispositivo.
- Pendiente comprobar en iOS y Android los recortes de fotografías reales, métricas de fuente, teclado y navegación con VoiceOver/TalkBack.
- Los tokens compartidos alcanzan pantallas secundarias. Se ejecutó la suite completa para comprobar regresiones; su revisión visual completa queda fuera de estos tres pilotos.
- Las cabeceras opcionales del chat y las herramientas de IA se desplazan dentro de su área; conviene comprobar su uso con contenido real y lectores de pantalla.
