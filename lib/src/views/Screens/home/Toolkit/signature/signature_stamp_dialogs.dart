import 'package:flutter/material.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/services/signature/signature_models.dart';
import 'package:broker_wallet/src/Views/Screens/home/Toolkit/signature/signature_ui_support.dart';

/// What the user chose in the "add" sheet.
enum AddStampChoice {
  /// Draw a new signature.
  newSignature,

  /// Use a signature drawn earlier in this session ([AddStampSelection.asset]).
  reuseSignature,

  /// Draw new initials.
  drawInitials,

  /// Type new initials.
  typeInitials,

  /// Use initials made earlier in this session ([AddStampSelection.asset]).
  reuseInitials,

  /// Add a date.
  date,

  /// Add a typed text.
  text,
}

class AddStampSelection {
  const AddStampSelection(this.choice, [this.asset]);

  final AddStampChoice choice;
  final StampAsset? asset;
}

/// The text and colour of a typed item.
class TypedStampResult {
  const TypedStampResult(this.text, this.colorValue);

  final String text;
  final int colorValue;
}

/// The sheet that offers what can be placed: a signature, initials, a date or a
/// text, and the signatures and initials already made in this session.
Future<AddStampSelection?> showAddStampSheet(
  BuildContext context, {
  required List<StampAsset> signatures,
  required List<StampAsset> initials,
}) {
  return showModalBottomSheet<AddStampSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _AddStampSheet(
      signatures: signatures,
      initials: initials,
    ),
  );
}

class _AddStampSheet extends StatelessWidget {
  const _AddStampSheet({required this.signatures, required this.initials});

  final List<StampAsset> signatures;
  final List<StampAsset> initials;

