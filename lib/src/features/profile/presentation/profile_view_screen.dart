import 'package:flutter/material.dart';

import '../../../widgets/attra_image.dart';
import '../domain/profile_state.dart';
import 'intro_media_view.dart';

/// Visor de SOLO LECTURA del perfil de otra persona (fotos, datos, bio,
/// intereses). Se abre al pinchar el perfil de un usuario en chats/matches.
class ProfileViewScreen extends StatelessWidget {
  const ProfileViewScreen({super.key, required this.profile});

  final SeedProfile profile;

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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
        child: AttraImage(url: photos.first.url),
      ));
    }

    // Bloque de información (nombre, lugar, trabajo, bio, intereses).
    items.add(Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('${profile.displayName}$ageText',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          if (place.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: <Widget>[
                const Icon(Icons.place_outlined, size: 18),
                const SizedBox(width: 6),
                Text(place),
              ]),
            ),
          if (work.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: <Widget>[
                const Icon(Icons.work_outline, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(work)),
              ]),
            ),
          if (profile.bio.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Text('Sobre mí', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(profile.bio, style: theme.textTheme.bodyLarge),
          ],
          if (profile.interests.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text('Intereses', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: IntroVideoPlayer(video: profile.introVideo!),
      ));
    }

    // Audio de presentación (tras el bloque de info).
    if (profile.introAudio != null) {
      items.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: AttraImage(url: photo.url),
          ),
        ),
      ));
      if (promptIndex < prompts.length) {
        items.add(_PromptCard(prompt: prompts[promptIndex], theme: theme));
        promptIndex++;
      }
    }

    // Prompts sobrantes si hay más prompts que fotos adicionales.
    while (promptIndex < prompts.length) {
      items.add(_PromptCard(prompt: prompts[promptIndex], theme: theme));
      promptIndex++;
    }

    items.add(const SizedBox(height: 24));

    return Scaffold(
      appBar: AppBar(title: Text('${profile.displayName}$ageText')),
      body: ListView(padding: EdgeInsets.zero, children: items),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.prompt, required this.theme});

  final PublicPrompt prompt;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(prompt.question, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(
              prompt.answer,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
            ),
          ],
        ),
      ),
    );
  }
}
