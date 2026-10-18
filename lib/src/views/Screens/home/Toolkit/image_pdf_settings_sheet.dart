import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/app_colors.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_layout.dart';
import 'package:broker_wallet/src/services/image_to_pdf/image_pdf_models.dart';

/// What the settings sheet hands back when the user applies it.
class ImagePdfSettingsResult {
  const ImagePdfSettingsResult(this.settings, this.password);

  final ImagePdfSettings settings;

  /// Only meaningful while [ImagePdfSettings.passwordProtect] is on.
  final String password;
}

/// The Images to PDF settings: page format, picture processing, layout and the
/// professional features. Nothing here is applied until the user taps Apply,
/// and a value that is out of range blocks Apply and says why.
class ImagePdfSettingsSheet extends StatefulWidget {
  const ImagePdfSettingsSheet({
    super.key,
    required this.settings,
    required this.hasPassword,
    required this.onApply,
  });

  final ImagePdfSettings settings;

  /// A password is already set for the pending PDF (so the sheet does not ask
  /// for it again unless the user changes it).
  final bool hasPassword;
  final ValueChanged<ImagePdfSettingsResult> onApply;

  @override
  State<ImagePdfSettingsSheet> createState() => _ImagePdfSettingsSheetState();
}

class _ImagePdfSettingsSheetState extends State<ImagePdfSettingsSheet> {
  static const Color _green = Color(0xFF4CAF50);

  late ImagePdfSettings _s;
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _watermark;
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _inches = false;
  bool _changePassword = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _s = widget.settings;
    _width = TextEditingController(text: _format(_s.customWidthMm));
    _height = TextEditingController(text: _format(_s.customHeightMm));
    _watermark = TextEditingController(text: _s.watermarkText);
    _changePassword = !widget.hasPassword;
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    _watermark.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _format(double mm) {
    final value = _inches ? ImagePdfLayout.mmToInch(mm) : mm;
    final text = value.toStringAsFixed(_inches ? 2 : 1);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// A number typed with Western or Arabic-Indic digits and either decimal
  /// separator.
  double? _parse(String raw) {
    var text = raw.trim();
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < arabic.length; i++) {
      text = text.replaceAll(arabic[i], '$i');
    }
    text = text.replaceAll('٫', '.').replaceAll(',', '.');
    return double.tryParse(text);
  }

  double? _mm(TextEditingController controller) {
    final value = _parse(controller.text);
    if (value == null) return null;
    return _inches ? ImagePdfLayout.inchToMm(value) : value;
  }

  bool get _customValid {
    if (_s.pageSize != PdfPageSize.custom) return true;
    final w = _mm(_width);
    final h = _mm(_height);
    if (w == null || h == null) return false;
    return w >= ImagePdfLimits.minCustomMm &&
        w <= ImagePdfLimits.maxCustomMm &&
        h >= ImagePdfLimits.minCustomMm &&
        h <= ImagePdfLimits.maxCustomMm;
  }

  bool get _watermarkValid =>
      !_s.watermark || ImagePdfText.isValidWatermark(_watermark.text);

  bool get _passwordValid {
    if (!_s.passwordProtect) return true;
    if (!_changePassword) return true;
    return ImagePdfText.isValidPassword(_password.text) &&
        _password.text == _confirm.text;
  }

  bool get _canApply => _customValid && _watermarkValid && _passwordValid;

  void _apply() {
    if (!_canApply) return;
    var settings = _s.copyWith(watermarkText: _watermark.text.trim());
    if (settings.pageSize == PdfPageSize.custom) {
      settings = settings.copyWith(
          customWidthMm: _mm(_width), customHeightMm: _mm(_height));
    }
    widget.onApply(ImagePdfSettingsResult(settings,
        settings.passwordProtect && _changePassword ? _password.text : ''));
    Navigator.of(context).pop();
  }

  void _switchUnit(bool inches) {
    if (inches == _inches) return;
    final w = _mm(_width);
    final h = _mm(_height);
    setState(() {
      _inches = inches;
      if (w != null) _width.text = _format(w);
      if (h != null) _height.text = _format(h);
    });
  }

