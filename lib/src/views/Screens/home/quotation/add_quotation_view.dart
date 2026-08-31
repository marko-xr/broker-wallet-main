// lib/src/Views/Screens/home/quotation/add_quotation_view.dart
// ignore_for_file: unused_element_parameter

import 'package:broker_wallet/src/Views/Screens/home/quotation/add_quotation_viewmodel.dart';
import 'package:broker_wallet/src/Views/Screens/home/quotation/quotation_model.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/save_cancel_buttons.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/constants/app_colors.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

class AddQuotationView extends StatelessWidget {
  const AddQuotationView({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    return ChangeNotifierProvider(
      create: (_) => AddQuotationViewModel(),
      child: Consumer<AddQuotationViewModel>(
        builder: (context, vm, _) {
          final colors = Theme.of(context).colorScheme;

          return Scaffold(
            backgroundColor: colors.surface,
            appBar: AppBar(
              leading: const BackArrowButton(),
              title: Text(loc.translate('quotation'),
                  style: AppTextStyles.appBarTitle),
              centerTitle: true,
              elevation: 0,
              backgroundColor: colors.surface,
            ),
            body: Stack(
              fit: StackFit.expand,
              children: [
                // Scrollable content
                SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 20,
                    bottom: keyboardHeight > 0
                        ? keyboardHeight + 20
                        : 100, // Dynamic bottom padding
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ===== HEADER / GENERAL =====
                      _CollapsibleSection(
                        title: loc.translate('generalInformation'),
                        child: _SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Label(loc.translate('propertyTitle')),
                              _TextFieldIcon(
                                iconAsset: 'assets/icons/profile-person.svg',
                                hint: loc.translate('enterPropertyTitle'),
                                value: vm.propertyTitle,
                                onChanged: vm.setPropertyTitle,
                              ),
                              const SizedBox(height: 14),
                              _Label(loc.translate('propertyType')),
                              _TextFieldIcon(
                                iconAsset: 'assets/icons/subtitle-lable.svg',
                                hint: loc.translate('enterPropertyType'),
                                value: vm.propertyType,
                                onChanged: vm.setPropertyType,
                              ),
                              const SizedBox(height: 14),
                              _Label(loc.translate('parking')),
                              _SwitchRow(
                                labelOn: loc.translate('yes'),
                                labelOff: loc.translate('no'),
                                value: vm.parking,
                                onChanged: vm.setParking,
                              ),
                              const SizedBox(height: 14),
                              _Label(loc.translate('date')),
                              _DatePickerField(
                                iconAsset: 'assets/icons/calendar-lable.svg',
                                hint: loc.translate('enterDate'),
                                value: vm.date,
                                onChanged: vm.setDate,
                              ),
                              const SizedBox(height: 14),
                              _Label(loc.translate('starting')),
                              _SmartDatePickerField(
                                iconAsset: 'assets/icons/calendar-lable.svg',
                                hint: 'YYYY-MM-DD',
                                value: vm.startDate,
                                onChanged: vm.setStartDate,
                                isStartDate: true,
                              ),
                              const SizedBox(height: 14),
                              _Label(loc.translate('ending')),
                              _AutoCalculatedDateField(
                                iconAsset: 'assets/icons/calendar-lable.svg',
                                hint: 'YYYY-MM-DD',
                                value: vm.endDate,
                                onChanged: vm.setEndDate,
                              ),
                              const SizedBox(height: 14),

                              // Welcome Message Configuration
                              _Label(loc.translate('welcomeMessageSettings')),
                              _WelcomeMessageModeSelector(
                                mode: vm.welcomeMessageMode,
                                onModeChanged: vm.setWelcomeMessageMode,
                              ),

                              // Show template message preview only for auto mode
                              if (vm.welcomeMessageMode ==
                                  WelcomeMessageMode.auto) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    border: Border.all(color: colors.primary),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.auto_awesome,
                                              size: 16, color: colors.primary),
                                          const SizedBox(width: 8),
                                          Text(
                                            _getLocalizedWithFallback(
                                                loc,
                                                'templatePreview',
                                                'Template Preview'),
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: colors.primary,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        _generateWelcomeMessagePreview(vm, loc),
                                        style: TextStyle(
                                          color: colors.primary,
                                          fontSize: 13,
                                          height: 1.4,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              if (vm.welcomeMessageMode ==
                                  WelcomeMessageMode.custom) ...[
                                const SizedBox(height: 8),
                                _NotesBox(
                                  value: vm.customWelcomeMessage,
                                  onChanged: vm.setCustomWelcomeMessage,
                                  hint: loc
                                      .translate('writeCustomWelcomeMessage'),
                                ),
                              ],

                              const SizedBox(height: 14),
                              _Label(loc.translate('customNote')),
                              _NotesBox(
                                value: vm.customNote,
                                onChanged: vm.setCustomNote,
                                hint: loc.translate('enterCustomNote'),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ===== MONEY & TERMS =====
                      _CollapsibleSection(
                        title: loc.translate('moneyAndTerms'),
                        child: _SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Label(loc.translate('currencyCode')),
                              _TextFieldIcon(
                                iconAsset: 'assets/icons/price-lable.svg',
                                hint: 'AED',
                                value: vm.currencyCode,
                                onChanged: vm.setCurrencyCode,
                              ),
                              const SizedBox(height: 14),
                              _LabelWithCurrency(loc.translate('totalAmount')),
                              _TextFieldIcon(
                                iconAsset: 'assets/icons/price-lable.svg',
                                hint: loc.translate('enterTotalPrice'),
                                value: vm.totalAmount,
                                onChanged: vm.setTotalAmount,
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 14),
                              _Label(loc.translate('numberOfInstallments')),
                              _TextFieldIcon(
                                iconAsset:
                                    'assets/icons/installments-lable.svg',
                                hint: loc.translate('enterInstallmentsNumber'),
                                value: vm.numberOfInstallments,
                                onChanged: vm.setNumberOfInstallments,
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 14),
                              _Label(loc.translate('paymentType')),
                              _PaymentTypeChips(
                                value: vm.paymentType,
                                onChanged: vm.setPaymentType,
                                cashLabel: loc.translate('cash'),
                                chequeLabel: loc.translate('cheque'),
                                bankLabel: loc.translate('bankTransfer'),
                              ),
                              const SizedBox(height: 14),
                              _LabelWithCurrency(
                                  loc.translate('insuranceAmount')),
                              _TextFieldIcon(
                                iconAsset: 'assets/icons/price-lable.svg',
                                hint: loc.translate('enterAmount'),
                                value: vm.insuranceAmount,
                                onChanged: vm.setInsuranceAmount,
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 10),
                              _SwitchRow(
                                labelOn:
                                    '${loc.translate('returnable')} : ${loc.translate('yes')}',
                                labelOff:
                                    '${loc.translate('returnable')} : ${loc.translate('no')}',
                                value: vm.insuranceReturnable,
                                onChanged: vm.setInsuranceReturnable,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ===== DOWNPAYMENTS TABLE =====
                      _CollapsibleSection(
                        title: loc.translate('downpayments'),
                        onExpanded: vm
                            .triggerInitialSmartCalculation, // Trigger smart calc when opened
                        child: _SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Show smart calculation info if possible
                              if (vm.canGenerateSmartDownpayments &&
                                  vm.downpayments.isEmpty)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              _HelperLabelRow(labels: [
                                loc.translate('paymentMethod'),
                                loc.translate('paymentNumber'),
                                loc.translate('paymentDate'),
                                loc.translate('installmentAmount'),
                              ]),
                              const SizedBox(height: 8),
                              ListView.builder(
                                itemCount: vm.downpayments.length,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemBuilder: (context, index) {
                                  final row = vm.downpayments[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _DownpaymentRow(
                                      index: index,
                                      method: row.method,
                                      number: row.number,
                                      date: row.date,
                                      amount: row.amount,
                                      onMethodChanged: (m) =>
                                          vm.updateDownpaymentMethod(index, m),
                                      onNumberChanged: (v) =>
                                          vm.updateDownpaymentNumber(index, v),
                                      onDateChanged: (v) =>
                                          vm.updateDownpaymentDate(index, v),
                                      onAmountChanged: (v) =>
                                          vm.updateDownpaymentAmount(index, v),
                                      onRemove: () =>
                                          vm.removeDownpaymentRow(index),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: vm.addDownpaymentRow,
                                    icon: const Icon(Icons.add),
                                    label: Text(loc.translate('addRow')),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ===== GOVERNMENT FEES =====
                      _CollapsibleSection(
                        title: loc.translate('governmentFees'),
                        child: _SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _LabelWithCurrency(loc.translate('municipality')),
                              _TextFieldIcon(
                                iconAsset: 'assets/icons/price-lable.svg',
                                hint: 'AED',
                                value: vm.govMunicipality,
                                onChanged: vm.setGovMunicipality,
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 14),
                              _LabelWithCurrency(loc.translate('electricity')),
                              _TextFieldIcon(
                                iconAsset: 'assets/icons/price-lable.svg',
                                hint: 'AED',
                                value: vm.govElectricity,
                                onChanged: vm.setGovElectricity,
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 14),
                              _LabelWithCurrency(loc.translate('sewerage')),
                              _TextFieldIcon(
                                iconAsset: 'assets/icons/price-lable.svg',
                                hint: 'AED',
                                value: vm.govSewerage,
                                onChanged: vm.setGovSewerage,
                                keyboardType: TextInputType.number,
                              ),
                              const SizedBox(height: 14),
                              _LabelWithCurrency(loc.translate('total')),
                              _TextFieldIcon(
                                iconAsset: 'assets/icons/price-lable.svg',
                                hint: loc.translate('autoOrManual'),
                                value: vm.govTotal,
                                onChanged: vm.setGovTotal,
                                keyboardType: TextInputType.number,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ===== ADMINISTRATIVE FEES =====
                      _CollapsibleSection(
                        title: loc.translate('administrativeFees'),
                        onExpanded: () {
                          // Add default fee if empty when section is expanded
                          if (vm.administrativeFees.isEmpty) {
                            vm.addAdministrativeFeeRow();
                          }
                        },
                        child: _SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Show message if no fees added yet
                              if (vm.administrativeFees.isEmpty) ...[
                                Container(
                                  width: double.infinity,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 20),
                                  child: Text(
                                    loc.translate('addAdministrativeFeeHint'),
                                    style: AppTextStyles.hintText,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],

                              // Dynamic Administrative Fee Rows
                              if (vm.administrativeFees.isNotEmpty) ...[
                                for (int i = 0;
                                    i < vm.administrativeFees.length;
                                    i++)
                                  Padding(
                                    padding: EdgeInsets.only(bottom: 14),
                                    child: _AdministrativeFeeRow(
                                      index: i,
                                      title: vm.administrativeFees[i].title,
                                      amount: vm.administrativeFees[i].amount,
                                      onTitleChanged:
                                          vm.updateAdministrativeFeeTitle,
                                      onAmountChanged:
                                          vm.updateAdministrativeFeeAmount,
                                      onRemove: () =>
                                          vm.removeAdministrativeFeeRow(i),
                                    ),
                                  ),
                              ],

                              // Add Fee Button
                              Container(
                                width: double.infinity,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.grey[300]!,
                                    style: BorderStyle.solid,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: vm.addAdministrativeFeeRow,
                                  borderRadius: BorderRadius.circular(10),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add,
                                        color: Colors.grey[600],
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        loc.translate('addAdministrativeFee'),
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 14),

                              _LabelWithCurrency(loc.translate('total')),
                              _TextFieldIcon(
                                iconAsset: 'assets/icons/price-lable.svg',
                                hint: loc.translate('autoOrManual'),
                                value: vm.admTotal,
                                onChanged: vm.setAdmTotal,
                                keyboardType: TextInputType.number,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ===== OFFICE =====
                      _CollapsibleSection(
                        title: loc.translate('officeInformation'),
                        child: _SectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Label(loc.translate('officeName')),
                              _TextFieldIcon(
                                iconAsset: 'assets/icons/offices-lable.svg',
                                hint: loc.translate('enterOfficeName'),
                                value: vm.officeName,
                                onChanged: vm.setOfficeName,
                              ),
                              const SizedBox(height: 14),
                              _Label(loc.translate('officeLogo')),
                              _LogoUploadBox(
                                uploadedFileName: vm.officeLogoFileName,
                                onTap: () => vm.selectLogo(context),
                                onClear: () => vm.clearLogo(),
                                localization: loc,
                                showImagePreview: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Fixed buttons at bottom - hide when keyboard is visible
                if (keyboardHeight == 0)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            offset: const Offset(0, -2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: SaveCancelButtons(
                        isLoading: vm.isLoading,
                        isEnabled: vm.hasAnyContent,
                        isEditMode:
                            false, // Quotation doesn't have mode like other add screens
                        onSave: () => vm.save(context),
                        onCancel: () => vm.cancel(context),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Generate a preview of the welcome message template
  String _generateWelcomeMessagePreview(
      AddQuotationViewModel vm, AppLocalizations loc) {
    final officeName = vm.officeName.trim().isNotEmpty
        ? vm.officeName
        : (loc.translate('ourOffice') != 'ourOffice'
            ? loc.translate('ourOffice')
            : 'Our Office');
    final propertyType = vm.propertyType.trim().isNotEmpty
        ? vm.propertyType.toLowerCase()
        : (loc.translate('property') != 'property'
            ? loc.translate('property')
            : 'property');

    final hasParking = vm.parking;
    final hasAmount = vm.totalAmount.trim().isNotEmpty;
    final hasInstallments = vm.numberOfInstallments.trim().isNotEmpty;

    // Build dynamic localized message with fallbacks
    String message = _getLocalizedWithFallback(
            loc, 'welcomeToOffice', 'Welcome to {officeName}!')
        .replaceAll('{officeName}', officeName);
    message += ' ';
    message += _getLocalizedWithFallback(loc, 'quotationIntro',
        'We are pleased to present this comprehensive quotation for');
    message += ' ';

    if (vm.propertyTitle.trim().isNotEmpty) {
      message += _getLocalizedWithFallback(loc, 'namedPremiumProperty',
              '"{propertyTitle}" - a premium {propertyType}')
          .replaceAll('{propertyTitle}', vm.propertyTitle)
          .replaceAll('{propertyType}', propertyType);
    } else {
      message += _getLocalizedWithFallback(
              loc, 'premiumProperty', 'a premium {propertyType}')
          .replaceAll('{propertyType}', propertyType);
    }

    if (hasParking) {
      message += ' ';
      message += _getLocalizedWithFallback(loc, 'withParkingFacilities',
          'featuring dedicated parking facilities');
    }

    if (vm.startDate.trim().isNotEmpty && vm.endDate.trim().isNotEmpty) {
      message += ' ';
      message += _getLocalizedWithFallback(
              loc, 'availableFromTo', 'available from {startDate} to {endDate}')
          .replaceAll('{startDate}', vm.startDate)
          .replaceAll('{endDate}', vm.endDate);
    }

    message += '. ';

    if (hasAmount) {
      message += _getLocalizedWithFallback(
          loc, 'competitivePricing', 'This offer includes competitive pricing');
      if (hasInstallments) {
        message += ' ';
        message += _getLocalizedWithFallback(
            loc, 'flexibleInstallments', 'with flexible installment options');
      }
      message += '. ';
    }

    message += _getLocalizedWithFallback(loc, 'exceptionalService',
        'We are committed to providing exceptional service and look forward to building a successful partnership with you.');

    return message;
  }

  /// Helper function to get localized text with fallback
  String _getLocalizedWithFallback(
      AppLocalizations loc, String key, String fallback) {
    final translated = loc.translate(key);
    return translated == key ? fallback : translated;
  }
}

// ==================== UI COMPONENTS ====================

class _CollapsibleSection extends StatefulWidget {
  final String title;
  final Widget child;
  final VoidCallback? onExpanded; // Add callback for when section is expanded
  const _CollapsibleSection({
    required this.title,
    required this.child,
    this.onExpanded,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection>
    with TickerProviderStateMixin {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: Color.fromARGB((0.15 * 255).round(), colors.outline.red,
                colors.outline.green, colors.outline.blue)),
      ),
      child: Column(
        children: [
          // Header (tap to expand/collapse)
          InkWell(
            onTap: () {
              setState(() => _expanded = !_expanded);
              // Trigger callback when expanding
              if (_expanded && widget.onExpanded != null) {
                widget.onExpanded!();
              }
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                      child:
                          Text(widget.title, style: AppTextStyles.appBarTitle)),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 200),
                    turns: _expanded ? 0.5 : 0.0,
                    child:
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 24),
                  ),
                ],
              ),
            ),
          ),
          // Body
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: widget.child,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 7, start: 2, top: 2),
      child: Text(text, style: AppTextStyles.sectionLabel),
    );
  }
}

class _LabelWithCurrency extends StatelessWidget {
  final String text;
  const _LabelWithCurrency(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 7, start: 2),
      child: Row(
        children: [
          Text(text, style: AppTextStyles.sectionLabel),
          const SizedBox(width: 8),
          Text('(', style: AppTextStyles.sectionLabel),
          Image.asset(
            'assets/images/UAE_Dirham.png',
            width: 16,
            height: 16,
            color: const Color(0xFF8B959A),
          ),
          Text(')', style: AppTextStyles.sectionLabel),
        ],
      ),
    );
  }
}

class _TextFieldIcon extends StatefulWidget {
  final String? iconAsset;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final bool readOnly;
  final VoidCallback? onTap;

  const _TextFieldIcon({
    this.iconAsset,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.keyboardType,
    this.readOnly = false,
    this.onTap,
  });

  @override
  State<_TextFieldIcon> createState() => _TextFieldIconState();
}

class _TextFieldIconState extends State<_TextFieldIcon> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_TextFieldIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          if (widget.iconAsset != null)
            SvgPicture.asset(
              widget.iconAsset!,
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(
                Color(0xFF8B959A),
                BlendMode.srcIn,
              ),
            ),
          if (widget.iconAsset != null) const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              keyboardType: widget.keyboardType,
              readOnly: widget.readOnly,
              onTap: widget.onTap,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: AppTextStyles.hintText,
              ),
              style: AppTextStyles.bodyText,
              onChanged: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _DatePickerField extends StatefulWidget {
  final String? iconAsset;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;

  const _DatePickerField({
    this.iconAsset,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_DatePickerField> createState() => _DatePickerFieldState();
}

class _DatePickerFieldState extends State<_DatePickerField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_DatePickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    // Parse existing date or use current date as default
    DateTime initialDate = DateTime.now();
    if (widget.value.isNotEmpty) {
      try {
        initialDate = DateTime.parse(widget.value);
      } catch (e) {
        // If parsing fails, use current date
        initialDate = DateTime.now();
      }
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2050),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: const Color(0xFF02957D), // Calendar header color
                  onPrimary: Colors.white, // Header text color
                  surface: Theme.of(context).colorScheme.surface,
                  onSurface: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      // Format date as YYYY-MM-DD
      final formattedDate =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';

      _controller.text = formattedDate;
      widget.onChanged(formattedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          if (widget.iconAsset != null)
            SvgPicture.asset(
              widget.iconAsset!,
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(
                Color(0xFF8B959A),
                BlendMode.srcIn,
              ),
            ),
          if (widget.iconAsset != null) const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              readOnly: true, // Make field read-only to force date picker usage
              onTap: _selectDate,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: AppTextStyles.hintText,
                suffixIcon: const Icon(
                  Icons.calendar_today,
                  size: 20,
                  color: Color(0xFF8B959A),
                ),
              ),
              style: AppTextStyles.bodyText,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartDatePickerField extends StatefulWidget {
  final String? iconAsset;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;
  final bool isStartDate;

  const _SmartDatePickerField({
    this.iconAsset,
    required this.hint,
    required this.value,
    required this.onChanged,
    this.isStartDate = false,
  });

  @override
  State<_SmartDatePickerField> createState() => _SmartDatePickerFieldState();
}

class _SmartDatePickerFieldState extends State<_SmartDatePickerField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_SmartDatePickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    // Parse existing date or use current date as default
    DateTime initialDate = DateTime.now();
    if (widget.value.isNotEmpty) {
      try {
        initialDate = DateTime.parse(widget.value);
      } catch (e) {
        // If parsing fails, use current date
        initialDate = DateTime.now();
      }
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2050),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.primary, // Calendar header color
                  onPrimary: Colors.white, // Header text color
                  surface: Theme.of(context).colorScheme.surface,
                  onSurface: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      // Format date as YYYY-MM-DD
      final formattedDate =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';

      _controller.text = formattedDate;
      widget.onChanged(formattedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          if (widget.iconAsset != null)
            SvgPicture.asset(
              widget.iconAsset!,
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(
                Color(0xFF8B959A),
                BlendMode.srcIn,
              ),
            ),
          if (widget.iconAsset != null) const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              readOnly: true, // Make field read-only to force date picker usage
              onTap: _selectDate,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: AppTextStyles.hintText,
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.isStartDate) const SizedBox(width: 14),
                    const Icon(
                      Icons.calendar_today,
                      size: 20,
                      color: Color(0xFF8B959A),
                    ),
                  ],
                ),
              ),
              style: AppTextStyles.bodyText,
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoCalculatedDateField extends StatefulWidget {
  final String? iconAsset;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;

  const _AutoCalculatedDateField({
    this.iconAsset,
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_AutoCalculatedDateField> createState() =>
      _AutoCalculatedDateFieldState();
}

class _AutoCalculatedDateFieldState extends State<_AutoCalculatedDateField> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_AutoCalculatedDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final loc = AppLocalizations.of(context);
    // Show confirmation dialog for manual override
    final bool? shouldOverride = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.translate('overrideEndDate')),
        content: Text(loc.translate('overrideEndDateMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(loc.translate('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(loc.translate('override')),
          ),
        ],
      ),
    );

    if (shouldOverride != true) return;

    // Parse existing date or use current date as default
    DateTime initialDate = DateTime.now();
    if (widget.value.isNotEmpty) {
      try {
        initialDate = DateTime.parse(widget.value);
      } catch (e) {
        initialDate = DateTime.now();
      }
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2050),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.primary,
                  onPrimary: Colors.white,
                  surface: Theme.of(context).colorScheme.surface,
                  onSurface: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formattedDate =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';

      _controller.text = formattedDate;
      widget.onChanged(formattedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bool hasValue = widget.value.isNotEmpty;

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color:
            hasValue ? colors.surface : colors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: hasValue
            ? Border.all(color: colors.primary.withValues(alpha: 0.3), width: 1)
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          if (widget.iconAsset != null)
            SvgPicture.asset(
              widget.iconAsset!,
              width: 24,
              height: 24,
              colorFilter: const ColorFilter.mode(
                Color(0xFF8B959A),
                BlendMode.srcIn,
              ),
            ),
          if (widget.iconAsset != null) const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              readOnly: true,
              onTap: _selectDate,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: AppTextStyles.hintText.copyWith(
                  color:
                      hasValue ? colors.primary.withValues(alpha: 0.7) : null,
                  fontSize: hasValue ? 13 : null,
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(width: 14),
                    const Icon(
                      Icons.calendar_today,
                      size: 20,
                      color: Color(0xFF8B959A),
                    ),
                  ],
                ),
              ),
              style: AppTextStyles.bodyText.copyWith(
                color: hasValue ? colors.primary : null,
                fontWeight: hasValue ? FontWeight.w500 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotesBox extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String hint;

  const _NotesBox({
    required this.value,
    required this.onChanged,
    required this.hint,
  });

  @override
  State<_NotesBox> createState() => _NotesBoxState();
}

class _NotesBoxState extends State<_NotesBox> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_NotesBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 84),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: _controller,
        minLines: 3,
        maxLines: 7,
        decoration: InputDecoration.collapsed(
          hintText: widget.hint,
          hintStyle: AppTextStyles.hintText,
        ),
        style: AppTextStyles.bodyText,
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _LogoUploadBox extends StatelessWidget {
  final String uploadedFileName;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final AppLocalizations localization;
  final bool showImagePreview;

  const _LogoUploadBox({
    required this.uploadedFileName,
    required this.onTap,
    this.onClear,
    required this.localization,
    this.showImagePreview = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasFile = uploadedFileName.isNotEmpty;

    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(Icons.attach_file, size: 22, color: Color(0xFF8B959A)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasFile
                  ? uploadedFileName
                  : localization.translate('uploadOfficeLogo'),
              style: AppTextStyles.hintText,
            ),
          ),
          // Clear button - only show when file is selected
          if (hasFile && onClear != null) ...[
            GestureDetector(
              onTap: onClear,
              child: Container(
                margin: const EdgeInsets.all(7),
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.red.shade400,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.clear,
                  color: Colors.white,
                  size: 25,
                ),
              ),
            ),
          ],
          // Upload button
          GestureDetector(
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.all(7),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SvgPicture.asset(
                'assets/icons/upload-media.svg',
                width: 25,
                height: 25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String labelOn;
  final String labelOff;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.labelOn,
    required this.labelOff,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child:
                Text(value ? labelOn : labelOff, style: AppTextStyles.bodyText),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _PaymentTypeChips extends StatelessWidget {
  final String value; // 'cash' | 'cheque' | 'bankTransfer'
  final ValueChanged<String> onChanged;
  final String cashLabel;
  final String chequeLabel;
  final String bankLabel;

  const _PaymentTypeChips({
    required this.value,
    required this.onChanged,
    required this.cashLabel,
    required this.chequeLabel,
    required this.bankLabel,
  });

  @override
  Widget build(BuildContext context) {
    final options = <String, String>{
      'cash': cashLabel,
      'cheque': chequeLabel,
      'bankTransfer': bankLabel,
    };
    return Wrap(
      spacing: 8,
      children: options.entries.map((e) {
        final selected = value == e.key;
        return ChoiceChip(
          label: Text(e.value),
          selected: selected,
          onSelected: (_) => onChanged(e.key),
        );
      }).toList(),
    );
  }
}

class _HelperLabelRow extends StatelessWidget {
  final List<String> labels;
  const _HelperLabelRow({required this.labels});

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.hintText;
    return LayoutBuilder(
      builder: (context, c) {
        return Wrap(
          spacing: 16,
          runSpacing: 6,
          children: labels.map((t) => Text(t, style: style)).toList(),
        );
      },
    );
  }
}

class _DownpaymentRow extends StatelessWidget {
  final int index;
  final String method; // 'cash' | 'cheque' | 'bankTransfer' | 'other'
  final String number;
  final String date; // free-form string for now
  final String amount;

  final ValueChanged<String> onMethodChanged;
  final ValueChanged<String> onNumberChanged;
  final ValueChanged<String> onDateChanged;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onRemove;

  const _DownpaymentRow({
    required this.index,
    required this.method,
    required this.number,
    required this.date,
    required this.amount,
    required this.onMethodChanged,
    required this.onNumberChanged,
    required this.onDateChanged,
    required this.onAmountChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          // First line: method + number
          Row(
            children: [
              Expanded(
                flex: 6,
                child: _DropdownField(
                  label:
                      AppLocalizations.of(context).translate('paymentMethod'),
                  value: method,
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'cheque', child: Text('Cheque')),
                    DropdownMenuItem(
                        value: 'bankTransfer', child: Text('Bank Transfer')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) => onMethodChanged(v ?? 'cash'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _SmallTextField(
                  hint: '1',
                  value: number,
                  onChanged: onNumberChanged, // will be ignored (readOnly)
                  keyboardType: TextInputType.number,
                  readOnly: true, // <---- auto-numbered
                ),
              ),
              const SizedBox(width: 44), // Space for delete button alignment
            ],
          ),
          const SizedBox(height: 8),

          // Second line: date + amount
          LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final buttonWidth = 44.0; // Delete button + spacing
              final spacingWidth = 12.0; // SizedBox widths
              final fieldWidth =
                  (availableWidth - buttonWidth - spacingWidth) / 2;

              return Row(
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: _SmallDateField(
                      hint: 'YYYY-MM-DD',
                      value: date, // prefilled like "2025-"
                      onChanged: onDateChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: fieldWidth,
                    child: _SmallTextField(
                      hint: AppLocalizations.of(context).translate('amount'),
                      value: amount,
                      onChanged: onAmountChanged,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 40,
                    child: IconButton(
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: AppLocalizations.of(context).translate('remove'),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// Add readOnly to small text field
class _SmallTextField extends StatefulWidget {
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final bool readOnly; // <----

  const _SmallTextField({
    required this.hint,
    required this.value,
    required this.onChanged,
    this.keyboardType,
    this.readOnly = false, // <----
  });

  @override
  State<_SmallTextField> createState() => _SmallTextFieldState();
}

class _SmallTextFieldState extends State<_SmallTextField> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _SmallTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (widget.readOnly) {
      // For read-only fields (like auto-numbered fields), use simple text display
      return Container(
        height: 52,
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        alignment: widget.keyboardType == TextInputType.number
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Text(
          _c.text.isEmpty ? widget.hint : _c.text,
          style: _c.text.isEmpty
              ? AppTextStyles.hintText.copyWith(fontSize: 14)
              : AppTextStyles.bodyText.copyWith(fontSize: 14),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      );
    }

    // For editable fields, use TextField but with better constraints
    return Container(
      height: 52,
      child: TextField(
        controller: _c,
        readOnly: widget.readOnly,
        keyboardType: widget.keyboardType,
        scrollPadding: EdgeInsets.zero,
        style: AppTextStyles.bodyText.copyWith(fontSize: 14),
        textAlign: widget.keyboardType == TextInputType.number
            ? TextAlign.end
            : TextAlign.start,
        maxLines: 1,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: AppTextStyles.hintText.copyWith(fontSize: 14),
          filled: true,
          fillColor: colors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          isDense: true,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _SmallDateField extends StatefulWidget {
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;

  const _SmallDateField({
    required this.hint,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_SmallDateField> createState() => _SmallDateFieldState();
}

class _SmallDateFieldState extends State<_SmallDateField> {
  late final TextEditingController _c;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _SmallDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    // Parse existing date or use current date as default
    DateTime initialDate = DateTime.now();
    if (widget.value.isNotEmpty) {
      try {
        initialDate = DateTime.parse(widget.value);
      } catch (e) {
        // If parsing fails, use current date
        initialDate = DateTime.now();
      }
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2050),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppColors.primary, // Calendar header color
                  onPrimary: Colors.white, // Header text color
                  surface: Theme.of(context).colorScheme.surface,
                  onSurface: Theme.of(context).colorScheme.onSurface,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      // Format date as YYYY-MM-DD
      final formattedDate =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';

      _c.text = formattedDate;
      widget.onChanged(formattedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _selectDate,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _c.text.isEmpty ? widget.hint : _c.text,
                    style: _c.text.isEmpty
                        ? AppTextStyles.hintText.copyWith(fontSize: 14)
                        : AppTextStyles.bodyText.copyWith(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.calendar_today,
                  size: 14,
                  color: Color(0xFF8B959A),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTextStyles.hintText,
        filled: true,
        fillColor: colors.surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value.isEmpty ? null : value,
          isExpanded: true,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _AdministrativeFeeRow extends StatelessWidget {
  final int index;
  final String title;
  final String amount;
  final Function(int, String) onTitleChanged;
  final Function(int, String) onAmountChanged;
  final VoidCallback onRemove;

  const _AdministrativeFeeRow({
    required this.index,
    required this.title,
    required this.amount,
    required this.onTitleChanged,
    required this.onAmountChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.translate('serviceName'),
                      style: AppTextStyles.sectionLabel,
                    ),
                    const SizedBox(height: 4),
                    _SmallTextField(
                      hint: loc.translate('serviceNameHint'),
                      value: title,
                      onChanged: (v) => onTitleChanged(index, v),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.translate('amount'),
                      style: AppTextStyles.sectionLabel,
                    ),
                    const SizedBox(height: 4),
                    _SmallTextField(
                      hint: '0.00',
                      value: amount,
                      onChanged: (v) => onAmountChanged(index, v),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
                color: Colors.red,
                iconSize: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Welcome Message Mode Selector Widget
class _WelcomeMessageModeSelector extends StatelessWidget {
  final WelcomeMessageMode mode;
  final ValueChanged<WelcomeMessageMode> onModeChanged;

  const _WelcomeMessageModeSelector({
    required this.mode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Auto mode option
        _WelcomeModeOption(
          title: loc.translate('useTemplateMessage'),
          subtitle: loc.translate('autoGenerateWelcomeMessage'),
          isSelected: mode == WelcomeMessageMode.auto,
          onTap: () => onModeChanged(WelcomeMessageMode.auto),
          icon: Icons.auto_awesome,
          colors: colors,
        ),
        const SizedBox(height: 8),

        // Custom mode option
        _WelcomeModeOption(
          title: loc.translate('customMessage'),
          subtitle: loc.translate('writeYourOwnWelcomeMessage'),
          isSelected: mode == WelcomeMessageMode.custom,
          onTap: () => onModeChanged(WelcomeMessageMode.custom),
          icon: Icons.edit,
          colors: colors,
        ),
        const SizedBox(height: 8),

        // Hidden mode option
        _WelcomeModeOption(
          title: loc.translate('hideWelcomeMessage'),
          subtitle: loc.translate('noWelcomeSectionInPdf'),
          isSelected: mode == WelcomeMessageMode.hidden,
          onTap: () => onModeChanged(WelcomeMessageMode.hidden),
          icon: Icons.visibility_off,
          colors: colors,
        ),
      ],
    );
  }
}

// Individual welcome mode option widget
class _WelcomeModeOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final IconData icon;
  final ColorScheme colors;

  const _WelcomeModeOption({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    required this.icon,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isSelected
              ? colors.primary
              : colors.outline.withValues(alpha: 0.3),
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isSelected
            ? colors.primary.withValues(alpha: 0.08)
            : colors.surface,
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color: isSelected ? colors.primary : colors.onSurfaceVariant,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? colors.primary : colors.onSurface,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 8,
            color: isSelected
                ? colors.primary.withValues(alpha: 0.7)
                : colors.onSurfaceVariant,
          ),
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle, color: colors.primary)
            : Icon(Icons.radio_button_unchecked,
                color: colors.onSurfaceVariant.withValues(alpha: 0.5)),
      ),
    );
  }
}
