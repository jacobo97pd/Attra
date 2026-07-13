import 'package:flutter/material.dart';

import '../data/safedate_service.dart';
import '../domain/trusted_contact.dart';

/// Contactos de confianza (SafeDate). Privados: nunca visibles para el match ni
/// otros usuarios. Solo se guardan los seleccionados explícitamente (no la
/// agenda del dispositivo).
class TrustedContactsScreen extends StatelessWidget {
  const TrustedContactsScreen({
    super.key,
    required this.uid,
    required this.service,
  });

  final String uid;
  final SafeDateService service;

  Future<void> _addOrEdit(BuildContext context, [TrustedContact? existing]) async {
    final TrustedContactInput? input =
        await _TrustedContactForm.show(context, existing);
    if (input == null) return;
    try {
      await service.saveTrustedContact(input, contactId: existing?.id);
    } on SafeDateException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Contactos de confianza')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(context),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Añadir'),
      ),
      body: StreamBuilder<List<TrustedContact>>(
        stream: service.observeTrustedContacts(uid),
        builder:
            (BuildContext context, AsyncSnapshot<List<TrustedContact>> snap) {
          final List<TrustedContact> contacts =
              snap.data ?? const <TrustedContact>[];
          return ListView(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 90 + MediaQuery.of(context).viewPadding.bottom),
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.lock_outline,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Estos contactos son privados: nadie con quien hagas match '
                        'los verá. Podrás avisar a una persona de confianza sin salir '
                        'de Attra.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (contacts.isEmpty)
                Text('Aún no has añadido contactos de confianza.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.outline))
              else
                for (final TrustedContact c in contacts)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.15),
                        child: Text(
                          c.displayName.isNotEmpty
                              ? c.displayName[0].toUpperCase()
                              : '?',
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                      ),
                      title: Row(
                        children: <Widget>[
                          Flexible(
                            child: Text(c.displayName,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          if (c.isPrimary) ...<Widget>[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('Principal',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        <String>[
                          if (c.phone != null) c.phone!,
                          if (c.email != null) c.email!,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (String v) {
                          if (v == 'edit') _addOrEdit(context, c);
                          if (v == 'delete') service.deleteTrustedContact(c.id);
                        },
                        itemBuilder: (_) => const <PopupMenuEntry<String>>[
                          PopupMenuItem<String>(
                              value: 'edit', child: Text('Editar')),
                          PopupMenuItem<String>(
                              value: 'delete', child: Text('Eliminar')),
                        ],
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// Formulario de contacto (nombre + teléfono/email + principal). Valida con el
/// modelo puro TrustedContactInput.
class _TrustedContactForm extends StatefulWidget {
  const _TrustedContactForm({this.existing});
  final TrustedContact? existing;

  static Future<TrustedContactInput?> show(
      BuildContext context, TrustedContact? existing) {
    return showModalBottomSheet<TrustedContactInput>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TrustedContactForm(existing: existing),
    );
  }

  @override
  State<_TrustedContactForm> createState() => _TrustedContactFormState();
}

class _TrustedContactFormState extends State<_TrustedContactForm> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.displayName ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.existing?.phone ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.existing?.email ?? '');
  late bool _primary = widget.existing?.isPrimary ?? false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    final TrustedContactInput input = TrustedContactInput(
      displayName: _name.text,
      phone: _phone.text,
      email: _email.text,
      isPrimary: _primary,
    );
    final String? err = input.validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.of(context).pop(input);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.existing == null ? 'Nuevo contacto' : 'Editar contacto',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Nombre', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'Teléfono (opcional)',
                hintText: '+34 …',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
                labelText: 'Email (opcional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _primary,
            onChanged: (bool v) => setState(() => _primary = v),
            title: const Text('Contacto principal'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          FilledButton(onPressed: _submit, child: const Text('Guardar')),
        ],
      ),
    );
  }
}
