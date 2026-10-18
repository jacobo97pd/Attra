import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/app_spacing.dart';
import '../../../theme/attra_colors.dart';
import '../../../widgets/attra_editorial.dart';
import '../../../widgets/attra_image.dart';
import '../../match/data/match_service.dart';
import '../../safety/presentation/safety_actions.dart';
import '../../social/presentation/intent_badge.dart';
import '../domain/profile_state.dart';
import 'intro_media_view.dart';

/// Visor de SOLO LECTURA del perfil de otra persona (fotos, datos, bio,
/// intereses). Se abre al pinchar el perfil de un usuario en chats/matches.
class ProfileViewScreen extends StatelessWidget {
  const ProfileViewScreen({
    super.key,
    required this.profile,
    this.matchService,
    this.onBlocked,
  });

  final SeedProfile profile;

  /// Guideline 1.2: si se pasa, la barra superior ofrece Reportar y Bloquear.
  /// Es nulo cuando la pantalla muestra el perfil PROPIO.
  final MatchService? matchService;

  /// Se llama tras bloquear, para que el llamante refresque su listado.
  final VoidCallback? onBlocked;

  /// Galería del perfil: la foto PRINCIPAL (photoUrl) primero y luego las
  /// adicionales (sin duplicar si coincide la URL).
  List<AdditionalPhoto> get _photos {
    final List<AdditionalPhoto> out = <AdditionalPhoto>[];
    if (profile.photoUrl.isNotEmpty) {
      out.add(AdditionalPhoto(
          url: profile.photoUrl, storagePath: '', source: 'primary', order: 0));
    }
    for (final AdditionalPhoto p in profile.photos) {
      if (p.url.isNotEmpty && p.url != profile.photoUrl) out.add(p);
    }
    return out;
  }

  /// Abre el Instagram del perfil: intenta la app nativa y, si no, el navegador.
  Future<void> _openInstagram(String handle) async {
    final String h = handle.replaceAll('@', '').trim();
    if (h.isEmpty) return;
    final Uri appUri = Uri.parse('instagram://user?username=$h');
    final Uri webUri = Uri.parse('https://instagram.com/$h');
    if (await canLaunchUrl(appUri)) {
      await launchUrl(appUri);
    } else {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double inset = AppSpacing.pageInset(context);
    final List<AdditionalPhoto> photos = _photos;
    final List<PublicPrompt> prompts = profile.profilePrompts;
    final String ageText = profile.age != null ? ', ${profile.age}' : '';
    final String place = <String>[profile.city, profile.country]
        .where((String s) => s.isNotEmpty)
        .join(', ');
    final String work = <String>[profile.jobTitle, profile.company]
        .where((String s) => s.isNotEmpty)
        .join(' · ');

    // Construye la lista intercalando fotos y prompts.
    // Estructura: foto hero → info → [foto2 → prompt1? → foto3 → prompt2? …]
    final List<Widget> items = <Widget>[];

    // Foto principal (hero).
    if (photos.isNotEmpty) {
      items.add(AspectRatio(
        aspectRatio: 3 / 4,
        child: Semantics(
          image: true,
          label: 'Foto principal de ${profile.displayName}',
          child: ExcludeSemantics(
              child: AttraImage(
                  url: photos.first.url,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg))),
        ),
      ));
    }

    // Bloque de información (nombre, lugar, trabajo, bio, intereses).
    items.add(Padding(
      padding: EdgeInsets.fromLTRB(inset, 24, inset, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            header: true,
            child: Text('${profile.displayName}$ageText',
                style: theme.textTheme.headlineLarge),
          ),
          // Modo Amigos: badge de intención (oculto en dating, que es lo normal).
          if (!profile.intentMode.isDating)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: IntentBadge(mode: profile.intentMode, hideDating: true),
            ),
          if (place.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: <Widget>[
                const Icon(Icons.place_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(place, style: theme.textTheme.bodyMedium)),
              ]),
            ),
          if (work.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: <Widget>[
                const Icon(Icons.work_outline, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(work, style: theme.textTheme.bodyMedium)),
              ]),
            ),
          if (profile.instagram.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _openInstagram(profile.instagram),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    foregroundColor: context.colors.textPrimary,
                  ),
                  icon: const Icon(Icons.camera_alt_outlined, size: 20),
                  label: Text('@${profile.instagram}'),
                ),
              ),
            ),
          if (profile.bio.isNotEmpty) ...<Widget>[
            const SizedBox(height: 32),
            const AttraSectionHeading(title: 'Sobre mí'),
            const SizedBox(height: 12),
            Text(profile.bio, style: theme.textTheme.bodyLarge),
          ],
          if (profile.interests.isNotEmpty) ...<Widget>[
            const SizedBox(height: 32),
            const AttraSectionHeading(title: 'Intereses'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: profile.interests
                  .map((String i) => Chip(
                      label: Text(i), visualDensity: VisualDensity.compact))
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    ));

    // Vídeo de presentación (debajo de la info/bio/intereses).
    if (profile.introVideo != null) {
      items.add(Padding(
        padding: EdgeInsets.fromLTRB(inset, 32, inset, 0),
        child: IntroVideoPlayer(video: profile.introVideo!),
      ));
    }

    // Audio de presentación (tras el bloque de info).
    if (profile.introAudio != null) {
      items.add(Padding(
        padding: EdgeInsets.fromLTRB(inset, 24, inset, 0),
        child: IntroAudioPlayer(
          audio: profile.introAudio!,
          label: 'Audio de presentación',
        ),
      ));
    }

    // Fotos adicionales con prompts intercalados después de cada foto.
    final List<AdditionalPhoto> rest = photos.skip(1).toList();
    int promptIndex = 0;
    for (final AdditionalPhoto photo in rest) {
      items.add(Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Semantics(
          image: true,
          label: 'Foto de ${profile.displayName}',
          child: ExcludeSemantics(
              child: AspectRatio(
            aspectRatio: 3 / 4,
            child: AttraImage(
                url: photo.url,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
          )),
        ),
      ));
      if (promptIndex < prompts.length) {
        items.add(_promptNote(context, prompts[promptIndex]));
        promptIndex++;
      }
    }

    // Prompts sobrantes si hay más prompts que fotos adicionales.
    while (promptIndex < prompts.length) {
      items.add(_promptNote(context, prompts[promptIndex]));
      promptIndex++;
    }

    items.add(SizedBox(height: 32 + MediaQuery.paddingOf(context).bottom));

    final MatchService? safetyService = matchService;
    return Scaffold(
      appBar: AppBar(
        title: Text('${profile.displayName}$ageText'),
        actions: <Widget>[
          if (safetyService != null)
            SafetyMenuButton(
              matchService: safetyService,
              uid: profile.id,
              displayName: profile.displayName,
              onResult: (SafetyActionResult result) {
                if (result != SafetyActionResult.blocked) return;
                onBlocked?.call();
                if (context.mounted) Navigator.of(context).maybePop();
              },
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          child: AttraContentFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: items,
            ),
          ),
        ),
      ),
    );
  }

  Widget _promptNote(BuildContext context, PublicPrompt prompt) {
    final double inset = AppSpacing.pageInset(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          inset - AppSpacing.lg, 8, inset - AppSpacing.lg, 0),
      child: AttraPromptNote(question: prompt.question, answer: prompt.answer),
    );
  }
}
