import 'package:broker_wallet/src/Views/Widgets/save_cancel_buttons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/input_phone_validation.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/utils/images.dart';
import 'package:broker_wallet/src/viewmodels/AddScreens/add_requested_viewmodel.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/common/enums/add_requested_mode.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/request_model.dart';

class AddRequestedView extends StatelessWidget {
  final AddRequestedMode mode;
  final String? requestId;
  final RequestModel? requestData;

  const AddRequestedView({
    super.key,
    this.mode = AddRequestedMode.add,
    this.requestId,
    this.requestData,
  });

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);

    return ChangeNotifierProvider(
      create: (_) => AddRequestedViewModel(
        mode: mode,
        requestId: requestId,
        requestData: requestData,
      ),
      child: Consumer<AddRequestedViewModel>(
        builder: (context, vm, _) {
          final theme = Theme.of(context);
          final colors = theme.colorScheme;

          return Scaffold(
            backgroundColor: colors.surface,
            resizeToAvoidBottomInset: false, // Prevent keyboard from moving

            appBar: AppBar(
              leading: const BackArrowButton(),
              title: Text(
                  vm.isEditMode
                      ? localization.translate('editRequest')
                      : localization.translate('requested'),
                  style: AppTextStyles.appBarTitle),
              centerTitle: true,
              elevation: 0,
              backgroundColor: colors.surface,
            ),
            body: Builder(
              builder: (context) {
                // Detect keyboard visibility
                final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Scrollable content
                    SingleChildScrollView(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 8,
                        bottom: keyboardHeight > 0
                            ? keyboardHeight + 20
                            : 100, // Dynamic bottom padding
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Rent/Sell tab
                          _RentSellTabs(
                            tab: vm.tab,
                            onChanged: vm.setTab,
                            localization: localization,
                          ),
                          const SizedBox(height: 18),
                          _Label(localization.translate('selectTheCity')),
                          _CityChips(
                            cities: vm.cities,
                            selected: vm.selectedCity,
                            onSelect: vm.selectCity,
                            localization: localization,
                          ),
                          const SizedBox(height: 18),
                          _Label(localization.translate('location')),
                          _LocationInput(
                            value: vm.location,
                            onChanged: (v) => vm.location = v,
                            hint: localization.translate('locationHint'),
                          ),
                          const SizedBox(height: 18),
                          _Label(localization.translate('phoneNumber')),
                          PhoneInputWidget(
                            countryCode: vm.countryCode,
                            value: vm.phone,
                            onChanged: vm.setPhone,
                            localization: localization,
                            phoneError: vm.phoneError,
                            showError: vm.phone.isNotEmpty,
                          ),
                          const SizedBox(height: 18),
                          _Label(localization.translate('priceRange')),
                          Row(
                            children: [
                              Expanded(
                                child: _PriceBox(
                                  value: vm.minPrice,
                                  onChanged: (v) => vm.minPrice = v,
                                  hint: localization.translate('minimumPrice'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _PriceBox(
                                  value: vm.maxPrice,
                                  onChanged: (v) => vm.maxPrice = v,
                                  hint: localization.translate('maximumPrice'),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 18),
                          _Label(localization.translate('squareFootage')),
                          _SquareFootageBox(
                            value: vm.squareFootage,
                            onChanged: vm.setSquareFootage,
                            hint: localization.translate('squareFootageHint'),
                          ),

                          const SizedBox(height: 18),
                          _Label(localization.translate('notes')),
                          _NotesBox(
                            value: vm.notes,
                            onChanged: (v) => vm.notes = v,
                            hint: localization.translate('notesHint'),
                          ),
                          const SizedBox(height: 18),
                          _Label(localization
                              .translate('typeOfRequestPropertiesAlt')),
                          _TypeChips(
                            type: vm.propertyType,
                            onSelect: vm.setPropertyType,
                            localization: localization,
                          ),
                          const SizedBox(height: 18),
                          // Dynamic label and chips for specific property type
                          if (vm.propertyType != null) ...[
                            const SizedBox(height: 18),
                            // Dynamic label and chips for specific property type
                            _Label(
                              localization
                                  .translate('selectSpecificPropertyFor')
                                  .replaceFirst(
                                      '{propertyType}',
                                      localization.translate(
                                          _propertyTypeLabel(vm.propertyType))),
                            ),
                            _SpecificPropertyTypeChips(
                              types:
                                  vm.getSpecificPropertyTypes(vm.propertyType),
                              selected: vm.selectedSpecificPropertyType,
                              onSelect: vm.selectSpecificPropertyType,
                              localization: localization,
                            ),
                          ],

                          // Conditional rooms and bathrooms sections
                          if (_shouldShowRoomsAndBaths(
                              vm.selectedSpecificPropertyType)) ...[
                            const SizedBox(height: 18),
                            _Label(localization.translate('numberOfRooms')),
                            _NumbersRow(
                              count: 6,
                              selected: vm.rooms,
                              onSelect: vm.selectRooms,
                            ),
                            const SizedBox(height: 18),
                            _Label(localization.translate('numberOfBathrooms')),
                            _NumbersRow(
                              count: 6,
                              selected: vm.baths,
                              onSelect: vm.selectBaths,
                            ),
                          ],
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
                            isEditMode: mode == AddRequestedMode.edit,
                            onSave: () => vm.save(context),
                            onCancel: () => vm.cancel(context),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// Helper widgets below:

class _RentSellTabs extends StatelessWidget {
  final RequestTab tab;
  final ValueChanged<RequestTab> onChanged;
  final AppLocalizations localization;

  const _RentSellTabs({
    required this.tab,
    required this.onChanged,
    required this.localization,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(RequestTab.rent),
              child: Container(
                decoration: BoxDecoration(
                  color: tab == RequestTab.rent
                      ? colors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: Text(
                  localization.translate('rent'),
                  style: AppTextStyles.tabText.copyWith(
                    color: tab == RequestTab.rent
                        ? Colors.white
                        : colors.onSurface,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(RequestTab.sell),
              child: Container(
                decoration: BoxDecoration(
                  color: tab == RequestTab.sell
                      ? colors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: Text(
                  localization.translate('sale'),
                  style: AppTextStyles.tabText.copyWith(
                    color: tab == RequestTab.sell
                        ? Colors.white
                        : colors.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 7, start: 2),
      child: Text(
        text,
        style: AppTextStyles.sectionLabel,
      ),
    );
  }
}

class _CityChips extends StatelessWidget {
  final List<String> cities;
  final String selected;
  final ValueChanged<String> onSelect;
  final AppLocalizations localization;
  const _CityChips({
    required this.cities,
    required this.selected,
    required this.onSelect,
    required this.localization,
  });

  @override
  Widget build(BuildContext context) {
    if (selected.isEmpty) {
      // Show main city chips
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: cities.map((c) {
          final labelKey = _cityLocalizationKey(c);
          return GestureDetector(
            onTap: () => onSelect(c),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.3,
                ),
              ),
              child: Text(
                localization.translate(labelKey),
                style: AppTextStyles.chipText.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }).toList(),
      );
    } else {
      // Show selected city with areas
      return Consumer<AddRequestedViewModel>(
        builder: (context, vm, _) {
          final areas = _getResidentialAreas(selected);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          localization
                              .translate(_cityLocalizationKey(selected)),
                          style: AppTextStyles.chipText.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => onSelect(""),
                          child:
                              Icon(Icons.close, color: Colors.white, size: 18),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Areas selection - keep original style but allow multiple selection
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: areas.map((areaKey) {
                  final isSelected = vm.selectedAreas.contains(areaKey);
                  final canSelect = vm.selectedAreas.length < 3 || isSelected;

                  return GestureDetector(
                    onTap: canSelect ? () => vm.selectArea(areaKey) : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 9),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : canSelect
                                ? Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.07)
                                : Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : canSelect
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.3),
                          width: 1.3,
                        ),
                      ),
                      child: Text(
                        localization.translate(areaKey),
                        style: AppTextStyles.chipText.copyWith(
                          color: isSelected
                              ? Colors.white
                              : canSelect
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .primary
                                      .withValues(alpha: 0.4),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          );
        },
      );
    }
  }
}

// Helper to get the correct localization key for city
String _cityLocalizationKey(String city) {
  switch (city) {
    case "Dubai":
      return "dubai";
    case "Abu Dhabi":
      return "abuDhabi";
    case "Khor Fakkan":
      return "khorFakkan";
    case "Al Ain":
      return "alAin";
    case "Ras Al Khaimah":
      return "rasAlKhaimah";
    case "Fujairah":
      return "fujairah";
    case "Sharjah":
      return "sharjah";
    case "Ajman":
      return "ajman";
    case "Umm Al Quwain":
      return "ummAlQuwain";
    default:
      return city;
  }
}

// Helper to get residential area localization keys for a city
List<String> _getResidentialAreas(String city) {
  switch (city) {
    case "Dubai":
      return [
        "jumeirah",
        "alBarsha",
        "deira",
        "karama",
        "mirdif",
        "discoveryGardens",
        "burDubai",
        "jvc",
        "downtownDubai",
        "businessBay",
      ];
    case "Abu Dhabi":
      return [
        "alReemIsland",
        "alRahaBeach",
        "khalifaCity",
        "mohammedBinZayedCity",
        "baniyas",
        "alShamkha",
        "alMuroor",
        "alMaqtaa",
        "mussafah",
        "alBateen",
      ];
    case "Sharjah":
      return [
        "alNahdaSharjah",
        "muwaileh",
        "alMajaz",
        "alQasimia",
        "alTaawun",
        "abuShagara",
        "alYarmook",
        "alButina",
        "alKhan",
        "alFalah",
      ];
    case "Ajman":
      return [
        "alNuaimia",
        "alRashidiya",
        "alRawda",
        "alHelio",
        "alJurf",
        "alHamidiya",
        "alZahra",
        "alMowaihat",
        "emiratesCity",
        "ajmanIndustrialArea",
      ];
    case "Ras Al Khaimah":
      return [
        "alDhait",
        "alMairid",
        "alQurm",
        "alNakheel",
        "seihAlUraibi",
        "alJazeeraAlHamra",
        "alRams",
        "alUraibi",
        "alMamourah",
        "khuzam",
      ];
    case "Fujairah":
      return [
        "alFaseel",
        "madhab",
        "murbah",
        "qalaatAlFujairah",
        "dibbaFujairah",
        "alGurfa",
        "sakamkam",
        "alTawyeen",
        "dadna",
        "alBidya",
      ];
    case "Umm Al Quwain":
      return [
        "alRaafa",
        "alSalama",
        "alRamlah",
        "alMuroorUAQ",
        "alKhorUAQ",
        "alHadarah",
        "alHaditha",
        "falajAlMualla",
        "ummaquwainIndustrialArea",
        "alShabiya",
      ];
    case "Al Ain":
      return [
        "alJimi",
        "alAinIndustrialArea",
        "alMuwaiji",
        "alAmeriya",
        "alHili",
        "alMarkhaniya",
        "alYahar",
        "alQattara",
        "alKhabisi",
        "zakhir",
      ];
    default:
      return [];
  }
}

class _LocationInput extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String hint;

  const _LocationInput({
    required this.value,
    required this.onChanged,
    required this.hint,
  });

  @override
  State<_LocationInput> createState() => _LocationInputState();
}

class _LocationInputState extends State<_LocationInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_LocationInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
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
      height: 52,
      decoration: BoxDecoration(
        // color: AppColors.boxDecoration,
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          const Icon(
            Icons.location_on_outlined,
            color: Color(0xFF8B959A),
            size: 25,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
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

class _PriceBox extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String hint;

  const _PriceBox({
    required this.value,
    required this.onChanged,
    required this.hint,
  });

  @override
  State<_PriceBox> createState() => _PriceBoxState();
}

class _SquareFootageBox extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String hint;

  const _SquareFootageBox({
    required this.value,
    required this.onChanged,
    required this.hint,
  });

  @override
  State<_SquareFootageBox> createState() => _SquareFootageBoxState();
}

class _SquareFootageBoxState extends State<_SquareFootageBox> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_SquareFootageBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
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
      height: 52,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            Icons.square_foot,
            size: 22,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: AppTextStyles.hintText,
              ),
              style: AppTextStyles.bodyText,
              onChanged: widget.onChanged,
            ),
          ),
          Text(
            'sq ft',
            style: AppTextStyles.hintText.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceBoxState extends State<_PriceBox> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_PriceBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
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
      height: 52,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Image.asset(
            AppImages.uaeDirham,
            width: 18,
            height: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
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
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
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

class _TypeChips extends StatelessWidget {
  final PropertyType? type; // Made nullable
  final ValueChanged<PropertyType> onSelect;
  final AppLocalizations localization;
  const _TypeChips(
      {required this.type, required this.onSelect, required this.localization});

  @override
  Widget build(BuildContext context) {
    List<MapEntry<PropertyType, String>> types = [
      MapEntry(PropertyType.commercial, localization.translate('commercial')),
      MapEntry(PropertyType.residential, localization.translate('residential')),
      MapEntry(PropertyType.furnished, localization.translate('furnished')),
    ];
    return Wrap(
      spacing: 10,
      children: types.map((e) {
        final sel = e.key == type;
        return ChoiceChip(
          label: Text(e.value),
          selected: sel,
          showCheckmark: false,
          onSelected: (_) => onSelect(e.key),
          selectedColor: Theme.of(context).colorScheme.primary,
          labelStyle: TextStyle(
            color: sel ? Colors.white : Theme.of(context).colorScheme.onSurface,
            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }
}

class _SpecificPropertyTypeChips extends StatelessWidget {
  final List<String> types;
  final String selected;
  final ValueChanged<String> onSelect;
  final AppLocalizations localization;
  const _SpecificPropertyTypeChips({
    required this.types,
    required this.selected,
    required this.onSelect,
    required this.localization,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      children: types.map((t) {
        final sel = t == selected;
        return ChoiceChip(
          label: Text(localization.translate(_propertySubTypeKey(t))),
          selected: sel,
          showCheckmark: false,
          onSelected: (_) => onSelect(t),
          selectedColor: Theme.of(context).colorScheme.primary,
          labelStyle: TextStyle(
            color: sel ? Colors.white : Theme.of(context).colorScheme.onSurface,
            fontWeight: sel ? FontWeight.bold : FontWeight.normal,
          ),
        );
      }).toList(),
    );
  }
}

class _NumbersRow extends StatelessWidget {
  final int count;
  final int selected;
  final ValueChanged<int> onSelect;
  const _NumbersRow({
    required this.count,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: List.generate(count, (idx) {
        final sel = (idx + 1) == selected;
        return GestureDetector(
          onTap: () => onSelect(idx + 1),
          child: Container(
            width: 48,
            height: 40,
            margin: const EdgeInsets.only(right: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: sel
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              border: Border.all(
                color: sel
                    ? Theme.of(context).colorScheme.primary
                    : const Color(0xFFD9D9D9),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              (idx + 1).toString().padLeft(2, '0'),
              style: TextStyle(
                color: sel
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                fontSize: 16,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// Update the _propertyTypeLabel function to handle nullable type
String _propertyTypeLabel(PropertyType? type) {
  if (type == null) return "propertyType"; // Fallback key

  switch (type) {
    case PropertyType.residential:
      return "residential";
    case PropertyType.commercial:
      return "commercial";
    case PropertyType.furnished:
      return "furnished";
  }
}

bool _shouldShowRoomsAndBaths(String selectedPropertyType) {
  const allowedTypes = ['Villa', 'Apartment', 'Studio'];
  return allowedTypes.contains(selectedPropertyType);
}

String _propertySubTypeKey(String type) {
  // camel/snake/label mapping to arb keys
  switch (type.toLowerCase().replaceAll(' ', '').replaceAll('&', 'and')) {
    case "apartment":
      return "apartment";
    case "villa":
      return "villa";
    case "studio":
      return "studio";
    case "townhouse":
      return "townhouse";
    case "penthouse":
      return "penthouse";
    case "compound":
      return "compound";
    case "duplex":
      return "duplex";
    case "fullfloor":
      return "fullFloor";
    case "halffloor":
      return "halfFloor";
    case "wholebuilding":
      return "wholeBuilding";
    case "land":
      return "land";
    case "bulkrentunit":
      return "bulkRentUnit";
    case "bungalow":
      return "bungalow";
    case "hotelandhotelapartment":
    case "hotelhotelapartment":
      return "hotelAndHotelApartment";
    case "officespace":
      return "officeSpace";
    case "retail":
      return "retail";
    case "warehouse":
      return "warehouse";
    case "shop":
      return "shop";
    case "showroom":
      return "showRoom";
    case "bulksaleunit":
      return "bulkSaleUnit";
    case "factory":
      return "factory";
    case "laborcamp":
      return "laborCamp";
    case "staffaccommodation":
      return "staffAccommodation";
    case "businesscentre":
      return "businessCentre";
    case "farm":
      return "farm";
    case "offices":
      return "offices"; // fallback for 'Offices'
    default:
      return type;
  }
}
