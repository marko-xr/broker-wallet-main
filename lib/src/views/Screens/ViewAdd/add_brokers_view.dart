import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';
import 'package:broker_wallet/src/Views/Widgets/input_phone_validation.dart';
import 'package:broker_wallet/src/Views/Widgets/save_cancel_buttons.dart';
import 'package:provider/provider.dart';
import 'package:broker_wallet/src/constants/constants.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/AddScreens/add_brokers_viewmodel.dart';
import 'package:broker_wallet/src/common/enums/add_brokers_mode.dart';
import 'package:broker_wallet/src/data/models/ScreensModel/brokers_model.dart';

class AddBrokersView extends StatelessWidget {
  final AddBrokersMode mode;
  final String? brokerId;
  final BrokerModel? brokerData;

  const AddBrokersView({
    super.key,
    this.mode = AddBrokersMode.add,
    this.brokerId,
    this.brokerData,
  });

  @override
  Widget build(BuildContext context) {
    final localization = AppLocalizations.of(context);

    return ChangeNotifierProvider(
      create: (_) => AddBrokersViewModel(
        mode: mode,
        brokerId: brokerId,
        brokerData: brokerData,
      ),
      child: Consumer<AddBrokersViewModel>(
        builder: (context, vm, _) {
          final colors = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: colors.surface,
            resizeToAvoidBottomInset: false, // Prevent keyboard from moving
            appBar: AppBar(
              leading: const BackArrowButton(),
              title: Text(
                  mode == AddBrokersMode.edit
                      ? localization.translate('editBroker')
                      : localization.translate('brokers'),
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
                          // Show error if exists
                          if (vm.error != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: colors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: colors.error.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline,
                                      color: colors.error, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      vm.error!,
                                      style: TextStyle(
                                          color: colors.error, fontSize: 14),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: vm.clearError,
                                    icon: Icon(Icons.close,
                                        color: colors.error, size: 18),
                                    constraints: const BoxConstraints(),
                                    padding: EdgeInsets.zero,
                                  ),
                                ],
                              ),
                            ),

                          _Label(localization.translate('name')),
                          _TextFieldIcon(
                            iconAsset: 'assets/icons/profile-person.svg',
                            hint: localization.translate('enterBrokerName'),
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
                          _Label(localization.translate('notes')),
                          _NotesBox(
                            value: vm.notes,
                            onChanged: vm.setNotes,
                            hint: localization.translate('notesHint'),
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
                            isEditMode: mode == AddBrokersMode.edit,
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

// --- REUSABLE WIDGETS ---

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
  final String? iconAsset;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;

  const _TextFieldIcon({
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
