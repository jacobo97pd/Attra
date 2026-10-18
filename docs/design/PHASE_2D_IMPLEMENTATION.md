# Attra · Fase 2D

Implementación de movimiento y microinteracciones en Flutter. 18 de octubre de 2026.

## Skill y estado de entrada

Se verificó la instalación y se leyó completo [Emil Design Engineering](../../.agents/skills/emil-design-eng/SKILL.md). Fue la única skill utilizada. Esta instalación contiene un único `SKILL.md`, sin archivos adicionales de referencias. Se consultó también [Easings.co](https://easings.co/), uno de los recursos enlazados por la skill; `easing.dev` no fue accesible desde la herramienta. Los coeficientes de las curvas proceden del propio `SKILL.md`, sin inventar curvas ni sustituir la skill por otra.

Se comprobaron el código real, el estado de Git y los informes anteriores. Los tres pilotos de Fase 2B estaban presentes y el refinamiento de Fase 2C estaba implementado. Se tomó una copia completa de `lib`, `test` y los manifiestos de dependencias antes de editar, incluyendo los cambios que ya estaban sin confirmar.

Se conserva «Nota fotográfica»: los archivos de tema, colores, espaciados y tipografía son idénticos a los del comienzo de esta fase. Las imágenes de referencia del usuario se interpretaron como referencias de calidad de interacción; no se sustituyó la dirección visual por sus efectos de cristal o iluminación.

## Criterios aplicados

- Decidir primero si una interacción debe animarse: los mensajes, los precios y los saldos se actualizan inmediatamente. Las transiciones comunican activación, cambio de estado o continuidad espacial.
- Usar desplazamientos pequeños y curvas de salida rápidas. La curva principal es `Cubic(0.23, 1, 0.32, 1)`, proporcionada por la skill. Se conservan las curvas existentes donde ya cumplen su función.
- Conservar los relojes funcionales y no enlazar operaciones de servicio a la finalización de una animación nueva.
- Retargetear las pulsaciones desde su valor actual y evitar reiniciar una transición de estado que ya está terminando.
- Mostrar únicamente el contenido vigente en las transiciones de estado nuevas. Las reconstrucciones con la misma identidad no vuelven a animarse.
- Mantener la activación por teclado inmediata. El feedback de pulsación añadido se activa exclusivamente por puntero; no envuelve ni retrasa callbacks.
- Utilizar herramientas nativas de Flutter y adaptar los principios de rendimiento de la skill al motor de Flutter. No se presume que sus afirmaciones web sobre GPU o hilos equivalgan a mediciones de esta aplicación.

## Cambios implementados

| Before | After | Why |
| --- | --- | --- |
| El desplazamiento del swipe hacía `setState` sobre la ficha completa en cada actualización. | `AnimatedBuilder` escucha el controlador existente y las revisiones del arrastre, conservando el cuerpo de la ficha en su argumento `child`. | Aislar giro, desplazamiento, sellos y controles del contenido fotográfico y las respuestas. |
| El siguiente perfil sustituía directamente el contenido. | Continuidad de 160 ms, desplazamiento vertical de 0,8 % de su altura y contenido visible desde el primer frame. Solo se activa al cambiar la identidad del perfil. | Orientar al usuario sin retener una ficha anterior ni demorar la siguiente acción. |
| La transición global de match podía transparentar los controles de la pantalla anterior sobre el vínculo. | Fondo que se establece durante el primer cuarto de la misma transición de ruta. | Mantener el foco en las personas; se conservan los 200/140 ms de la ruta. |
| Las dos fotografías del match se movían como un único bloque. | Acercamiento independiente desde ±14 puntos mediante la animación de ruta existente. | Expresar el vínculo sin partículas, confeti, rebotes ni otro controlador. |
| Botones comunes y acciones de foto dependían únicamente de su feedback nativo. | Escala de pulsación de 0,98, 100 ms al presionar y 140 ms al liberar, conservando el feedback nativo. | Confirmar el contacto sin demorar la acción ni reducir el área táctil. |
| La apertura de una imagen ordinaria del chat cambiaba de vista sin una referencia espacial propia. | `Hero` con identidad por chat y mensaje, desactivado con movimiento reducido. | Conectar miniatura y visor; una URL repetida no produce tags duplicados. |
| Los estados de IA visual y la barra de Spark cambiaban directamente. | Transición breve del contenido vigente, 180 y 160 ms respectivamente. | Explicar cambios reales, manteniendo texto, estado y CTA actualizados inmediatamente. |
| El pulso de voz se repetía también en el briefing y al revisar el borrador. | Solo se ejecuta durante grabación/procesamiento, en primer plano, con tickers habilitados y sin movimiento reducido. | Eliminar actividad visual que no comunica un proceso en curso. |
| Cada una de las nueve barras de voz creaba un `AnimatedContainer` que cambiaba de altura durante el pulso. | Geometría fija y `Transform.scale`; el halo también se escala con tamaño fijo. | Evitar nueve interpolaciones implícitas de layout y cambios de dimensiones por frame. |
| La entrada adicional del formulario duraba 360 ms y recorría 16 puntos. | Entrada de 180 ms y 8 puntos; el cambio de página habitual conserva sus 240 ms. | Evitar una segunda entrada larga sobre la navegación del paso. |
| Varias cabeceras, progresos y cambios de formulario ignoraban la preferencia de movimiento reducido. | Duración cero para sus transiciones visuales; navegación de páginas mediante `jumpToPage` en ese modo. | Mantener la aplicación funcional sin desplazamientos o controladores cosméticos innecesarios. |
| Los controles y etiquetas de vistas salientes seguían presentes durante un `AnimatedSwitcher`. | Las vistas salientes se excluyen de hit testing y semántica. | Conservar la transición existente sin duplicar acciones accesibles. |

## Componentes reutilizables

[attra_motion.dart](../../lib/src/widgets/attra_motion.dart) reúne las herramientas de presentación:

- `AttraPressFeedback`: observa puntero primario, liberación y cancelación. El botón nativo conserva su callback, foco, semántica y objetivo táctil. `transformHitTests: false` mantiene su geometría interactiva original. Las activaciones por teclado no producen escala.
- `AttraStateTransition`: entrada inicial inmediata, animación únicamente al cambiar `value`, conservación del contenido actual y finalización sin volver al inicio si otro cambio llega durante la transición. Se detiene al solicitar movimiento reducido o desactivar `TickerMode`; no se reproduce al reactivarlo.
- `AttraMotion.durationOf` y `pageTo`: tratamiento de movimiento reducido para transiciones visuales y páginas. `pageTo` utiliza la API estática de scroll cuando corresponde, evitando enviar una duración cero a `animateToPage`.
- `AttraMotion.switcherLayout`: conserva la presentación saliente de los switchers existentes, excluyendo sus controles y etiquetas accesibles.

No hay un temporizador global de animaciones ni una duración universal. No se añadió ninguna dependencia.

## Aplicación por módulo

| Módulo | Implementación y decisiones conservadas |
| --- | --- |
| Descubrimiento | Movimiento aislado del cuerpo, continuidad al cambiar perfil y pulsación de acciones de like/Attra sobre fotos. Los gestos siguen respondiendo directamente al dedo, sin spring ni interpolación adicional entre dedo y tarjeta. Cabecera y plegado respetan movimiento reducido. |
| Matches y Attras | Convergencia de fotografías y fondo de transición más limpio, usando la ruta existente. El mensaje, las acciones de chat/Spark y el distintivo de Attra mantienen su contenido y condiciones. Los CTA no esperan otra animación para funcionar. |
| Chat | Pulsaciones en composer y reproducción de voz; continuidad espacial de imágenes ordinarias. Los mensajes y el envío optimista se mantienen instantáneos. No se introdujo una entrada por mensaje ni un efecto que se repita con los streams. |
| Teclado y audio | Se mantiene el comportamiento nativo de teclado, foco y resize. No se añade otra interpolación de insets. Play/pausa y la barra de grabación conservan el estado real de sus servicios. |
| Autenticación | Mismo cambio de etapa y misma transición normal; salientes sin acciones duplicadas y cambio de sesión sin animación cuando el sistema lo solicita. Se conservan formulario, aceptación del EULA, validaciones y callbacks. |
| Onboarding | Entrada adicional más corta, progreso estático con movimiento reducido y páginas instantáneas en ese modo. Persistencia y validación preceden a la navegación igual que antes. El indicador de voz deja de animar estados inactivos. |
| Plus, Pro y cartera | Feedback en los botones comunes de compra/activación y en el selector mensual/anual. Se conserva la selección inmediata: no se interpolan precios, créditos, disponibilidad ni beneficios, y no se representa una compra como confirmada antes del servicio. |
| IA visual | Continuidad al cambiar el estado del panel de análisis. Las fotos, consentimiento, revocación, búsqueda, resultados y errores siguen dependiendo de los mismos valores y llamadas. No se simula progreso. |
| Connection Lab y Spark | Pulsación contenida en las fichas de Lab; transición de estados en la barra contextual de Spark sin repetir por snapshots equivalentes. Sus destinos, invitaciones, rondas, tiempos y respuestas permanecen iguales. |
| Historias y descubrimiento a ciegas | El arrastre visual y sus sellos permanecen estáticos al solicitar movimiento reducido; se conservan decisiones y relojes. El revelado posterior al match detiene el desenfoque en ese modo. No se añade un acceso al perfil ni una transición que mantenga material privado anterior. |
| SafeDate y propuestas | Se conservan las transiciones nativas de hojas y diálogos. No se añade una coreografía propia a decisiones de seguridad ni esperas a sus acciones. Los controles comunes reciben el mismo feedback donde ya se utilizan. |
| Notificaciones y actividad | Se mantienen la entrada y descarte nativos, estados de lectura y navegación. No se anima cada actualización de bandeja o actividad ni se añade una celebración de Attras recibidos que pudiera insinuar un revelado. |
| Tutorial y navegación | Se conservan rutas nativas, destinos y recorrido. Indicadores estáticos con movimiento reducido, y salto de página estático en el tutorial. |

La revisión incluyó conservar interacciones que ya estaban resueltas. No se modificó cada módulo para añadir movimiento cuando no aportaba información.

## Animaciones y tiempos conservados

| Interacción | Conservación |
| --- | --- |
| Swipe del feed | Umbral de 100, traducción proporcional al dedo, salida/retorno de 260 ms, curva existente y despacho al finalizar. `AnimationBehavior.preserve` sigue protegiendo ese reloj funcional. |
| Swipe del visor a ciegas | Duración existente de 240 ms, umbral, bloqueos, secuencia de cancelación y callbacks sin cambios. |
| Ruta de match | Entrada de 200 ms, salida de 140 ms, fade y escala global desde 0,94 con su curva existente. El acceso al chat sigue siendo inmediato al activar el CTA. |
| Páginas del onboarding/tutorial | 240/280 ms en modo habitual; API de salto en movimiento reducido. |
| Voz | Pulso de 1.500 ms conservado durante actividad real. No se cambian límites de grabación, temporizadores, permisos ni envío. |
| Loaders existentes | Se conservan logo, carga inline y skeletons con sus controles de accesibilidad de Fase 1. No se reinician sus ciclos por cambios de contenido ni se acelera artificialmente un servicio. |
| Rutas, hojas y diálogos | Se mantienen las herramientas y transiciones nativas existentes. No se impone una transición personalizada global. |

Los controladores que finalizan swipes conservan su reloj incluso cuando su desplazamiento visual se elimina. Detenerlos por motivos cosméticos alteraría el despacho de acciones. Los controladores puramente cosméticos nuevos sí se detienen y se colocan en su estado final.

## Eliminaciones y rendimiento

Se eliminaron el pulso de voz fuera de actividad, las nueve animaciones implícitas de altura de sus barras y la duración excesiva de la entrada adicional del formulario. El movimiento de posición de los elementos intervenidos se omite con movimiento reducido. No se añadieron partículas, springs, glow, blur decorativo ni movimiento de scroll por visibilidad.

El cuerpo del perfil se mantiene como el mismo widget durante el arrastre y el retorno. Una prueba comprueba su identidad antes y durante ambos recorridos; la mejora demostrada es de alcance de reconstrucción, no un número de FPS. Se sustituyó la creación de `CurvedAnimation` en los recorridos de swipe/match por `CurveTween` con la misma curva, evitando listeners de estado innecesarios.

No se añadieron `RepaintBoundary` de producción sin medición que lo justificara. Los utilizados para capturas existen únicamente en pruebas. No se midieron frame times, consumo de GPU, memoria ni rendimiento en dispositivos a 60/120 Hz.

## Restricciones verificadas

El diff de esta fase contiene **19 archivos de implementación de UI y 7 archivos de pruebas**. No modifica servicios, repositorios, modelos de dominio, Firebase, backend, reglas o contratos. `pubspec.yaml`, `pubspec.lock` y todos los archivos de `lib/src/theme` son idénticos al estado de entrada.

Se compararon mecánicamente los métodos de estado/acción previos al `build` de acceso, chat y paywall: permanecen iguales. También se compararon `triggerSwipe`, `_trySwipe`, `_passFromControl` y `_onDragEnd`: iguales. Los cambios de `_onDragUpdate` y del listener sustituyen la notificación de reconstrucción por una notificación de presentación, manteniendo la acumulación de `_dx` y las decisiones.

El acceso al perfil desde el muro, las condiciones de privacidad, consentimiento, seguridad, precios y derechos heredados no se cambiaron. `Hero` se limita a mensajes de imagen ordinaria y no envuelve fotos bomba. No se realizaron push, merge, publicaciones ni despliegues.

## Pruebas y validaciones

Se añadieron **15 casos** y se adaptó la identificación de la entrada del paso en la prueba existente de onboarding para distinguirla de los nuevos widgets de pulsación. Sus expectativas de visibilidad y movimiento reducido se conservan.

Las pruebas nuevas cubren:

- Pulsación, liberación inmediata, cancelación, teclado, objetivo táctil y cambio de movimiento reducido durante el contacto.
- Cambios rápidos de estado, ausencia de contenido saliente, reconstrucciones equivalentes y detención/reactivación con movimiento reducido y `TickerMode`.
- Conservación del cuerpo del perfil durante el drag y retorno.
- Ausencia de un ticker cosmético en el briefing de voz.
- Detención del controlador de revelado ya autorizado, conservación de su duración habitual y disponibilidad de la acción.
- Mensajes de stream inmediatos sin repetición ni desplazamiento añadido.
- Identidad de imágenes repetidas, apertura del visor y mantenimiento del origen de `Hero` mientras Flutter pausa los tickers de la ruta anterior; desactivación del vuelo en movimiento reducido.
- Ruta de match de 200/140 ms, callback de chat inmediato y fotogramas normal/reducido.

La primera ejecución completa detectó el uso inválido de duración cero en `animateToPage`. Se corrigió utilizando `jumpToPage`, conservando el flujo de persistencia y la duración habitual. Las pruebas del recorrido de onboarding y tutorial volvieron a pasar sin cambiar sus expectativas.

| Comando | Resultado |
| --- | --- |
| `flutter analyze --no-pub` | Sin incidencias. |
| `flutter test --no-pub --reporter expanded` | **1.236 pruebas superadas** en la suite completa. |
| `git diff --check` | Sin errores de whitespace. |

Los registros resumidos de la ejecución final se guardan en [validation.txt](phase2d/validation.txt).

## Evidencia visual

Se generaron **20 PNG**: cinco momentos del match en modo normal y reducido, tanto sobre el código de entrada como sobre la implementación posterior. La referencia anterior se ejecutó desde la copia inicial, mediante un fixture temporal que se eliminó al terminar; no se revirtió el código de la aplicación.

Se inspeccionaron los fotogramas de entrada a 40, 100 y 200 ms y el modo reducido. Se confirmó que el plano anterior deja de transparentarse durante la entrada, que las fotografías se acercan de manera contenida y que su posición permanece estática con movimiento reducido.

| Before | After | Why |
| --- | --- | --- |
| [Match, 40 ms](phase2d/evidence/before/match-040.png) | [Match, 40 ms](phase2d/evidence/after/match-040.png) | Fondo del nuevo plano y aproximación de las dos imágenes. |
| [Match, 100 ms](phase2d/evidence/before/match-100.png) | [Match, 100 ms](phase2d/evidence/after/match-100.png) | Continuidad dentro de la misma duración existente. |
| [Match, 200 ms](phase2d/evidence/before/match-200.png) | [Match, 200 ms](phase2d/evidence/after/match-200.png) | Composición final conservada. |
| [Movimiento reducido, 100 ms](phase2d/evidence/before/match-reduced-100.png) | [Movimiento reducido, 100 ms](phase2d/evidence/after/match-reduced-100.png) | Sin convergencia ni zoom espacial añadidos. |
| [Salida, 70 ms](phase2d/evidence/before/match-exit-070.png) | [Salida, 70 ms](phase2d/evidence/after/match-exit-070.png) | Salida dentro de los 140 ms originales. |

Son fotogramas del **motor de widgets de Flutter con reloj de prueba**, fuentes locales y datos ficticios. El fixture usa iniciales en lugar de fotografías personales, no consulta cuentas y no contiene una conversación real. La fuente de pruebas no cubre todos los emoji de una plataforma nativa. Los tiempos de los nombres de archivo no son mediciones de rendimiento.

No son capturas ni una grabación de iPhone/Android. No se validaron visualmente en ejecución todos los subestados de las demás pantallas. No hay dispositivos ADB conectados y falta el ejecutable del emulador Android en este entorno Windows.

## Pendientes y riesgos

- Probar gestos rápidos, interrupciones, retorno, teclado e insets en dispositivos iOS y Android, con movimiento reducido activado antes y durante la interacción.
- Medir la construcción, rasterización y memoria en modo profile con fotografías reales, caché fría, scroll y conversaciones largas. La reutilización del cuerpo y la eliminación de interpolaciones de layout no acreditan por sí solas fluidez a 60/120 Hz.
- Revisar el vuelo de imágenes con fotografías grandes, zoom y red lenta, y la transición desde un match real al chat. El caso de tags repetidos y la navegación se probaron con fixtures, no con fotografías de producción.
- Verificar grabación, reproducción, pausas y reanudación con los plugins nativos. Las pruebas no acreditan funcionamiento de cámara, micrófono, biometría, compras ni RTC en un dispositivo.
- La nueva entrada de perfil y los wrappers de pulsación afectan componentes compartidos; revisar sensibilidad táctil y cancelación por scroll con contenido real, lectores de pantalla y botones de accesibilidad.

No quedó una modificación visual bloqueada por requerir una regla de negocio. Las decisiones de no animar mensajes, precios, créditos, decisiones de seguridad y actualizaciones frecuentes son deliberadas.

## Archivos afectados

Inventario estructurado: [changed-files.json](phase2d/changed-files.json). El listado corresponde únicamente a esta fase; el repositorio mantiene también el trabajo sin confirmar de fases anteriores.

| ?rea | Archivos |
| --- | --- |
| ai_visual | [ai_visual_screen.dart](../../lib/src/features/ai_visual/presentation/ai_visual_screen.dart) |
| auth | [login_screen.dart](../../lib/src/features/auth/presentation/login_screen.dart), [session_gate.dart](../../lib/src/features/auth/presentation/session_gate.dart) |
| chat | [chat_detail_screen.dart](../../lib/src/features/chat/presentation/chat_detail_screen.dart), [voice_note_bubble.dart](../../lib/src/features/chat/presentation/voice_note_bubble.dart) |
| connection_lab | [lab_widgets.dart](../../lib/src/features/connection_lab/presentation/lab_widgets.dart) |
| feed | [feed_screen.dart](../../lib/src/features/feed/presentation/feed_screen.dart), [feed_top_bar.dart](../../lib/src/features/feed/presentation/feed_top_bar.dart) |
| home | [home_shell.dart](../../lib/src/features/home/presentation/home_shell.dart) |
| match | [match_created_dialog.dart](../../lib/src/features/match/presentation/match_created_dialog.dart) |
| monetization | [paywall_screen.dart](../../lib/src/features/monetization/presentation/paywall_screen.dart) |
| onboarding | [onboarding_screen.dart](../../lib/src/features/onboarding/presentation/onboarding_screen.dart), [voice_profile_setup.dart](../../lib/src/features/onboarding/presentation/voice_profile_setup.dart) |
| spark | [spark_entry_card.dart](../../lib/src/features/spark/presentation/spark_entry_card.dart) |
| stories | [blind_story_viewer_screen.dart](../../lib/src/features/stories/presentation/blind_story_viewer_screen.dart), [profile_reveal_screen.dart](../../lib/src/features/stories/presentation/profile_reveal_screen.dart) |
| tutorial | [tutorial_screen.dart](../../lib/src/features/tutorial/presentation/tutorial_screen.dart) |
| widgets | [attra_buttons.dart](../../lib/src/widgets/attra_buttons.dart), [attra_motion.dart](../../lib/src/widgets/attra_motion.dart) |
| Prueba | [chat_accessibility_recovery_test.dart](../../test/src/features/chat/presentation/chat_accessibility_recovery_test.dart) |
| Prueba | [feed_action_dock_test.dart](../../test/src/features/feed/presentation/feed_action_dock_test.dart) |
| Prueba | [onboarding_motion_test.dart](../../test/src/features/onboarding/presentation/onboarding_motion_test.dart) |
| Prueba | [voice_profile_setup_test.dart](../../test/src/features/onboarding/presentation/voice_profile_setup_test.dart) |
| Prueba | [profile_reveal_motion_test.dart](../../test/src/features/stories/profile_reveal_motion_test.dart) |
| Prueba | [attra_motion_test.dart](../../test/src/widgets/attra_motion_test.dart) |
| Prueba | [phase2d_motion_test.dart](../../test/visual/phase2d_motion_test.dart) |