  String _sizeName(AppLocalizations loc, PdfPageSize size) =>
      size == PdfPageSize.custom
          ? loc.translate('i2pCustom')
          : size.name.toUpperCase();

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_green, _green.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                const Icon(Icons.settings, color: AppColors.white, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    loc.translate('advancedPdfSettings'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppColors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                      loc.translate('pageFormat'), Icons.aspect_ratio),
                  const SizedBox(height: 12),
                  _dropdown<PdfPageSize>(
                    loc.translate('pageSize'),
                    _s.pageSize,
                    PdfPageSize.values,
                    (v) => setState(() => _s = _s.copyWith(pageSize: v)),
                    (v) => _sizeName(loc, v),
                  ),
                  if (_s.pageSize == PdfPageSize.custom) ..._customSize(loc),
                  const SizedBox(height: 12),
                  _dropdown<PdfOrientation>(
                    loc.translate('orientation'),
                    _s.orientation,
                    PdfOrientation.values,
                    (v) => setState(() => _s = _s.copyWith(orientation: v)),
                    (v) {
                      switch (v) {
                        case PdfOrientation.portrait:
                          return loc.translate('portrait');
                        case PdfOrientation.landscape:
                          return loc.translate('landscape');
                        case PdfOrientation.auto:
                          return loc.translate('auto');
                      }
                    },
                  ),
                  _hint(loc.translate('i2pOrientationHint'), colors),
                  const SizedBox(height: 24),
                  _sectionHeader(
                      loc.translate('imageProcessing'), Icons.photo_filter),
                  const SizedBox(height: 12),
                  _dropdown<ImageQuality>(
                    loc.translate('imageQuality'),
                    _s.quality,
                    ImageQuality.values,
                    (v) => setState(() => _s = _s.copyWith(quality: v)),
                    (v) => loc.translate('i2pQuality${_cap(v.name)}'),
                  ),
                  _hint(loc.translate('i2pQualityHint'), colors),
                  const SizedBox(height: 12),
                  _dropdown<CompressionLevel>(
                    loc.translate('compression'),
                    _s.compression,
                    CompressionLevel.values,
                    (v) => setState(() => _s = _s.copyWith(compression: v)),
                    (v) => loc.translate('i2pCompression${_cap(v.name)}'),
                  ),
                  _hint(loc.translate('i2pCompressionHint'), colors),
                  const SizedBox(height: 24),
                  _sectionHeader(
                      loc.translate('layoutAndDesign'), Icons.design_services),
                  const SizedBox(height: 12),
                  _dropdown<PdfLayout>(
                    loc.translate('layoutStyle'),
                    _s.layout,
                    PdfLayout.values,
                    (v) => setState(() => _s = _s.copyWith(layout: v)),
                    (v) {
                      switch (v) {
                        case PdfLayout.fitToPage:
                          return loc.translate('fitToPage');
                        case PdfLayout.originalSize:
                          return loc.translate('originalSize');
                        case PdfLayout.centerFit:
                          return loc.translate('centerFit');
                        case PdfLayout.tileMultiple:
                          return loc.translate('tileMultiple');
                      }
                    },
                  ),
                  _hint(loc.translate('i2pLayoutHint${_cap(_s.layout.name)}'),
                      colors),
                  if (_s.layout == PdfLayout.tileMultiple) ...[
                    const SizedBox(height: 12),
                    _dropdown<int>(
                      loc.translate('i2pTilesPerPage'),
                      _s.tilesPerPage,
                      ImagePdfLimits.tileCounts,
                      (v) => setState(() => _s = _s.copyWith(tilesPerPage: v)),
                      (v) => '$v',
                    ),
                  ],
                  const SizedBox(height: 12),
                  _slider(
                    loc.translate('pageMargin'),
                    _s.marginMm,
                    0,
                    ImagePdfLimits.maxMarginMm,
                    (v) => setState(() => _s = _s.copyWith(marginMm: v)),
                    loc
                        .translate('i2pMillimetres')
                        .replaceAll('{value}', _s.marginMm.round().toString()),
                  ),
                  const SizedBox(height: 24),
                  _sectionHeader(loc.translate('professionalFeatures'),
                      Icons.business_center),
                  const SizedBox(height: 12),
                  _switch(
                    loc.translate('addPageNumbers'),
                    loc.translate('includePageNumbersBottom'),
                    _s.pageNumbers,
                    (v) => setState(() => _s = _s.copyWith(pageNumbers: v)),
                    Icons.format_list_numbered,
                  ),
                  _switch(
                    loc.translate('addTimestamp'),
                    loc.translate('includeCreationDateTime'),
                    _s.timestamp,
                    (v) => setState(() => _s = _s.copyWith(timestamp: v)),
                    Icons.access_time,
                  ),
                  _switch(
                    loc.translate('addWatermark'),
                    loc.translate('includeAppWatermark'),
                    _s.watermark,
                    (v) => setState(() => _s = _s.copyWith(watermark: v)),
                    Icons.branding_watermark,
                  ),
                  if (_s.watermark) _watermarkField(loc, colors),
                  _switch(
                    loc.translate('i2pCoverPage'),
                    loc.translate('i2pCoverPageSub'),
                    _s.coverPage,
                    (v) => setState(() => _s = _s.copyWith(coverPage: v)),
                    Icons.article_outlined,
                  ),
                  _switch(
                    loc.translate('i2pPasswordProtect'),
                    loc.translate('i2pPasswordProtectSub'),
                    _s.passwordProtect,
                    (v) => setState(() => _s = _s.copyWith(passwordProtect: v)),
                    Icons.lock_outline,
                  ),
                  if (_s.passwordProtect) ..._passwordFields(loc, colors),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.cancel),
                          label: Text(loc.translate('cancel')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.card,
                            foregroundColor: AppColors.textSecondary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _canApply ? _apply : null,
                          icon: const Icon(Icons.check),
                          label: Text(loc.translate('applySettings')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: AppColors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _cap(String name) => name[0].toUpperCase() + name.substring(1);

  List<Widget> _customSize(AppLocalizations loc) {
    String? error;
    if (!_customValid) {
      error = loc.translate('i2pCustomRange');
    }
    Widget field(String label, TextEditingController controller) => Expanded(
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩.,٫]')),
              LengthLimitingTextInputFormatter(7),
            ],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: label,
              suffixText: _inches ? 'in' : 'mm',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        );
    return [
      const SizedBox(height: 12),
      Row(
        children: [
          field(loc.translate('i2pWidth'), _width),
          const SizedBox(width: 12),
          field(loc.translate('i2pHeight'), _height),
        ],
      ),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment<bool>(value: false, label: Text('mm')),
            ButtonSegment<bool>(value: true, label: Text('in')),
          ],
          selected: <bool>{_inches},
          onSelectionChanged: (v) => _switchUnit(v.first),
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(error,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.error)),
        ),
    ];
  }

  Widget _watermarkField(AppLocalizations loc, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _watermark,
        maxLength: ImagePdfLimits.maxWatermarkLength,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: loc.translate('i2pWatermarkText'),
          hintText: loc.translate('i2pWatermarkHint'),
          errorText:
              _watermarkValid ? null : loc.translate('i2pWatermarkInvalid'),
          border: const OutlineInputBorder(),
          counterText: '',
          isDense: true,
        ),
      ),
    );
  }

  List<Widget> _passwordFields(AppLocalizations loc, ColorScheme colors) {
    final mismatch = _changePassword &&
        _confirm.text.isNotEmpty &&
        _password.text != _confirm.text;
    final weak = _changePassword &&
        _password.text.isNotEmpty &&
        !ImagePdfText.isValidPassword(_password.text);
    return [
      if (widget.hasPassword && !_changePassword)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              const Icon(Icons.check_circle, size: 18, color: _green),
              const SizedBox(width: 8),
              Expanded(child: Text(loc.translate('i2pPasswordSet'))),
              TextButton(
                onPressed: () => setState(() => _changePassword = true),
                child: Text(loc.translate('i2pPasswordChange')),
              ),
            ],
          ),
        )
      else ...[
        TextField(
          controller: _password,
          obscureText: !_showPassword,
          enableSuggestions: false,
          autocorrect: false,
          maxLength: ImagePdfLimits.maxPasswordLength,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: loc.translate('i2pPassword'),
            errorText: weak ? loc.translate('i2pErrPassword') : null,
            border: const OutlineInputBorder(),
            counterText: '',
            isDense: true,
            suffixIcon: IconButton(
              icon:
                  Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirm,
          obscureText: !_showPassword,
          enableSuggestions: false,
          autocorrect: false,
          maxLength: ImagePdfLimits.maxPasswordLength,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: loc.translate('i2pPasswordConfirm'),
            errorText: mismatch ? loc.translate('i2pPasswordMismatch') : null,
            border: const OutlineInputBorder(),
            counterText: '',
            isDense: true,
          ),
        ),
      ],
      _hint(loc.translate('i2pPasswordWarning'), colors),
      const SizedBox(height: 4),
    ];
  }

  Widget _hint(String text, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: colors.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.tilePrimary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _green, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdown<T>(
    String label,
    T value,
    List<T> options,
    ValueChanged<T> onChanged,
    String Function(T) text,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.card),
            borderRadius: BorderRadius.circular(8),
            color: AppColors.surface,
          ),
          child: DropdownButton<T>(
            value: value,
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: AppColors.surface,
            items: [
              for (final option in options)
                DropdownMenuItem<T>(
                  value: option,
                  child: Text(
                    text(option),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _slider(String label, double value, double min, double max,
      ValueChanged<double> onChanged, String display) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                display,
                style: const TextStyle(
                    color: _green, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: _green,
            inactiveTrackColor: AppColors.card,
            thumbColor: _green,
          ),
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: (max - min).round(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _switch(String title, String subtitle, bool value,
      ValueChanged<bool> onChanged, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
            color: value ? _green.withValues(alpha: 0.3) : AppColors.card),
        borderRadius: BorderRadius.circular(12),
        color: value ? _green.withValues(alpha: 0.05) : AppColors.surface,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value ? _green.withValues(alpha: 0.1) : AppColors.card,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon,
                color: value ? _green : AppColors.textSecondary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: _green.withValues(alpha: 0.5),
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return _green.withValues(alpha: 0.8);
              }
              return Colors.grey.shade400;
            }),
          ),
        ],
      ),
    );
  }
}
