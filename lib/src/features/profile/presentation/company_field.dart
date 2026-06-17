import 'package:flutter/material.dart';

import '../domain/companies.dart';

/// Campo de empresa con autocompletado sobre [kCuratedCompanies].
/// Permite texto libre si la empresa no está en la lista.
class CompanyField extends StatefulWidget {
  const CompanyField({
    super.key,
    required this.onChanged,
    this.initialValue = '',
  });

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<CompanyField> createState() => _CompanyFieldState();
}

class _CompanyFieldState extends State<CompanyField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  final FocusNode _focus = FocusNode();
  List<String> _suggestions = const <String>[];

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        setState(() => _suggestions = const <String>[]);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final String q = value.trim().toLowerCase();
    final List<String> matches = q.isEmpty
        ? const <String>[]
        : kCuratedCompanies
            .where((String c) => c.toLowerCase().contains(q))
            .take(6)
            .toList(growable: false);
    setState(() => _suggestions = matches);
    widget.onChanged(value.trim());
  }

  void _select(String company) {
    _controller.text = company;
    _controller.selection =
        TextSelection.fromPosition(TextPosition(offset: company.length));
    setState(() => _suggestions = const <String>[]);
    _focus.unfocus();
    widget.onChanged(company);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _controller,
          focusNode: _focus,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            labelText: 'Empresa / dónde trabajas',
            hintText: 'Ej. KPMG, Telefónica, Google...',
            prefixIcon: Icon(Icons.business_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        if (_suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: _suggestions
                  .map((String c) => ListTile(
                        dense: true,
                        title: Text(c),
                        onTap: () => _select(c),
                      ))
                  .toList(growable: false),
            ),
          ),
      ],
    );
  }
}