  Widget _option(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required AddStampSelection selection,
  }) {
    return InkWell(
      key: key,
      onTap: () => Navigator.of(context).pop(selection),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey[200]!, width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _reuseRow(
    BuildContext context,
    AppLocalizations localization,
    List<StampAsset> assets,
    AddStampChoice choice,
    String keyPrefix,
  ) {
    if (assets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localization.translate('sigUseAgain'),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: assets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final asset = assets[index];
                return InkWell(
                  key: ValueKey<String>('$keyPrefix-${asset.id}'),
                  onTap: () => Navigator.of(context)
                      .pop(AddStampSelection(choice, asset)),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 96,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Image.memory(
                      asset.png,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              localization.translate('sigAddItem'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 16),
            _option(
              context,
              key: const ValueKey<String>('add-signature'),
              icon: Icons.draw,
              color: SignatureColors.redLight,
              title: localization.translate('sigDrawNewSignature'),
              subtitle: localization.translate('sigDrawNewSignatureSub'),
              selection: const AddStampSelection(AddStampChoice.newSignature),
            ),
            _reuseRow(context, localization, signatures,
                AddStampChoice.reuseSignature, 'reuse-signature'),
            const SizedBox(height: 8),
            _option(
              context,
              key: const ValueKey<String>('add-initials-draw'),
              icon: Icons.gesture,
              color: Colors.blue,
              title: localization.translate('sigDrawInitials'),
              subtitle: localization.translate('sigInitialsSub'),
              selection: const AddStampSelection(AddStampChoice.drawInitials),
            ),
            const SizedBox(height: 8),
            _option(
              context,
              key: const ValueKey<String>('add-initials-type'),
              icon: Icons.text_fields,
              color: Colors.blue,
              title: localization.translate('sigTypeInitials'),
              subtitle: localization.translate('sigTypeInitialsSub'),
              selection: const AddStampSelection(AddStampChoice.typeInitials),
            ),
            _reuseRow(context, localization, initials,
                AddStampChoice.reuseInitials, 'reuse-initials'),
            const SizedBox(height: 8),
            _option(
              context,
              key: const ValueKey<String>('add-date'),
              icon: Icons.event,
              color: Colors.green,
              title: localization.translate('sigAddDate'),
              subtitle: localization.translate('sigAddDateSub'),
              selection: const AddStampSelection(AddStampChoice.date),
            ),
            const SizedBox(height: 8),
            _option(
              context,
              key: const ValueKey<String>('add-text'),
              icon: Icons.title,
              color: Colors.orange,
              title: localization.translate('sigAddText'),
              subtitle: localization.translate('sigAddTextSub'),
              selection: const AddStampSelection(AddStampChoice.text),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: Colors.grey[300]!, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                localization.translate('cancel'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF666666),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a typed item: initials or a text. Returns null when cancelled.
Future<TypedStampResult?> showTypedStampDialog(
  BuildContext context, {
  required StampKind kind,
  String? initialText,
  int? initialColor,
}) {
  assert(kind == StampKind.initials || kind == StampKind.text);
  return showDialog<TypedStampResult>(
    context: context,
    builder: (_) => _TypedStampDialog(
      kind: kind,
      initialText: initialText,
      initialColor: initialColor,
    ),
  );
}

class _TypedStampDialog extends StatefulWidget {
  const _TypedStampDialog({
    required this.kind,
    this.initialText,
    this.initialColor,
  });

  final StampKind kind;
  final String? initialText;
  final int? initialColor;

  @override
  State<_TypedStampDialog> createState() => _TypedStampDialogState();
}

class _TypedStampDialogState extends State<_TypedStampDialog> {
  late final TextEditingController _controller;
  late int _color;
  String? _error;

  int get _maxRunes => widget.kind == StampKind.initials
      ? StampText.maxInitialsRunes
      : StampText.maxTextRunes;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? '');
    _color = widget.initialColor ?? kSignaturePenColors.first.toARGB32();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final localization = AppLocalizations.of(context);
    final cleaned = StampText.clean(_controller.text, maxRunes: _maxRunes);
    if (cleaned == null) {
      setState(() => _error = localization.translate(
          widget.kind == StampKind.initials
              ? 'sigInitialsInvalid'
              : 'sigTextInvalid'));
      return;
    }
    Navigator.of(context).pop(TypedStampResult(cleaned, _color));
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    final isInitials = widget.kind == StampKind.initials;
    return AlertDialog(
      title: Text(localization
          .translate(isInitials ? 'sigTypeInitials' : 'sigAddText')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey<String>('typed-stamp-field'),
              controller: _controller,
              autofocus: true,
              maxLength: _maxRunes,
              textDirection: StampText.isRightToLeft(_controller.text)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              textCapitalization: isInitials
                  ? TextCapitalization.characters
                  : TextCapitalization.sentences,
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: localization
                    .translate(isInitials ? 'sigInitialsHint' : 'sigTextHint'),
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              localization.translate('color'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              children: [
                for (final color in kSignaturePenColors)
                  GestureDetector(
                    key: ValueKey<String>('typed-color-${color.toARGB32()}'),
                    onTap: () => setState(() => _color = color.toARGB32()),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.toARGB32() == _color
                              ? Colors.grey[800]!
                              : Colors.grey[300]!,
                          width: color.toARGB32() == _color ? 3 : 1,
                        ),
                      ),
                      child: color.toARGB32() == _color
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 18)
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localization.translate('cancel')),
        ),
        TextButton(
          key: const ValueKey<String>('typed-stamp-ok'),
          onPressed: _submit,
          child: Text(localization.translate('sigAdd')),
        ),
      ],
    );
  }
}

/// Asks for a date: today by default, another day by choice, in a numeric or a
/// long format. Returns the text to place, or null when cancelled.
Future<TypedStampResult?> showDateStampDialog(
  BuildContext context, {
  DateTime? now,
}) {
  return showDialog<TypedStampResult>(
    context: context,
    builder: (_) => _DateStampDialog(now: now ?? DateTime.now()),
  );
}

class _DateStampDialog extends StatefulWidget {
  const _DateStampDialog({required this.now});

  final DateTime now;

  @override
  State<_DateStampDialog> createState() => _DateStampDialogState();
}

class _DateStampDialogState extends State<_DateStampDialog> {
  late DateTime _date;
  bool _numeric = true;
  int _color = kSignaturePenColors.first.toARGB32();

  @override
  void initState() {
    super.initState();
    _date = DateTime(widget.now.year, widget.now.month, widget.now.day);
  }

  bool get _arabic => Localizations.localeOf(context).languageCode == 'ar';

  String get _text => _numeric
      ? StampDate.numeric(_date)
      : StampDate.long(_date, arabic: _arabic);

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(widget.now.year - 100),
      lastDate: DateTime(widget.now.year + 100),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(localization.translate('sigAddDate')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                _text,
                key: const ValueKey<String>('date-preview'),
                style: Theme.of(context).textTheme.titleLarge,
                textDirection: _numeric || !_arabic
                    ? TextDirection.ltr
                    : TextDirection.rtl,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                key: const ValueKey<String>('date-choose'),
                onPressed: _pick,
                icon: const Icon(Icons.edit_calendar),
                label: Text(localization.translate('sigChooseDate')),
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: const ValueKey<String>('date-format-numeric'),
                  label: Text(localization.translate('sigDateNumeric')),
                  selected: _numeric,
                  onSelected: (_) => setState(() => _numeric = true),
                ),
                ChoiceChip(
                  key: const ValueKey<String>('date-format-long'),
                  label: Text(localization.translate('sigDateLong')),
                  selected: !_numeric,
                  onSelected: (_) => setState(() => _numeric = false),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              children: [
                for (final color in kSignaturePenColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = color.toARGB32()),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.toARGB32() == _color
                              ? Colors.grey[800]!
                              : Colors.grey[300]!,
                          width: color.toARGB32() == _color ? 3 : 1,
                        ),
                      ),
                      child: color.toARGB32() == _color
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 18)
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(localization.translate('cancel')),
        ),
        TextButton(
          key: const ValueKey<String>('date-ok'),
          onPressed: () =>
              Navigator.of(context).pop(TypedStampResult(_text, _color)),
          child: Text(localization.translate('sigAdd')),
        ),
      ],
    );
  }
}
