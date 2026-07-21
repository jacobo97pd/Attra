import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/app_colors.dart';

/// Imagen preset para grupos/planes (bundled en assets). Se guarda como
/// `asset:<ruta>` en `photoUrl`; la UI la detecta y usa Image.asset.
class GroupPhotoPreset {
  const GroupPhotoPreset(this.id, this.label, this.asset);
  final String id;
  final String label;
  final String asset;
  String get value => 'asset:$asset';
}

const List<GroupPhotoPreset> kGroupPhotoPresets = <GroupPhotoPreset>[
  GroupPhotoPreset('disco', 'Fiesta', 'assets/images/disco.png'),
  GroupPhotoPreset('paisaje', 'Aire libre', 'assets/images/paisaje.png'),
  GroupPhotoPreset('cine', 'Cine', 'assets/images/cine.png'),
  GroupPhotoPreset('cena', 'Cena', 'assets/images/Cena.png'),
  GroupPhotoPreset('pintura', 'Arte', 'assets/images/pintura.png'),
  GroupPhotoPreset('deportes', 'Deporte', 'assets/images/deportes.png'),
];

/// ¿La foto es un preset bundled (asset:) en vez de una URL de Storage?
bool isAssetPhoto(String url) => url.startsWith('asset:');

/// Ruta de asset de una foto preset (`asset:assets/...` → `assets/...`).
String assetPathOf(String url) =>
    isAssetPhoto(url) ? url.substring('asset:'.length) : url;

/// Elección de foto de grupo: o un preset (value `asset:...`) o una imagen
/// subida por el usuario (bytes + contentType).
class GroupPhotoChoice {
  const GroupPhotoChoice.preset(this.presetValue)
      : bytes = null,
        contentType = '';
  const GroupPhotoChoice.custom(this.bytes, this.contentType)
      : presetValue = null;

  final String? presetValue;
  final Uint8List? bytes;
  final String contentType;

  bool get isPreset => presetValue != null;
}

/// Hoja para elegir la foto del grupo: mini-galería de presets + "Subir foto".
class GroupPhotoPickerSheet {
  static Future<GroupPhotoChoice?> show(BuildContext context) {
    return showModalBottomSheet<GroupPhotoChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (BuildContext ctx) => const _PickerBody(),
    );
  }
}

class _PickerBody extends StatelessWidget {
  const _PickerBody();

  Future<void> _upload(BuildContext context) async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      imageQuality: 85,
    );
    if (file == null) return;
    final Uint8List bytes = await file.readAsBytes();
    final String ct =
        file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    if (context.mounted) {
      Navigator.of(context).pop(GroupPhotoChoice.custom(bytes, ct));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewPadding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Foto del grupo',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Elige una imagen o sube la tuya.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
            children: <Widget>[
              for (final GroupPhotoPreset p in kGroupPhotoPresets)
                _PresetThumb(
                  preset: p,
                  onTap: () => Navigator.of(context)
                      .pop(GroupPhotoChoice.preset(p.value)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _upload(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.attraRed,
                side: const BorderSide(color: AppColors.attraRed),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.upload_outlined),
              label: const Text('Subir foto del grupo'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetThumb extends StatelessWidget {
  const _PresetThumb({required this.preset, required this.onTap});
  final GroupPhotoPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(preset.asset, fit: BoxFit.cover),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: const BoxDecoration(
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(14)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.transparent, Color(0xCC000000)],
                ),
              ),
              child: Text(preset.label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
