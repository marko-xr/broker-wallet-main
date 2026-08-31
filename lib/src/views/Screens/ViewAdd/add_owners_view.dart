import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/input_phone_validation.dart';
import 'package:broker_wallet/src/Views/Widgets/media_upload_widget.dart';
import 'package:broker_wallet/src/Views/Widgets/pickup_location_widget.dart';
import 'package:broker_wallet/src/Views/Widgets/save_cancel_buttons.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/AddScreens/add_owners_viewmodel.dart';
import 'package:broker_wallet/src/common/enums/add_owners_mode.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/owners_model.dart';

class AddOwnersView extends StatelessWidget {
  final AddOwnersMode mode;
  final String? ownerId;
  final OwnerModel? ownerData;

  const AddOwnersView({
    super.key,
    this.mode = AddOwnersMode.add,
    this.ownerId,
    this.ownerData,
  });

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);

    return ChangeNotifierProvider<AddOwnersViewModel>(
      create: (context) => AddOwnersViewModel(
        mode: mode,
        ownerId: ownerId,
        ownerData: ownerData,
      ),
      child: Consumer<AddOwnersViewModel>(
        builder: (context, vm, child) {
          final colors = Theme.of(context).colorScheme;

          return Scaffold(
            backgroundColor: colors.surface,
            resizeToAvoidBottomInset: false, // Prevent keyboard from moving
            appBar: AppBar(
              leading: const BackArrowButton(),
              title: Text(localization.translate('owners'),
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
                        top: 20,
                        bottom: keyboardHeight > 0
                            ? keyboardHeight + 20
                            : 100, // Dynamic bottom padding
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Label(localization.translate('name')),
                          _TextFieldIcon(
                            iconAsset: 'assets/icons/profile-person.svg',
                            hint: localization.translate('enterOwnersName'),
                            value: vm.name,
                            onChanged: vm.setName,
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
                          _Label(localization.translate('typeOfProperties')),
                          _TextFieldIcon(
                            iconAsset: 'assets/icons/building-property.svg',
                            hint: localization.translate('enterPropertiesType'),
                            value: vm.typeOfProperties,
                            onChanged: vm.setTypeOfProperties,
                          ),
                          const SizedBox(height: 18),
                          _Label(localization.translate('propertyLocation')),
                          _TextFieldIcon(
                            icon: Icons.location_on_outlined,
                            hint:
                                localization.translate('enterPropertyLocation'),
                            value: vm.propertyLocation,
                            onChanged: vm.setPropertyLocation,
                          ),
                          const SizedBox(height: 18),
                          _Label(localization.translate('notes')),
                          _NotesBox(
                            value: vm.notes,
                            onChanged: vm.setNotes,
                            hint: localization.translate('notesHint'),
                          ),
                          const SizedBox(height: 18),
                          _Label(localization.translate('pickUpLocation')),
                          PickUpInputWidget(
                            value: vm.pickUpLocation,
                            onChanged: vm.setPickUpLocation,
                            hint: localization.translate('pickUpLocationHint'),
                            localization: localization,
                            viewModel:
                                vm, // Pass the ViewModel for location features
                          ),
                          const SizedBox(height: 18),
                          _Label(localization.translate('uploadMedia')),
                          MediaUploadWidget(
                            selectedFiles: vm.selectedFiles,
                            existingFileUrls: vm.uploadedFileUrls,
                            onSelectMedia: () => vm.selectMedia(context),
                            onRemoveFile: vm.removeFile,
                            onRemoveExistingFile: vm.removeUploadedFile,
                            onClearAll: vm.clearAllFiles,
                            isUploading: vm.isUploading,
                            localization: localization,
                            maxDisplayFiles: 3, // Standardized to 3 like offers
                            showUploadButton:
                                false, // Disable upload button - we save immediately
                            showImagePreview: false,
                            hintText: localization.translate('uploadMediaHint'),
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
                            isEditMode: mode == AddOwnersMode.edit,
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
// --- WIDGETS ---

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 7, start: 2),
      child: Text(text, style: AppTextStyles.sectionLabel),
    );
  }
}

class _TextFieldIcon extends StatefulWidget {
  final IconData? icon;
  final String? iconAsset;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;

  const _TextFieldIcon({
    this.icon,
    this.iconAsset,
    required this.hint,
    required this.value,
    required this.onChanged,
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
          if (widget.icon != null)
            Icon(widget.icon, color: const Color(0xFF8B959A), size: 24)
          else if (widget.iconAsset != null)
            SvgPicture.asset(
              widget.iconAsset!,
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(
                colors.primary,
                BlendMode.srcIn,
              ),
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
