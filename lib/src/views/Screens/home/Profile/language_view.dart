import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:broker_wallet/src/Views/Widgets/language_option_tile.dart';
import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
import 'package:broker_wallet/src/viewmodels/locale_viewmodel.dart';
import 'package:broker_wallet/src/viewmodels/language_viewmodel.dart';
import 'package:broker_wallet/src/Views/Widgets/back_arrow_button.dart';

class LanguageView extends StatelessWidget {
  const LanguageView({super.key});

  static const double kHorizontalPadding =
      32; // <<-- Adjust for WIDER tiles and button

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LanguageViewModel(
        localeVM: context.read<LocaleViewModel>(),
      ),
      child: Consumer<LanguageViewModel>(
        builder: (context, vm, _) {
          final loc = AppLocalizations.of(context);
          final colors = Theme.of(context).colorScheme;
          final texts = Theme.of(context).textTheme;

          return Scaffold(
            appBar: AppBar(
              leading: const BackArrowButton(),
              title: Text(
                loc.translate('selectLanguage'),
                style: texts.titleLarge,
              ),
              centerTitle: true,
              elevation: 0,
              backgroundColor: colors.surface,
            ),
            body: Column(
              children: [
                const SizedBox(height: 22),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: kHorizontalPadding),
                    itemCount: vm.options.length,
                    itemBuilder: (_, index) {
                      final option = vm.options[index];
                      return LanguageOptionTile(
                        option: option,
                        isSelected: vm.selected == option.locale,
                        onTap: () => vm.select(option.locale),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      kHorizontalPadding, 20, kHorizontalPadding, 30),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 50),
                      ),
                      onPressed: () {
                        vm.save();
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(
                              '/profile'); // or whatever your profile route is
                        }
                      },
                      child: Text(loc.translate('save')),
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
}
